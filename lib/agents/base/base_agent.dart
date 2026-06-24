// Copyright (c) 2026 TermuxForge. All rights reserved.
// SPDX-License-Identifier: MIT

/// Abstract base class for every agent in the TermuxForge system.
///
/// Defines the lifecycle, task execution, tool access, memory, and
/// reporting contracts that all specialised agents must implement.
///
/// Subclasses should override [systemPrompt] and [preferredCapabilities]
/// to declare their specialisation, and implement [executeTask] with
/// domain-specific logic.
library;

import 'dart:async';

import 'package:logger/logger.dart';
import 'package:uuid/uuid.dart';

import 'package:nexon/agents/base/agent_types.dart';

/// Singleton UUID generator shared by all agents.
const _uuid = Uuid();

/// Abstract base class for all TermuxForge agents.
///
/// Every agent has:
/// - A unique [id] and human-readable [name].
/// - A [type] that classifies its specialisation.
/// - Lifecycle hooks: [initialize], [dispose].
/// - Task execution via [executeTask].
/// - Inter-agent communication via [handleMessage].
/// - Tool invocation via [useTool].
/// - Memory read/write via [retrieveContext] / [saveToMemory].
/// - Observability via [getStatusReport] / [reportProgress].
abstract class BaseAgent {
  // -----------------------------------------------------------------------
  // Constructor
  // -----------------------------------------------------------------------

  /// Creates a [BaseAgent] with sane defaults.
  ///
  /// [id] defaults to a v4 UUID if not provided.
  BaseAgent({
    String? id,
    required this.name,
    List<String>? allowedTools,
    this.assignedModel,
    Map<String, dynamic>? metadata,
  })  : id = id ?? _uuid.v4(),
        allowedTools = allowedTools ?? <String>[],
        messageQueue = <AgentMessage>[],
        _spawnedAt = DateTime.now(),
        costAccrued = 0.0,
        errorCount = 0,
        metadata = metadata ?? <String, dynamic>{};

  // -----------------------------------------------------------------------
  // Identity
  // -----------------------------------------------------------------------

  /// Unique identifier for this agent instance.
  final String id;

  /// Human-readable display name.
  final String name;

  /// The specialisation type. Subclasses must override.
  AgentType get type;

  /// The system prompt that defines this agent's role for the LLM.
  ///
  /// Subclasses must override with a domain-specific prompt.
  String get systemPrompt;

  /// Model capabilities this agent prefers when selecting models.
  List<ModelCapability> get preferredCapabilities;

  // -----------------------------------------------------------------------
  // State
  // -----------------------------------------------------------------------

  /// Current lifecycle status.
  AgentStatus status = AgentStatus.created;

  /// The ID of the task currently being executed (if any).
  String? currentTaskId;

  /// The model assigned to this agent for the current session.
  String? assignedModel;

  /// Tool IDs this agent is allowed to invoke.
  final List<String> allowedTools;

  /// Incoming message queue.
  final List<AgentMessage> messageQueue;

  /// When this agent was created.
  DateTime get spawnedAt => _spawnedAt;
  final DateTime _spawnedAt;

  /// Accumulated cost in USD across all tasks executed.
  double costAccrued;

  /// Number of errors encountered.
  int errorCount;

  /// Arbitrary metadata bag.
  final Map<String, dynamic> metadata;

  /// Logger instance scoped to this agent.
  late final Logger _logger = Logger(
    printer: PrettyPrinter(methodCount: 0),
    filter: ProductionFilter(),
  );

  /// Expose logger to subclasses.
  Logger get logger => _logger;

  // -----------------------------------------------------------------------
  // Lifecycle
  // -----------------------------------------------------------------------

  /// Initialises the agent (load config, warm caches, etc.).
  ///
  /// Must be called before [executeTask]. Sets [status] to [AgentStatus.idle].
  Future<void> initialize() async {
    logger.i('[$name] Initialising agent ($id)');
    status = AgentStatus.idle;
    _publishEvent('agent.initialised');
  }

  /// Releases resources held by this agent.
  ///
  /// Sets [status] to [AgentStatus.disposed]. After this call the agent
  /// must not be used again.
  Future<void> dispose() async {
    logger.i('[$name] Disposing agent ($id)');
    status = AgentStatus.disposed;
    _publishEvent('agent.disposed');
  }

  // -----------------------------------------------------------------------
  // Task execution (abstract)
  // -----------------------------------------------------------------------

