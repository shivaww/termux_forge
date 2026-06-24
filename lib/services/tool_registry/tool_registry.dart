// ============================================================================
// TermuxForge — Tool Registry
// Unified abstraction layer for all 48+ tools available in the system.
// Handles registration, permission gating, invocation, and discovery.
// ============================================================================

import 'dart:async';

import 'package:nexon/services/tool_registry/tool_registry_types.dart';
import 'package:nexon/services/event_bus/event_bus.dart';
import 'package:nexon/services/event_bus/event_types.dart';

/// Central registry for all tools available in TermuxForge.
///
/// Every tool — whether built-in (file ops, git, shell), MCP-sourced, or
/// user-contributed — is registered here with a [ToolDefinition].
///
/// The registry enforces permission gating before any tool execution:
/// tools with a permission level above the caller's clearance are blocked.
///
/// ## Example
///
/// ```dart
/// final registry = ToolRegistry.instance;
///
/// final result = await registry.invokeTool(
///   'read_file',
///   {'path': '/home/project/lib/main.dart'},
///   callerPermissionLevel: 1,
/// );
/// print(result.data); // file contents
/// ```
class ToolRegistry {
  // ---------------------------------------------------------------------------
  // Singleton
  // ---------------------------------------------------------------------------

  ToolRegistry._internal() {
    _registerBuiltInTools();
  }

  /// The global [ToolRegistry] instance.
  static final ToolRegistry instance = ToolRegistry._internal();

  /// Factory constructor that returns the singleton [instance].
  factory ToolRegistry() => instance;

  // ---------------------------------------------------------------------------
  // Internal state
  // ---------------------------------------------------------------------------

  /// All registered tools keyed by ID.
  final Map<String, ToolDefinition> _tools = {};

  /// Reference to the event bus.
  final EventBus _eventBus = EventBus.instance;

  // ---------------------------------------------------------------------------
  // Registration
  // ---------------------------------------------------------------------------

  /// Registers a [tool] definition.
  ///
  /// If a tool with the same ID already exists, it is overwritten.
  void registerTool(ToolDefinition tool) {
    _tools[tool.id] = tool;
  }

  /// Unregisters the tool with the given [toolId].
  ///
  /// Returns `true` if the tool existed.
  bool unregisterTool(String toolId) => _tools.remove(toolId) != null;

  // ---------------------------------------------------------------------------
  // Invocation
  // ---------------------------------------------------------------------------

