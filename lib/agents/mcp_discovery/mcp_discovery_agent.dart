// Copyright (c) 2026 TermuxForge. All rights reserved.
// SPDX-License-Identifier: MIT

/// **MCP Discovery Agent** — MCP server specialist.
///
/// Specialises in:
/// - Discovering available MCP servers (local, network, registry).
/// - Validating MCP server health and capabilities.
/// - Integrating discovered tools into the tool registry.
/// - Managing MCP server lifecycle (start, stop, restart).
/// - Protocol version negotiation and capability matching.
library;

import 'dart:async';

import 'package:uuid/uuid.dart';

import 'package:nexon/agents/base/agent_exports.dart';

const _uuid = Uuid();

/// Represents a discovered MCP server.
class McpServerInfo {
  const McpServerInfo({
    required this.id,
    required this.name,
    required this.transport,
    required this.endpoint,
    this.tools = const [],
    this.protocolVersion = '2024-11-05',
    this.isHealthy = false,
    this.lastChecked,
    this.metadata = const {},
  });

  /// Unique server identifier.
  final String id;

  /// Human-readable server name.
  final String name;

  /// Transport type: `'stdio'`, `'sse'`, `'streamable-http'`.
  final String transport;

  /// Connection endpoint (command or URL).
  final String endpoint;

  /// Tools exposed by this server.
  final List<String> tools;

  /// MCP protocol version.
  final String protocolVersion;

  /// Whether the last health check passed.
  final bool isHealthy;

  /// When the last health check was performed.
  final DateTime? lastChecked;

  /// Extra metadata.
  final Map<String, dynamic> metadata;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'transport': transport,
        'endpoint': endpoint,
        'tools': tools,
        'protocolVersion': protocolVersion,
        'isHealthy': isHealthy,
        'lastChecked': lastChecked?.toIso8601String(),
        'metadata': metadata,
      };
}

/// MCP discovery specialist agent.
///
/// Discovers, validates, and integrates MCP servers and their tools
/// into the TermuxForge tool registry.
class McpDiscoveryAgent extends BaseAgent {
  /// Creates a [McpDiscoveryAgent].
  McpDiscoveryAgent({
    super.id,
    super.name = 'MCP Discovery',
    super.assignedModel,
    super.metadata,
  }) : super(
          allowedTools: const [
            'read_file',
            'write_file',
            'run_command',
            'search_files',
          ],
        );

  @override
  AgentType get type => AgentType.mcpDiscovery;

  @override
  String get systemPrompt => '''
You are the **MCP Discovery Specialist** within the TermuxForge agentic IDE.

Your domain:
- MCP (Model Context Protocol) server discovery and management.
- Transport types: stdio, SSE, streamable HTTP.
- Server health validation and capability enumeration.
- Tool registration: mapping MCP tools → TermuxForge tool registry.
- Configuration management: mcp_config.json, server credentials.
- Error recovery: reconnection, fallback servers, timeout handling.

Discovery sources:
1. Local mcp_config.json configuration.
2. NPM global packages (e.g. @modelcontextprotocol/* servers).
3. Python packages (e.g. mcp-server-* via pip/uvx).
4. Network service discovery (mDNS, known endpoints).
5. Registry API (if available).

Rules:
1. Always validate server health before registering tools.
2. Store server metadata for fast reconnection.
3. Handle transport-specific connection details.
4. Report discovered capabilities to the orchestrator.
5. Implement graceful degradation when servers are unavailable.
6. Log all discovery events for observability.
''';

  @override
  List<ModelCapability> get preferredCapabilities => const [
        ModelCapability.reasoning,
        ModelCapability.toolUse,
      ];

  /// Registry of discovered MCP servers.
  final Map<String, McpServerInfo> _discoveredServers = {};

  @override
  Future<AgentResult> executeTask(AgentTask task) {
    return runTaskLifecycle(task, () async {
      final context = await retrieveContext(
        '${task.description} mcp server discovery',
      );

      final desc = task.description.toLowerCase();

      if (desc.contains('discover') || desc.contains('scan')) {
        return _discoverServers(task);
      } else if (desc.contains('health') || desc.contains('validate')) {
        return _validateServers(task);
      } else if (desc.contains('register') || desc.contains('integrate')) {
        return _registerTools(task);
      }

      // Default: full discovery pipeline.
      return _fullDiscoveryPipeline(task);
    });
  }