  /// Executes the given [task] and returns an [AgentResult].
  ///
  /// Implementations should:
  /// 1. Set [status] to [AgentStatus.busy].
  /// 2. Retrieve relevant context via [retrieveContext].
  /// 3. Call the LLM with [systemPrompt] + task details.
  /// 4. Invoke tools as needed via [useTool].
  /// 5. Save important outcomes to memory.
  /// 6. Return a comprehensive [AgentResult].
  Future<AgentResult> executeTask(AgentTask task);

  // -----------------------------------------------------------------------
  // Messaging
  // -----------------------------------------------------------------------

  /// Handles an incoming [message] from another agent or the orchestrator.
  ///
  /// Default implementation enqueues the message; subclasses may override
  /// to process specific [MessageType]s eagerly.
  Future<void> handleMessage(AgentMessage message) async {
    logger.d('[$name] Received ${message.type.name} from ${message.senderId}');
    messageQueue.add(message);

    // Handle system control messages immediately.
    if (message.type == MessageType.systemControl) {
      await _handleSystemControl(message);
    }
  }

  /// Processes a system-control message (pause, resume, shutdown).
  Future<void> _handleSystemControl(AgentMessage message) async {
    final action = message.payload['action'] as String?;
    switch (action) {
      case 'pause':
        status = AgentStatus.waiting;
      case 'resume':
        status = AgentStatus.idle;
      case 'shutdown':
        await dispose();
      default:
        logger.w('[$name] Unknown system control action: $action');
    }
  }

  // -----------------------------------------------------------------------
  // Tool access
  // -----------------------------------------------------------------------

  /// Invokes the tool identified by [toolId] with the given [params].
  ///
  /// Returns a [ToolResult] indicating success or failure.
  ///
  /// If [toolId] is not in [allowedTools] the call is rejected.
  Future<ToolResult> useTool(
    String toolId,
    Map<String, dynamic> params,
  ) async {
    if (!allowedTools.contains(toolId)) {
      logger.w('[$name] Tool $toolId is not allowed');
      return ToolResult(
        toolId: toolId,
        success: false,
        error: 'Tool $toolId is not in the allowed list for agent $name',
      );
    }

    final stopwatch = Stopwatch()..start();
    try {
      // Delegate to the concrete tool-invocation implementation.
      final result = await invokeToolImpl(toolId, params);
      stopwatch.stop();

      _publishEvent('tool.invoked', data: {
        'toolId': toolId,
        'success': result.success,
        'durationMs': stopwatch.elapsedMilliseconds,
      });

      return result.success
          ? result
          : ToolResult(
              toolId: toolId,
              success: false,
              output: result.output,
              error: result.error,
              duration: stopwatch.elapsed,
            );
    } catch (e, st) {
      stopwatch.stop();
      errorCount++;
      logger.e('[$name] Tool $toolId threw', error: e, stackTrace: st);
      return ToolResult(
        toolId: toolId,
        success: false,
        error: e.toString(),
        duration: stopwatch.elapsed,
      );
    }
  }

  /// Low-level tool invocation that subclasses or the runtime can override.
  ///
  /// The default implementation returns a not-implemented error. The agent
  /// runtime will inject a real implementation at initialisation time via
  /// [setToolInvoker].
  Future<ToolResult> invokeToolImpl(
    String toolId,
    Map<String, dynamic> params,
  ) async {
    // This will be overridden by the runtime's tool registry injection.
    if (_toolInvoker != null) {
      return _toolInvoker!(toolId, params);
    }
    return ToolResult(
      toolId: toolId,
      success: false,
      error: 'No tool invoker configured for agent $name',
    );
  }

  /// Typedef for an injected tool invoker function.
  Future<ToolResult> Function(String toolId, Map<String, dynamic> params)?
      _toolInvoker;

  /// Injects a tool invoker function (called by the agent runtime).
  void setToolInvoker(
    Future<ToolResult> Function(String toolId, Map<String, dynamic> params)
        invoker,
  ) {
    _toolInvoker = invoker;
  }

  // -----------------------------------------------------------------------
  // Memory
  // -----------------------------------------------------------------------

  /// Retrieves context entries relevant to [query] from memory.
  ///
  /// Default implementation returns an empty list. Agents with memory
  /// integration should override this or have the runtime inject
  /// a [MemoryProvider].
  Future<List<MemoryEntry>> retrieveContext(String query) async {
    if (_memoryProvider != null) {
      return _memoryProvider!.retrieve(query, agentId: id);
    }
    return const [];
  }

  /// Saves a [MemoryEntry] for future retrieval.
  Future<void> saveToMemory(MemoryEntry entry) async {
    if (_memoryProvider != null) {
      await _memoryProvider!.save(entry);
    } else {
      logger.w('[$name] No memory provider — entry not persisted');
    }
  }

