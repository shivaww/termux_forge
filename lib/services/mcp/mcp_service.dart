// ============================================================================
// TermuxForge — MCP Service
// Full Model Context Protocol integration: server management, tool discovery,
// invocation, health monitoring, and MCP-based web search / research.
// ============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:uuid/uuid.dart';

import 'package:nexon/services/mcp/mcp_types.dart';
import 'package:nexon/services/event_bus/event_bus.dart';
import 'package:nexon/services/event_bus/event_types.dart';

/// Manages MCP server connections, tool discovery, and tool invocation.
///
/// The MCP service acts as a bridge between TermuxForge and external MCP
/// servers. It supports stdio, SSE, and HTTP transports.
///
/// ## Example
///
/// ```dart
/// final mcp = MCPService.instance;
///
/// final server = MCPServer(
///   id: 'brave-search',
///   name: 'Brave Search MCP',
///   transport: MCPTransport.http,
///   uri: 'http://localhost:3000',
/// );
///
/// await mcp.addServer(server);
/// await mcp.discoverTools(server.id);
///
/// final result = await mcp.invokeTool(
///   serverId: server.id,
///   toolName: 'brave_web_search',
///   params: {'query': 'Flutter state management 2026'},
/// );
/// ```
class MCPService {
  // ---------------------------------------------------------------------------
  // Singleton
  // ---------------------------------------------------------------------------

  MCPService._internal();

  /// The global [MCPService] instance.
  static final MCPService instance = MCPService._internal();

  /// Factory constructor that returns the singleton [instance].
  factory MCPService() => instance;

  // ---------------------------------------------------------------------------
  // Internal state
  // ---------------------------------------------------------------------------

  /// Registered MCP servers keyed by ID.
  final Map<String, MCPServer> _servers = {};

  /// Cached tool lookup: toolName@serverId → MCPTool.
  final Map<String, MCPTool> _toolCache = {};

  /// Event bus reference.
  final EventBus _eventBus = EventBus.instance;

  /// HTTP client for HTTP/SSE transports.
  final HttpClient _httpClient = HttpClient();

  /// UUID generator.
  static const _uuid = Uuid();

  /// Health monitoring timer.
  Timer? _healthTimer;

  // ---------------------------------------------------------------------------
  // Server Management
  // ---------------------------------------------------------------------------

  /// Registers a new MCP server.
  ///
  /// Publishes an [MCPServerAdded] event.
  Future<void> addServer(MCPServer server) async {
    _servers[server.id] = server;

    _eventBus.publish(MCPServerAdded(
      serverId: server.id,
      serverName: server.name,
      transport: server.transport.name,
      source: 'MCPService',
    ));

    // Attempt initial health check.
    await checkHealth(server.id);
  }

  /// Removes the server with the given [serverId].
  ///
  /// Also removes all cached tools from that server.
  bool removeServer(String serverId) {
    final server = _servers.remove(serverId);
    if (server == null) return false;

    // Remove cached tools.
    _toolCache.removeWhere((key, tool) => tool.serverId == serverId);

    _eventBus.publish(MCPServerRemoved(
      serverId: serverId,
      source: 'MCPService',
    ));

    return true;
  }

  /// Returns all registered servers.
  List<MCPServer> listServers({MCPServerStatus? status}) {
    if (status != null) {
      return _servers.values.where((s) => s.status == status).toList();
    }
    return List.unmodifiable(_servers.values);
  }

  /// Returns the server with the given [serverId], or `null`.
  MCPServer? getServer(String serverId) => _servers[serverId];

  // ---------------------------------------------------------------------------
  // Tool Discovery
  // ---------------------------------------------------------------------------

