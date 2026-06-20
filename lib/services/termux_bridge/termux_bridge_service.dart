// ============================================================================
// TermuxForge — Termux Bridge Service
// WebSocket communication layer to the localhost Python bridge process.
// ============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:uuid/uuid.dart';

import 'package:termux_forge/services/termux_bridge/bridge_protocol.dart';
import 'package:termux_forge/services/event_bus/event_bus.dart';
import 'package:termux_forge/services/event_bus/event_types.dart';

/// The connection state of the bridge.
enum BridgeConnectionState {
  /// Not connected and not attempting to connect.
  disconnected,

  /// Actively trying to establish a connection.
  connecting,

  /// Connected and ready for commands.
  connected,

  /// Connection was lost; attempting reconnection.
  reconnecting,
}

/// Communication layer between the Flutter app and the Termux Python bridge.
///
/// The bridge runs as a local Python process that provides shell access,
/// file operations, and other system interactions. Communication uses a
/// WebSocket transport with JSON-RPC 2.0 messages.
///
/// ## Architecture
///
/// ```
/// Flutter App ←→ [WebSocket] ←→ Python Bridge ←→ Termux / Shell
/// ```
///
/// ## Usage
///
/// ```dart
/// final bridge = TermuxBridgeService.instance;
/// await bridge.connect();
///
/// final response = await bridge.executeShell('ls -la');
/// print(response.stdout);
///
/// await bridge.disconnect();
/// ```
class TermuxBridgeService {
  // ---------------------------------------------------------------------------
  // Singleton
  // ---------------------------------------------------------------------------

  TermuxBridgeService._internal();

  /// The global [TermuxBridgeService] instance.
  static final TermuxBridgeService instance = TermuxBridgeService._internal();

  /// Factory constructor that returns the singleton [instance].
  factory TermuxBridgeService() => instance;

  // ---------------------------------------------------------------------------
  // Configuration
  // ---------------------------------------------------------------------------

  /// The WebSocket host. Defaults to localhost.
  String host = '127.0.0.1';

  /// The WebSocket port. Defaults to 8765.
  int port = 8765;

  /// Default command timeout.
  Duration defaultTimeout = const Duration(seconds: 30);

  /// Maximum reconnection attempts before giving up.
  int maxReconnectAttempts = 10;

  /// Delay between reconnection attempts.
  Duration reconnectDelay = const Duration(seconds: 2);

  // ---------------------------------------------------------------------------
  // Internal state
  // ---------------------------------------------------------------------------

  /// The underlying WebSocket connection.
  WebSocket? _socket;

  /// Current connection state.
  BridgeConnectionState _state = BridgeConnectionState.disconnected;

  /// Pending requests awaiting responses, keyed by request ID.
  final Map<String, Completer<BridgeResponse>> _pendingRequests = {};

  /// Queue of requests submitted while disconnected.
  final List<_QueuedRequest> _commandQueue = [];

  /// Complete history of commands sent through the bridge.
  final List<BridgeRequest> _commandHistory = [];

  /// Maximum history entries retained.
  static const int _maxHistory = 500;

  /// Subscription to the WebSocket stream.
  StreamSubscription<dynamic>? _socketSubscription;

  /// Reconnection attempt counter.
  int _reconnectAttempts = 0;

  /// Timer for reconnection backoff.
  Timer? _reconnectTimer;

  /// Timer for periodic health checks.
  Timer? _healthTimer;

  /// Event bus reference.
  final EventBus _eventBus = EventBus.instance;

  /// UUID generator.
  static const _uuid = Uuid();

  /// Stream controller for broadcasting connection state changes.
  final StreamController<BridgeConnectionState> _stateController =
      StreamController<BridgeConnectionState>.broadcast();

  /// Stream controller for streaming command output lines.
  final StreamController<String> _outputController =
      StreamController<String>.broadcast();

  // ---------------------------------------------------------------------------
  // Public getters
  // ---------------------------------------------------------------------------

  /// Whether the bridge is currently connected.
  bool get isConnected => _state == BridgeConnectionState.connected;

  /// The current connection state.
  BridgeConnectionState get connectionState => _state;

  /// A broadcast stream of connection state changes.
  Stream<BridgeConnectionState> get stateStream => _stateController.stream;

  /// A broadcast stream of raw output lines from commands.
  Stream<String> get outputStream => _outputController.stream;

  // ---------------------------------------------------------------------------
  // Connection Lifecycle
  // ---------------------------------------------------------------------------