  /// Injected memory provider.
  MemoryProvider? _memoryProvider;

  /// Injects a [MemoryProvider] (called by the agent runtime).
  void setMemoryProvider(MemoryProvider provider) {
    _memoryProvider = provider;
  }

  // -----------------------------------------------------------------------
  // Event bus
  // -----------------------------------------------------------------------

  /// Injected event sink for publishing [AgentEvent]s.
  void Function(AgentEvent event)? _eventSink;

  /// Injects an event sink (called by the agent runtime).
  void setEventSink(void Function(AgentEvent event) sink) {
    _eventSink = sink;
  }

  /// Publishes an event to the event bus.
  void _publishEvent(String eventType, {Map<String, dynamic>? data}) {
    final event = AgentEvent(
      type: eventType,
      agentId: id,
      timestamp: DateTime.now(),
      taskId: currentTaskId,
      data: data ?? const {},
    );
    _eventSink?.call(event);
  }

  /// Exposes [_publishEvent] to subclasses.
  void publishEvent(String eventType, {Map<String, dynamic>? data}) =>
      _publishEvent(eventType, data: data);

  // -----------------------------------------------------------------------
  // Reporting
  // -----------------------------------------------------------------------

  /// Returns a snapshot of this agent's current state for dashboards.
  Map<String, dynamic> getStatusReport() {
    return {
      'id': id,
      'name': name,
      'type': type.name,
      'status': status.name,
      'currentTaskId': currentTaskId,
      'assignedModel': assignedModel,
      'messageQueueLength': messageQueue.length,
      'spawnedAt': spawnedAt.toIso8601String(),
      'costAccrued': costAccrued,
      'errorCount': errorCount,
      'uptimeSeconds': DateTime.now().difference(spawnedAt).inSeconds,
      'metadata': metadata,
    };
  }

  /// Reports incremental progress on the current task.
  ///
  /// [percentage] should be between 0.0 and 1.0.
  Future<void> reportProgress(double percentage, String note) async {
    logger.i(
      '[$name] Progress: ${(percentage * 100).toStringAsFixed(1)}% — $note',
    );
    _publishEvent('task.progress', data: {
      'percentage': percentage,
      'note': note,
    });
  }

  // -----------------------------------------------------------------------
  // Helper: wrap task execution with lifecycle bookkeeping
  // -----------------------------------------------------------------------

  /// Wraps a task execution body with standard lifecycle management.
  ///
  /// Sets status to [AgentStatus.busy], records timing and cost,
  /// catches errors, and resets status to [AgentStatus.idle].
  Future<AgentResult> runTaskLifecycle(
    AgentTask task,
    Future<AgentResult> Function() body,
  ) async {
    final stopwatch = Stopwatch()..start();
    currentTaskId = task.id;
    status = AgentStatus.busy;
    _publishEvent('task.started', data: task.toJson());

    try {
      final result = await body();
      stopwatch.stop();

      costAccrued += result.cost;
      status = AgentStatus.idle;
      currentTaskId = null;

      _publishEvent('task.completed', data: {
        'success': result.success,
        'durationMs': stopwatch.elapsedMilliseconds,
        'cost': result.cost,
      });

      return AgentResult(
        taskId: result.taskId,
        success: result.success,
        output: result.output,
        artifacts: result.artifacts,
        memoryEntries: result.memoryEntries,
        nextSteps: result.nextSteps,
        cost: result.cost,
        duration: stopwatch.elapsed,
        error: result.error,
        metadata: result.metadata,
      );
    } catch (e, st) {
      stopwatch.stop();
      errorCount++;
      status = AgentStatus.error;
      currentTaskId = null;

      logger.e('[$name] Task ${task.id} failed', error: e, stackTrace: st);
      _publishEvent('task.failed', data: {'error': e.toString()});

      return AgentResult(
        taskId: task.id,
        success: false,
        error: e.toString(),
        duration: stopwatch.elapsed,
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Memory provider contract
// ---------------------------------------------------------------------------

/// Abstract contract for the memory subsystem injected into agents.
///
/// The agent runtime provides a concrete implementation that bridges
/// to the vector-memory or Isar-backed knowledge base.
abstract class MemoryProvider {
  /// Retrieves memory entries relevant to [query].
  ///
  /// If [agentId] is provided, results are scoped to that agent's entries.
  Future<List<MemoryEntry>> retrieve(
    String query, {
    String? agentId,
    int limit = 10,
  });

  /// Persists a [MemoryEntry].
  Future<void> save(MemoryEntry entry);

  /// Deletes a memory entry by [id].
  Future<void> delete(String id);
}