  /// Runs the full discovery pipeline: discover → validate → register.
  Future<AgentResult> _fullDiscoveryPipeline(AgentTask task) async {
    final outputs = <String>[];

    // 1. Discover.
    final discoverResult = await _discoverServers(task);
    outputs.add('## Discovery\n${discoverResult.output}');

    // 2. Validate.
    final validateResult = await _validateServers(task);
    outputs.add('## Validation\n${validateResult.output}');

    // 3. Register.
    final registerResult = await _registerTools(task);
    outputs.add('## Registration\n${registerResult.output}');

    await saveToMemory(MemoryEntry(
      id: _uuid.v4(),
      content: 'MCP discovery: Found ${_discoveredServers.length} servers, '
          '${_discoveredServers.values.where((s) => s.isHealthy).length} healthy',
      source: id,
      timestamp: DateTime.now(),
      tags: ['mcp', 'discovery'],
    ));

    return AgentResult(
      taskId: task.id,
      success: true,
      output: outputs.join('\n\n'),
      metadata: {
        'servers':
            _discoveredServers.values.map((s) => s.toJson()).toList(),
      },
    );
  }

  /// Discovers MCP servers from known sources.
  Future<AgentResult> _discoverServers(AgentTask task) async {
    final discovered = <McpServerInfo>[];

    // 1. Check local config.
    final configResult = await useTool('read_file', {
      'path': 'mcp_config.json',
    });

    if (configResult.success) {
      publishEvent('mcp.config_found');
    }

    // 2. Scan for NPM MCP packages.
    final npmResult = await useTool('run_command', {
      'command': 'npm list -g --json 2>/dev/null || echo "{}"',
    });

    if (npmResult.success) {
      publishEvent('mcp.npm_scan_complete');
    }

    // 3. Scan for Python MCP packages.
    final pipResult = await useTool('run_command', {
      'command': 'pip list --format=json 2>/dev/null || echo "[]"',
    });

    if (pipResult.success) {
      publishEvent('mcp.pip_scan_complete');
    }

    // Register discovered servers.
    for (final server in discovered) {
      _discoveredServers[server.id] = server;
    }

    return AgentResult(
      taskId: task.id,
      success: true,
      output: 'Discovered ${discovered.length} MCP servers from '
          'config, NPM, and pip sources.',
      metadata: {
        'serverCount': discovered.length,
        'servers': discovered.map((s) => s.toJson()).toList(),
      },
    );
  }

  /// Validates health of all discovered servers.
  Future<AgentResult> _validateServers(AgentTask task) async {
    var healthy = 0;
    var unhealthy = 0;

    for (final entry in _discoveredServers.entries) {
      final isHealthy = await _checkServerHealth(entry.value);
      _discoveredServers[entry.key] = McpServerInfo(
        id: entry.value.id,
        name: entry.value.name,
        transport: entry.value.transport,
        endpoint: entry.value.endpoint,
        tools: entry.value.tools,
        protocolVersion: entry.value.protocolVersion,
        isHealthy: isHealthy,
        lastChecked: DateTime.now(),
        metadata: entry.value.metadata,
      );

      if (isHealthy) {
        healthy++;
      } else {
        unhealthy++;
      }
    }

    return AgentResult(
      taskId: task.id,
      success: true,
      output: 'Validation complete: $healthy healthy, $unhealthy unhealthy',
      metadata: {'healthy': healthy, 'unhealthy': unhealthy},
    );
  }

  /// Registers tools from healthy servers into the tool registry.
  Future<AgentResult> _registerTools(AgentTask task) async {
    var registered = 0;

    for (final server in _discoveredServers.values) {
      if (!server.isHealthy) continue;

      for (final tool in server.tools) {
        publishEvent('mcp.tool_registered', data: {
          'tool': tool,
          'server': server.id,
        });
        registered++;
      }
    }

    return AgentResult(
      taskId: task.id,
      success: true,
      output: 'Registered $registered tools from '
          '${_discoveredServers.values.where((s) => s.isHealthy).length} '
          'healthy servers.',
      metadata: {'registeredTools': registered},
    );
  }

  Future<bool> _checkServerHealth(McpServerInfo server) async {
    // Placeholder — in production this would attempt an MCP initialize
    // handshake with the server.
    try {
      final result = await useTool('run_command', {
        'command': 'echo "health check for ${server.name}"',
        'timeout': 5000,
      });
      return result.success;
    } catch (_) {
      return false;
    }
  }

  /// Returns all discovered servers.
  List<McpServerInfo> get discoveredServers =>
      List.unmodifiable(_discoveredServers.values);
}