  /// Connects to the Python bridge via WebSocket.
  ///
  /// If already connected, this is a no-op. If a connection attempt is
  /// already in progress, returns the same future.
  ///
  /// Throws [SocketException] if the bridge process is not reachable.
  Future<void> connect({String? customHost, int? customPort}) async {
    if (_state == BridgeConnectionState.connected) return;

    final targetHost = customHost ?? host;
    final targetPort = customPort ?? port;

    _setState(BridgeConnectionState.connecting);

    try {
      _socket = await WebSocket.connect(
        'ws://$targetHost:$targetPort',
      ).timeout(const Duration(seconds: 10));

      _socketSubscription = _socket!.listen(
        _onMessage,
        onError: _onError,
        onDone: _onDone,
      );

      _setState(BridgeConnectionState.connected);
      _reconnectAttempts = 0;

      // Flush queued commands.
      await _flushQueue();

      // Start health monitoring.
      _startHealthMonitoring();
    } catch (e) {
      _setState(BridgeConnectionState.disconnected);
      rethrow;
    }
  }

  /// Gracefully disconnects from the bridge.
  Future<void> disconnect() async {
    _healthTimer?.cancel();
    _reconnectTimer?.cancel();
    await _socketSubscription?.cancel();

    if (_socket != null) {
      await _socket!.close(WebSocketStatus.normalClosure, 'Client disconnect');
      _socket = null;
    }

    // Fail all pending requests.
    for (final entry in _pendingRequests.entries) {
      entry.value.complete(BridgeResponse(
        id: entry.key,
        error: const BridgeError(
          code: BridgeErrorCodes.notConnected,
          message: 'Bridge disconnected',
        ),
      ));
    }
    _pendingRequests.clear();

    _setState(BridgeConnectionState.disconnected);
  }

  // ---------------------------------------------------------------------------
  // Command Execution
  // ---------------------------------------------------------------------------

  /// Sends a raw [BridgeRequest] and returns the [BridgeResponse].
  ///
  /// If the bridge is disconnected, the command is queued and will be sent
  /// when the connection is re-established.
  Future<BridgeResponse> sendCommand(BridgeRequest request) async {
    _commandHistory.add(request);
    if (_commandHistory.length > _maxHistory) {
      _commandHistory.removeAt(0);
    }

    if (!isConnected) {
      // Queue the command for later.
      final completer = Completer<BridgeResponse>();
      _commandQueue.add(_QueuedRequest(request: request, completer: completer));
      return completer.future;
    }

    return _sendImmediate(request);
  }

  /// Convenience method to execute a shell command.
  ///
  /// Returns the [BridgeResponse] with stdout, stderr, and exit code.
  Future<BridgeResponse> executeShell(
    String command, {
    String? workingDirectory,
    Duration? timeout,
  }) async {
    if (!isConnected) {
      try {
        await connect();
      } catch (e) {
        return BridgeResponse(
          id: _uuid.v4(),
          error: BridgeError(
            code: BridgeErrorCodes.notConnected,
            message: 'Bridge is not reachable at ws://$host:$port: $e',
          ),
        );
      }
    }

    final request = BridgeRequest(
      id: _uuid.v4(),
      method: 'execute_command',
      params: {
        'command': command,
        if (workingDirectory != null) 'cwd': workingDirectory,
      },
      timeout: (timeout ?? defaultTimeout).inSeconds,
    );

    _eventBus.publish(ShellCommandRequested(
      command: command,
      workingDirectory: workingDirectory,
      source: 'TermuxBridge',
    ));

    final stopwatch = Stopwatch()..start();
    final response = await sendCommand(request);
    stopwatch.stop();

    _eventBus.publish(ShellCommandExecuted(
      command: command,
      exitCode: response.exitCode ?? -1,
      stdout: response.stdout,
      stderr: response.stderr,
      duration: stopwatch.elapsed,
      source: 'TermuxBridge',
    ));

    return response;
  }

  /// Returns the command history.
  ///
  /// Optionally limit to the last [limit] entries.
  List<BridgeRequest> getCommandHistory({int? limit}) {
    if (limit != null && _commandHistory.length > limit) {
      return _commandHistory.sublist(_commandHistory.length - limit);
    }
    return List.unmodifiable(_commandHistory);
  }

  // ---------------------------------------------------------------------------
  // Internal: WebSocket handling
  // ---------------------------------------------------------------------------

