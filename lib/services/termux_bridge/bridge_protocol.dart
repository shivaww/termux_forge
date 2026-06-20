// ============================================================================
// TermuxForge — Bridge Protocol
// JSON-RPC data models for communication with the Python bridge process.
// ============================================================================

import 'dart:convert';

/// A JSON-RPC request sent to the Python bridge.
///
/// Follows a simplified JSON-RPC 2.0 structure.
///
/// ```json
/// {
///   "id": "req-abc",
///   "method": "execute_shell",
///   "params": {"command": "ls -la"},
///   "timeout": 30
/// }
/// ```
class BridgeRequest {
  /// Unique request identifier for correlating responses.
  final String id;

  /// The RPC method to invoke on the bridge (e.g., 'execute_shell').
  final String method;

  /// Parameters for the method.
  final Map<String, dynamic> params;

  /// Timeout in seconds. `null` means no explicit timeout.
  final int? timeout;

  /// When the request was created (UTC).
  final DateTime createdAt;

  BridgeRequest({
    required this.id,
    required this.method,
    this.params = const {},
    this.timeout,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now().toUtc();

  /// Serializes this request to a JSON string ready for transmission.
  String toJsonString() => jsonEncode(toJson());

  /// Converts to a JSON-serializable map.
  Map<String, dynamic> toJson() => {
        'jsonrpc': '2.0',
        'id': id,
        'method': method,
        'params': params,
        if (timeout != null) 'timeout': timeout,
      };

  /// Deserializes a [BridgeRequest] from a JSON map.
  factory BridgeRequest.fromJson(Map<String, dynamic> json) {
    return BridgeRequest(
      id: json['id'] as String,
      method: json['method'] as String,
      params: (json['params'] as Map<String, dynamic>?) ?? {},
      timeout: json['timeout'] as int?,
    );
  }

  @override
  String toString() => 'BridgeRequest($method, id=$id)';
}

/// A JSON-RPC response received from the Python bridge.
///
/// Contains either a successful result or an error, along with process
/// output details (stdout, stderr, exit code).
class BridgeResponse {
  /// The request ID this response correlates to.
  final String id;

  /// The result payload on success.
  final dynamic result;

  /// An error object on failure.
  final BridgeError? error;

  /// The process exit code (for shell commands).
  final int? exitCode;

  /// Standard output from the process.
  final String stdout;

  /// Standard error from the process.
  final String stderr;

  /// How long the bridge took to process the request.
  final Duration duration;

  /// When the response was received (UTC).
  final DateTime receivedAt;

  BridgeResponse({
    required this.id,
    this.result,
    this.error,
    this.exitCode,
    this.stdout = '',
    this.stderr = '',
    this.duration = Duration.zero,
    DateTime? receivedAt,
  }) : receivedAt = receivedAt ?? DateTime.now().toUtc();

  /// Whether the response indicates success (no error).
  bool get isSuccess => error == null;

  /// Whether the response indicates failure.
  bool get isError => error != null;

  /// Converts to a JSON-serializable map.
  Map<String, dynamic> toJson() => {
        'jsonrpc': '2.0',
        'id': id,
        'result': result,
        'error': error?.toJson(),
        'exitCode': exitCode,
        'stdout': stdout,
        'stderr': stderr,
        'durationMs': duration.inMilliseconds,
      };

  /// Deserializes a [BridgeResponse] from a JSON map.
  factory BridgeResponse.fromJson(Map<String, dynamic> json) {
    final result = json['result'];
    final resultMap = result is Map ? Map<String, dynamic>.from(result) : null;
    final durationMs = json['durationMs'] as int?;
    final durationSeconds = (resultMap?['duration'] as num?)?.toDouble();

    return BridgeResponse(
      id: json['id'].toString(),
      result: result,
      error: json['error'] != null
          ? BridgeError.fromJson(json['error'] as Map<String, dynamic>)
          : null,
      exitCode: (json['exitCode'] as int?) ?? (resultMap?['exitCode'] as int?),
      stdout: (json['stdout'] as String?) ??
          (resultMap?['stdout'] as String?) ??
          '',
      stderr: (json['stderr'] as String?) ??
          (resultMap?['stderr'] as String?) ??
          '',
      duration: durationMs != null
          ? Duration(milliseconds: durationMs)
          : Duration(milliseconds: ((durationSeconds ?? 0) * 1000).round()),
    );
  }

  @override
  String toString() =>
      'BridgeResponse(id=$id, success=$isSuccess, exit=$exitCode)';
}

/// A structured error in a [BridgeResponse].
class BridgeError {
  /// A machine-readable error code.
  final int code;

  /// A human-readable error message.
  final String message;

  /// Optional additional data about the error.
  final dynamic data;

  const BridgeError({
    required this.code,
    required this.message,
    this.data,
  });

  Map<String, dynamic> toJson() => {
        'code': code,
        'message': message,
        if (data != null) 'data': data,
      };

  factory BridgeError.fromJson(Map<String, dynamic> json) {
    return BridgeError(
      code: json['code'] as int,
      message: json['message'] as String,
      data: json['data'],
    );
  }

  @override
  String toString() => 'BridgeError($code: $message)';
}

/// Standard JSON-RPC error codes used by the bridge protocol.
abstract class BridgeErrorCodes {
  /// The method was not found.
  static const int methodNotFound = -32601;

  /// Invalid parameters.
  static const int invalidParams = -32602;

  /// Internal server error.
  static const int internalError = -32603;

  /// Request timed out.
  static const int timeout = -32000;

  /// Command execution failed.
  static const int executionFailed = -32001;

  /// Permission denied.
  static const int permissionDenied = -32002;

  /// Bridge is not connected.
  static const int notConnected = -32003;
}