  /// Invokes the tool identified by [toolId] with the given [params].
  ///
  /// [callerPermissionLevel] is the maximum permission level the caller is
  /// cleared for. If the tool's level exceeds it, a failed [ToolResult] is
  /// returned without executing the handler.
  ///
  /// Publishes [ToolInvoked] and [ToolResultReceived] events.
  Future<ToolResult> invokeTool(
    String toolId,
    Map<String, dynamic> params, {
    int callerPermissionLevel = 0,
    String? invokingAgentId,
  }) async {
    final tool = _tools[toolId];
    if (tool == null) {
      return ToolResult.fail(
        toolId: toolId,
        error: 'Tool "$toolId" not found in registry',
      );
    }

    // Permission gate.
    if (!isToolAllowed(toolId, callerPermissionLevel)) {
      return ToolResult.fail(
        toolId: toolId,
        error: 'Permission denied: tool "$toolId" requires level '
            '${tool.permissionLevel}, caller has $callerPermissionLevel',
      );
    }

    _eventBus.publish(ToolInvoked(
      toolId: toolId,
      parameters: params,
      invokingAgentId: invokingAgentId,
      source: 'ToolRegistry',
    ));

    final stopwatch = Stopwatch()..start();
    try {
      final result = await tool.handler(params);
      stopwatch.stop();

      _eventBus.publish(ToolResultReceived(
        toolId: toolId,
        success: result.success,
        duration: stopwatch.elapsed,
        source: 'ToolRegistry',
      ));

      return ToolResult(
        success: result.success,
        data: result.data,
        error: result.error,
        duration: stopwatch.elapsed,
        toolId: toolId,
      );
    } catch (e, stackTrace) {
      stopwatch.stop();

      _eventBus.publish(ToolResultReceived(
        toolId: toolId,
        success: false,
        duration: stopwatch.elapsed,
        source: 'ToolRegistry',
      ));

      return ToolResult.fail(
        toolId: toolId,
        error: 'Tool execution error: $e\n$stackTrace',
        duration: stopwatch.elapsed,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Queries
  // ---------------------------------------------------------------------------

  /// Returns the [ToolDefinition] for [toolId], or `null`.
  ToolDefinition? getTool(String toolId) => _tools[toolId];

  /// Returns all registered tools.
  List<ToolDefinition> listTools() => List.unmodifiable(_tools.values.toList());

  /// Returns tools belonging to the given [category].
  List<ToolDefinition> getToolsByCategory(ToolCategory category) {
    return _tools.values.where((t) => t.category == category).toList();
  }

  /// Whether the tool [toolId] is allowed for a caller with the given
  /// [callerLevel].
  bool isToolAllowed(String toolId, int callerLevel) {
    final tool = _tools[toolId];
    if (tool == null) return false;
    return callerLevel >= tool.permissionLevel;
  }

  /// Returns the permission level of the tool [toolId], or `-1` if not found.
  int getToolPermissionLevel(String toolId) {
    return _tools[toolId]?.permissionLevel ?? -1;
  }

  /// Total number of registered tools.
  int get toolCount => _tools.length;

  /// Returns all tool definitions as JSON-serializable maps.
  ///
  /// Useful for exposing the tool schema to LLMs.
  List<Map<String, dynamic>> toJsonSchema() {
    return _tools.values.map((t) => t.toJson()).toList();
  }

  // ---------------------------------------------------------------------------
  // Built-in Tool Registration
  // ---------------------------------------------------------------------------

  /// Registers all 48 built-in tools with placeholder handlers.
  ///
  /// Each handler is a stub that returns a TODO result. The actual
  /// implementations are wired in by the respective service modules
  /// during app initialization.
  void _registerBuiltInTools() {
    // -- File tools (category: file) ----------------------------------------
    _reg('read_file', 'Read File', 'Read the contents of a file at the given path.',
        ToolCategory.file, 1, [
      const ToolParameter(name: 'path', description: 'Absolute file path'),
    ]);
    _reg('write_file', 'Write File', 'Write content to a file, creating it if needed.',
        ToolCategory.file, 2, [
      const ToolParameter(name: 'path', description: 'Absolute file path'),
      const ToolParameter(name: 'content', description: 'File content to write'),
    ]);
    _reg('edit_file', 'Edit File', 'Apply targeted edits to an existing file.',
        ToolCategory.file, 2, [
      const ToolParameter(name: 'path', description: 'Absolute file path'),
      const ToolParameter(name: 'edits', description: 'List of edit operations', type: 'List<Map>'),
    ]);
    _reg('search_files', 'Search Files', 'Search for files matching a pattern or containing text.',
        ToolCategory.file, 1, [
      const ToolParameter(name: 'query', description: 'Search query or glob pattern'),
      const ToolParameter(name: 'directory', description: 'Root directory to search', required: false),
    ]);
    _reg('list_files', 'List Files', 'List files and directories in a path.',
        ToolCategory.file, 0, [
      const ToolParameter(name: 'path', description: 'Directory path'),
      const ToolParameter(name: 'recursive', description: 'Include subdirectories', type: 'bool', required: false, defaultValue: 'false'),
    ]);

    // -- Git tools (category: git) ------------------------------------------
    _reg('git_status', 'Git Status', 'Show the working tree status.',
        ToolCategory.git, 0, []);
    _reg('git_diff', 'Git Diff', 'Show changes between commits, working tree, etc.',
        ToolCategory.git, 0, [
      const ToolParameter(name: 'ref', description: 'Git ref to diff against', required: false),
    ]);
    _reg('git_commit', 'Git Commit', 'Create a new commit with staged changes.',
        ToolCategory.git, 4, [
      const ToolParameter(name: 'message', description: 'Commit message'),
    ]);

    // -- Flutter tools (category: flutter) ----------------------------------
    _reg('flutter_run', 'Flutter Run', 'Run the Flutter application.',
        ToolCategory.flutter, 4, [
      const ToolParameter(name: 'device', description: 'Target device ID', required: false),
    ]);
    _reg('flutter_test', 'Flutter Test', 'Run Flutter tests.',
        ToolCategory.flutter, 4, [
      const ToolParameter(name: 'target', description: 'Test file or directory', required: false),
    ]);
    _reg('flutter_build', 'Flutter Build', 'Build the Flutter application.',
        ToolCategory.flutter, 4, [
      const ToolParameter(name: 'target', description: 'Build target: apk, aab, ios, web'),
    ]);

    // -- Dart tools (category: dart) ----------------------------------------
    _reg('dart_analyze', 'Dart Analyze', 'Run static analysis on Dart code.',
        ToolCategory.dart, 3, [
      const ToolParameter(name: 'path', description: 'Path to analyze', required: false),
    ]);
    _reg('dart_test', 'Dart Test', 'Run Dart unit tests.',
        ToolCategory.dart, 4, [
      const ToolParameter(name: 'path', description: 'Test path', required: false),
    ]);

    // -- Shell tools (category: shell) --------------------------------------
    _reg('execute_shell', 'Execute Shell', 'Execute an arbitrary shell command.',
        ToolCategory.shell, 5, [
      const ToolParameter(name: 'command', description: 'The shell command to execute'),
      const ToolParameter(name: 'cwd', description: 'Working directory', required: false),
      const ToolParameter(name: 'timeout', description: 'Timeout in seconds', type: 'int', required: false, defaultValue: '30'),
    ]);
    _reg('install_package', 'Install Package', 'Install a system package via pkg.',
        ToolCategory.shell, 5, [
      const ToolParameter(name: 'package', description: 'Package name to install'),
    ]);
    _reg('query_tool_status', 'Query Tool Status', 'Check if a CLI tool is installed and its version.',
        ToolCategory.shell, 0, [
      const ToolParameter(name: 'tool', description: 'Tool name to check'),
    ]);

    // -- Memory tools (category: memory) ------------------------------------
    _reg('fetch_memory', 'Fetch Memory', 'Retrieve a value from the project memory store.',
        ToolCategory.memory, 0, [
      const ToolParameter(name: 'key', description: 'Memory key'),
      const ToolParameter(name: 'namespace', description: 'Memory namespace', required: false, defaultValue: 'project'),
    ]);
    _reg('save_memory', 'Save Memory', 'Store a value in the project memory.',
        ToolCategory.memory, 1, [
      const ToolParameter(name: 'key', description: 'Memory key'),
      const ToolParameter(name: 'value', description: 'Value to store'),
      const ToolParameter(name: 'namespace', description: 'Memory namespace', required: false, defaultValue: 'project'),
    ]);
    _reg('semantic_search', 'Semantic Search', 'Search memory using semantic similarity.',
        ToolCategory.memory, 1, [
      const ToolParameter(name: 'query', description: 'Natural language search query'),
      const ToolParameter(name: 'limit', description: 'Max results', type: 'int', required: false, defaultValue: '10'),
    ]);

    // -- Agent tools (category: agent) --------------------------------------
    _reg('send_agent_message', 'Send Agent Message', 'Send a message to another agent.',
        ToolCategory.agent, 1, [
      const ToolParameter(name: 'toAgentId', description: 'Recipient agent ID'),
      const ToolParameter(name: 'content', description: 'Message content'),
    ]);
    _reg('update_todo', 'Update Todo', 'Update a todo/checklist item.',
        ToolCategory.agent, 1, [
      const ToolParameter(name: 'todoId', description: 'Todo item ID'),
      const ToolParameter(name: 'completed', description: 'Completion status', type: 'bool'),
    ]);
    _reg('get_todo_progress', 'Get Todo Progress', 'Get progress on the current todo list.',
        ToolCategory.agent, 0, []);

    // -- Model tools (category: model) --------------------------------------
    _reg('compare_models', 'Compare Models', 'Run a prompt against multiple models and compare.',
        ToolCategory.model, 1, [
      const ToolParameter(name: 'prompt', description: 'The prompt to send'),
      const ToolParameter(name: 'modelIds', description: 'Model IDs to compare', type: 'List<String>'),
    ]);
    _reg('list_available_models', 'List Models', 'List all available LLM models across providers.',
        ToolCategory.model, 0, []);
    _reg('select_model_for_mode', 'Select Model', 'Select the best model for a given task mode.',
        ToolCategory.model, 1, [
      const ToolParameter(name: 'mode', description: 'Task mode: code, reason, fast, cheap'),
    ]);

    // -- MCP tools (category: mcp) ------------------------------------------
    _reg('list_mcp_servers', 'List MCP Servers', 'List all registered MCP servers.',
        ToolCategory.mcp, 0, []);
    _reg('add_mcp_server', 'Add MCP Server', 'Register a new MCP server.',
        ToolCategory.mcp, 3, [
      const ToolParameter(name: 'name', description: 'Server display name'),
      const ToolParameter(name: 'uri', description: 'Server URI'),
      const ToolParameter(name: 'transport', description: 'Transport: stdio, sse, http'),
    ]);
    _reg('remove_mcp_server', 'Remove MCP Server', 'Unregister an MCP server.',
        ToolCategory.mcp, 3, [
      const ToolParameter(name: 'serverId', description: 'Server ID to remove'),
    ]);
    _reg('discover_mcp_tools', 'Discover MCP Tools', 'Discover tools offered by an MCP server.',
        ToolCategory.mcp, 1, [
      const ToolParameter(name: 'serverId', description: 'Server ID to query'),
    ]);
    _reg('invoke_mcp_tool', 'Invoke MCP Tool', 'Invoke a tool on an MCP server.',
        ToolCategory.mcp, 3, [
      const ToolParameter(name: 'serverId', description: 'Server ID'),
      const ToolParameter(name: 'toolName', description: 'Tool name'),
      const ToolParameter(name: 'params', description: 'Tool parameters', type: 'Map<String, dynamic>', required: false),
    ]);
    _reg('sync_mcp_tool_registry', 'Sync MCP Registry', 'Sync all MCP tools into the local registry.',
        ToolCategory.mcp, 2, []);
    _reg('search_web_via_mcp', 'Web Search (MCP)', 'Search the web via an MCP web-search server.',
        ToolCategory.mcp, 2, [
      const ToolParameter(name: 'query', description: 'Search query'),
    ]);
    _reg('research_query_via_mcp', 'Research (MCP)', 'Deep research via MCP research server.',
        ToolCategory.mcp, 2, [
      const ToolParameter(name: 'query', description: 'Research query'),
    ]);
    _reg('check_mcp_server_health', 'MCP Health', 'Check the health of an MCP server.',
        ToolCategory.mcp, 0, [
      const ToolParameter(name: 'serverId', description: 'Server ID'),
    ]);

    // -- Workflow tools (category: workflow) --------------------------------
    _reg('start_workflow', 'Start Workflow', 'Start a multi-step workflow.',
        ToolCategory.workflow, 3, [
      const ToolParameter(name: 'workflowName', description: 'Workflow name'),
      const ToolParameter(name: 'steps', description: 'Ordered workflow steps', type: 'List<Map>'),
    ]);
    _reg('stop_workflow', 'Stop Workflow', 'Stop a running workflow.',
        ToolCategory.workflow, 3, [
      const ToolParameter(name: 'workflowId', description: 'Workflow ID'),
    ]);
    _reg('inspect_workflow', 'Inspect Workflow', 'Get the status of a running workflow.',
        ToolCategory.workflow, 0, [
      const ToolParameter(name: 'workflowId', description: 'Workflow ID'),
    ]);

    // -- Checkpoint tools (category: checkpoint) ----------------------------
    _reg('create_checkpoint', 'Create Checkpoint', 'Create a project snapshot checkpoint.',
        ToolCategory.checkpoint, 2, [
      const ToolParameter(name: 'label', description: 'Human-readable checkpoint label'),
    ]);
    _reg('rollback_checkpoint', 'Rollback Checkpoint', 'Rollback to a previous checkpoint.',
        ToolCategory.checkpoint, 6, [
      const ToolParameter(name: 'checkpointId', description: 'Checkpoint ID to rollback to'),
    ]);

    // -- Cost tools (category: cost) ----------------------------------------
    _reg('get_cost_dashboard', 'Cost Dashboard', 'Get current token/cost usage data.',
        ToolCategory.cost, 0, []);

    // -- Background agent tools (category: background) ----------------------
    _reg('list_background_agents', 'List Background Agents', 'List all running background agents.',
        ToolCategory.background, 0, []);
    _reg('start_background_agent', 'Start Background Agent', 'Start a new background agent.',
        ToolCategory.background, 3, [
      const ToolParameter(name: 'agentType', description: 'Agent type to start'),
      const ToolParameter(name: 'config', description: 'Agent configuration', type: 'Map<String, dynamic>', required: false),
    ]);
    _reg('stop_background_agent', 'Stop Background Agent', 'Stop a running background agent.',
        ToolCategory.background, 3, [
      const ToolParameter(name: 'agentId', description: 'Agent ID to stop'),
    ]);

    // -- Media tools (category: media) --------------------------------------
    _reg('generate_image', 'Generate Image', 'Generate an image from a text prompt.',
        ToolCategory.media, 3, [
      const ToolParameter(name: 'prompt', description: 'Image generation prompt'),
      const ToolParameter(name: 'model', description: 'Model to use', required: false),
    ]);
    _reg('generate_video', 'Generate Video', 'Generate a video from a text prompt.',
        ToolCategory.media, 3, [
      const ToolParameter(name: 'prompt', description: 'Video generation prompt'),
      const ToolParameter(name: 'model', description: 'Model to use', required: false),
    ]);
    _reg('list_media_models', 'List Media Models', 'List available image/video generation models.',
        ToolCategory.media, 0, []);
    _reg('select_media_model', 'Select Media Model', 'Select a media generation model.',
        ToolCategory.media, 1, [
      const ToolParameter(name: 'modelId', description: 'Model ID'),
    ]);

    // -- Provider tools (category: provider) --------------------------------
    _reg('inspect_provider_models', 'Inspect Provider', 'Inspect models available from a provider.',
        ToolCategory.provider, 0, [
      const ToolParameter(name: 'providerId', description: 'Provider ID'),
    ]);
  }

  /// Internal helper to register a tool with a placeholder handler.
  void _reg(
    String id,
    String name,
    String description,
    ToolCategory category,
    int permissionLevel,
    List<ToolParameter> params,
  ) {
    registerTool(ToolDefinition(
      id: id,
      name: name,
      description: description,
      category: category,
      permissionLevel: permissionLevel,
      parameters: params,
      // TODO: Replace placeholder handlers with real implementations
      // during service initialization. Each domain service (FileService,
      // GitService, etc.) should call ToolRegistry.registerTool() with
      // a concrete handler.
      handler: (p) async => ToolResult.fail(
        toolId: id,
        error: 'Tool "$id" handler not yet implemented. '
            'Wire the concrete implementation during app init.',
      ),
    ));
  }
}