  Future<BridgeResponse> _sendImmediate(BridgeRequest request) async {
    final completer = Completer<BridgeResponse>();
    _pendingRequests[request.id] = completer;

    try {
      _socket!.add(request.toJsonString());
    } catch (e) {
      _pendingRequests.remove(request.id);
      return BridgeResponse(
        id: request.id,
        error: BridgeError(
          code: BridgeErrorCodes.internalError,
          message: 'Failed to send: $e',
        ),
      );
    }

    // Apply timeout.
    final timeoutDuration = request.timeout != null
        ? Duration(seconds: request.timeout!)
        : defaultTimeout;

    return completer.future.timeout(timeoutDuration, onTimeout: () {
      _pendingRequests.remove(request.id);
      return BridgeResponse(
        id: request.id,
        error: const BridgeError(
          code: BridgeErrorCodes.timeout,
          message: 'Request timed out',
        ),
      );
    });
  }

  void _onMessage(dynamic data) {
    try {
      final json = jsonDecode(data as String) as Map<String, dynamic>;

      // Handle streaming output broadcasts from Python bridge.
      if (json['type'] == 'output') {
        final streamName = json['stream']?.toString() ?? 'stdout';
        final line = json['line']?.toString() ?? '';
        _outputController.add('[$streamName] $line');
        return;
      }
      if (json.containsKey('stream') && !json.containsKey('id')) {
        final line = json['stream'].toString();
        _outputController.add(line);
        return;
      }

      final response = BridgeResponse.fromJson(json);
      final completer = _pendingRequests.remove(response.id);
      if (completer != null && !completer.isCompleted) {
        completer.complete(response);
      }
    } catch (e) {
      // Malformed message — log and ignore.
      // TODO: Forward to a logging service.
      // ignore: avoid_print
      print('[TermuxBridge] Malformed message: $e');
    }
  }

  void _onError(Object error) {
    // ignore: avoid_print
    print('[TermuxBridge] WebSocket error: $error');
    _attemptReconnect();
  }

  void _onDone() {
    if (_state != BridgeConnectionState.disconnected) {
      _attemptReconnect();
    }
  }

  // ---------------------------------------------------------------------------
  // Reconnection
  // ---------------------------------------------------------------------------

  void _attemptReconnect() {
    if (_state == BridgeConnectionState.disconnected) return;
    if (_reconnectAttempts >= maxReconnectAttempts) {
      _setState(BridgeConnectionState.disconnected);
      // Fail all pending.
      for (final c in _pendingRequests.values) {
        if (!c.isCompleted) {
          c.complete(BridgeResponse(
            id: 'unknown',
            error: const BridgeError(
              code: BridgeErrorCodes.notConnected,
              message: 'Max reconnect attempts exceeded',
            ),
          ));
        }
      }
      _pendingRequests.clear();
      return;
    }

    _setState(BridgeConnectionState.reconnecting);
    _reconnectAttempts++;

    final delay = reconnectDelay * _reconnectAttempts; // linear backoff
    _reconnectTimer = Timer(delay, () async {
      try {
        await connect();
      } catch (_) {
        _attemptReconnect();
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Health Monitoring
  // ---------------------------------------------------------------------------

  void _startHealthMonitoring() {
    _healthTimer?.cancel();
    _healthTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (!isConnected) return;
      try {
        final ping = BridgeRequest(
          id: _uuid.v4(),
          method: 'ping',
          timeout: 5,
        );
        final response = await _sendImmediate(ping);
        if (response.isError) {
          _attemptReconnect();
        }
      } catch (_) {
        _attemptReconnect();
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Queue Management
  // ---------------------------------------------------------------------------

  Future<void> _flushQueue() async {
    final queued = List<_QueuedRequest>.from(_commandQueue);
    _commandQueue.clear();

    for (final item in queued) {
      try {
        final response = await _sendImmediate(item.request);
        item.completer.complete(response);
      } catch (e) {
        item.completer.complete(BridgeResponse(
          id: item.request.id,
          error: BridgeError(
            code: BridgeErrorCodes.internalError,
            message: 'Queue flush error: $e',
          ),
        ));
      }
    }
  }

  // ---------------------------------------------------------------------------
  // State Management
  // ---------------------------------------------------------------------------

  void _setState(BridgeConnectionState newState) {
    if (_state == newState) return;
    _state = newState;
    if (!_stateController.isClosed) {
      _stateController.add(newState);
    }
  }

  // ---------------------------------------------------------------------------
  // Cleanup
  // ---------------------------------------------------------------------------

  /// Releases all resources. Call only during app shutdown.
  Future<void> dispose() async {
    await disconnect();
    await _stateController.close();
    await _outputController.close();
  }
}

/// Internal helper pairing a queued request with its completer.
class _QueuedRequest {
  final BridgeRequest request;
  final Completer<BridgeResponse> completer;

  const _QueuedRequest({required this.request, required this.completer});
}