  /// Discovers tools on the MCP server identified by [serverId].
  ///
  /// Uses the MCP `tools/list` method. Discovered tools are cached locally
  /// and stored on the [MCPServer] object.
  ///
  /// Publishes an [MCPToolDiscovered] event.
  Future<List<MCPTool>> discoverTools(String serverId) async {
    final server = _servers[serverId];
    if (server == null) {
      throw StateError('MCP server "$serverId" not found');
    }

    try {
      final responseData = await _sendMCPRequest(
        server: server,
        method: 'tools/list',
        params: {},
      );

      final toolsData = responseData['tools'] as List<dynamic>? ?? [];
      final tools = <MCPTool>[];

      for (final item in toolsData) {
        final toolData = item as Map<String, dynamic>;
        final tool = MCPTool(
          id: '${serverId}_${toolData['name']}',
          name: toolData['name'] as String,
          description: (toolData['description'] as String?) ?? '',
          inputSchema: (toolData['inputSchema'] as Map<String, dynamic>?) ?? {},
          serverId: serverId,
        );
        tools.add(tool);
        _toolCache['${tool.name}@$serverId'] = tool;
      }

      server.tools
        ..clear()
        ..addAll(tools);

      _eventBus.publish(MCPToolDiscovered(
        serverId: serverId,
        toolCount: tools.length,
        toolNames: tools.map((t) => t.name).toList(),
        source: 'MCPService',
      ));

      return tools;
    } catch (e) {
      throw StateError('Failed to discover tools on "$serverId": $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Tool Invocation
  // ---------------------------------------------------------------------------

  /// Invokes a tool on the specified MCP server.
  ///
  /// Publishes [MCPToolInvoked] events.
  Future<MCPToolResult> invokeTool({
    required String serverId,
    required String toolName,
    Map<String, dynamic> params = const {},
  }) async {
    final server = _servers[serverId];
    if (server == null) {
      return MCPToolResult(
        success: false,
        error: 'MCP server "$serverId" not found',
        serverId: serverId,
        toolName: toolName,
      );
    }

    final stopwatch = Stopwatch()..start();

    try {
      final responseData = await _sendMCPRequest(
        server: server,
        method: 'tools/call',
        params: {
          'name': toolName,
          'arguments': params,
        },
      );

      stopwatch.stop();

      _eventBus.publish(MCPToolInvoked(
        serverId: serverId,
        toolName: toolName,
        success: true,
        duration: stopwatch.elapsed,
        source: 'MCPService',
      ));

      return MCPToolResult(
        success: true,
        content: responseData['content'],
        serverId: serverId,
        toolName: toolName,
        duration: stopwatch.elapsed,
      );
    } catch (e) {
      stopwatch.stop();

      _eventBus.publish(MCPToolInvoked(
        serverId: serverId,
        toolName: toolName,
        success: false,
        duration: stopwatch.elapsed,
        source: 'MCPService',
      ));

      return MCPToolResult(
        success: false,
        error: 'MCP tool invocation failed: $e',
        serverId: serverId,
        toolName: toolName,
        duration: stopwatch.elapsed,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Health Monitoring
  // ---------------------------------------------------------------------------

  /// Checks the health of the MCP server identified by [serverId].
  ///
  /// Publishes an [MCPServerChecked] event.
  Future<bool> checkHealth(String serverId) async {
    final server = _servers[serverId];
    if (server == null) return false;

    final stopwatch = Stopwatch()..start();

    try {
      // Use a ping or initialize method to check connectivity.
      await _sendMCPRequest(
        server: server,
        method: 'ping',
        params: {},
      );

      stopwatch.stop();
      server.status = MCPServerStatus.online;
      server.lastHealthCheck = DateTime.now().toUtc();
      server.lastHealthLatencyMs = stopwatch.elapsedMilliseconds;

      _eventBus.publish(MCPServerChecked(
        serverId: serverId,
        healthy: true,
        latencyMs: stopwatch.elapsedMilliseconds,
        source: 'MCPService',
      ));

      return true;
    } catch (e) {
      stopwatch.stop();
      server.status = MCPServerStatus.offline;
      server.lastHealthCheck = DateTime.now().toUtc();
      server.lastHealthLatencyMs = stopwatch.elapsedMilliseconds;

      _eventBus.publish(MCPServerChecked(
        serverId: serverId,
        healthy: false,
        latencyMs: stopwatch.elapsedMilliseconds,
        source: 'MCPService',
      ));

      return false;
    }
  }

  /// Starts periodic health checking of all servers.
  void startHealthMonitoring({
    Duration interval = const Duration(minutes: 5),
  }) {
    _healthTimer?.cancel();
    _healthTimer = Timer.periodic(interval, (_) async {
      for (final serverId in _servers.keys.toList()) {
        await checkHealth(serverId);
      }
    });
  }

  /// Stops periodic health checking.
  void stopHealthMonitoring() {
    _healthTimer?.cancel();
    _healthTimer = null;
  }

  // ---------------------------------------------------------------------------
  // Convenience: Web Search & Research
  // ---------------------------------------------------------------------------

  /// Searches the web using the first available MCP web-search server.
  ///
  /// Looks for a server with a tool named 'brave_web_search',
  /// 'web_search', or similar.
  Future<MCPToolResult> searchWeb(String query) async {
    final searchTool = _findToolByPattern(['brave_web_search', 'web_search',
        'search', 'tavily_search']);

    if (searchTool == null) {
      return MCPToolResult(
        success: false,
        error: 'No web search MCP tool available. '
            'Add an MCP server with web search capability.',
        serverId: '',
        toolName: 'web_search',
      );
    }

    return invokeTool(
      serverId: searchTool.serverId,
      toolName: searchTool.name,
      params: {'query': query},
    );
  }

  /// Performs deep research via the first available MCP research server.
  Future<MCPToolResult> research(String query) async {
    final researchTool = _findToolByPattern([
      'deep_research', 'research', 'research_query',
    ]);

    if (researchTool == null) {
      return MCPToolResult(
        success: false,
        error: 'No research MCP tool available.',
        serverId: '',
        toolName: 'research',
      );
    }

    return invokeTool(
      serverId: researchTool.serverId,
      toolName: researchTool.name,
      params: {'query': query},
    );
  }

  // ---------------------------------------------------------------------------
  // Internal: MCP Request Transport
  // ---------------------------------------------------------------------------

  /// Sends an MCP JSON-RPC request to the given [server].
  ///
  /// Dispatches to the appropriate transport handler.
  Future<Map<String, dynamic>> _sendMCPRequest({
    required MCPServer server,
    required String method,
    required Map<String, dynamic> params,
  }) async {
    return switch (server.transport) {
      MCPTransport.http || MCPTransport.sse => _sendHTTPRequest(
          server: server, method: method, params: params),
      MCPTransport.stdio => _sendStdioRequest(
          server: server, method: method, params: params),
    };
  }

  /// Sends an MCP request over HTTP.
  Future<Map<String, dynamic>> _sendHTTPRequest({
    required MCPServer server,
    required String method,
    required Map<String, dynamic> params,
  }) async {
    final uri = Uri.parse(server.uri);
    final request = await _httpClient.postUrl(uri);
    request.headers.set('Content-Type', 'application/json');

    final body = {
      'jsonrpc': '2.0',
      'id': _uuid.v4(),
      'method': method,
      'params': params,
    };

    request.write(jsonEncode(body));
    final response = await request.close().timeout(
      const Duration(seconds: 30),
    );

    final responseBody = await response.transform(utf8.decoder).join();

    if (response.statusCode != 200) {
      throw HttpException(
        'MCP HTTP error ${response.statusCode}: $responseBody',
      );
    }

    final json = jsonDecode(responseBody) as Map<String, dynamic>;

    if (json.containsKey('error')) {
      final error = json['error'] as Map<String, dynamic>;
      throw Exception('MCP error: ${error['message']}');
    }

    return (json['result'] as Map<String, dynamic>?) ?? {};
  }

  /// Sends an MCP request over stdio.
  ///
  /// Spawns the server process if needed and communicates via stdin/stdout.
  Future<Map<String, dynamic>> _sendStdioRequest({
    required MCPServer server,
    required String method,
    required Map<String, dynamic> params,
  }) async {
    // TODO: Implement stdio transport with process management.
    // The stdio transport requires:
    // 1. Spawning the server process using `server.uri` as the command.
    // 2. Sending JSON-RPC messages via stdin.
    // 3. Reading JSON-RPC responses from stdout.
    // 4. Managing process lifecycle (keep-alive, restart on crash).
    //
    // For now, delegate to the Termux bridge for process spawning.
    throw UnimplementedError(
      'Stdio MCP transport not yet implemented. '
      'Use HTTP or SSE transport, or implement stdio via TermuxBridgeService.',
    );
  }

  // ---------------------------------------------------------------------------
  // Internal Helpers
  // ---------------------------------------------------------------------------

  /// Finds the first cached tool matching any of the given name patterns.
  MCPTool? _findToolByPattern(List<String> patterns) {
    for (final pattern in patterns) {
      for (final tool in _toolCache.values) {
        if (tool.name.toLowerCase().contains(pattern.toLowerCase())) {
          return tool;
        }
      }
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Cleanup
  // ---------------------------------------------------------------------------

  /// Removes all servers and clears caches.
  void reset() {
    stopHealthMonitoring();
    _servers.clear();
    _toolCache.clear();
  }

  /// Closes the HTTP client. Call only during app shutdown.
  void dispose() {
    stopHealthMonitoring();
    _httpClient.close(force: true);
  }
}
