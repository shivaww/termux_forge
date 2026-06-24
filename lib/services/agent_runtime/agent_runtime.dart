// ============================================================================
// TermuxForge — Agent Runtime
// Manages the full lifecycle of AI agents: registration, spawning, task
// assignment, messaging, monitoring, and teardown.
// ============================================================================

import 'dart:async';

import 'package:uuid/uuid.dart';

import 'package:nexon/services/agent_runtime/agent_runtime_types.dart';
import 'package:nexon/services/event_bus/event_bus.dart';
import 'package:nexon/services/event_bus/event_types.dart';

/// Manages the lifecycle and orchestration of all agents in the system.
///
/// The [AgentRuntime] is the central authority for:
/// * **Registering** agent definitions before they are spawned.
/// * **Spawning** live agent instances with a specific model and tool set.
/// * **Assigning tasks** to agents and tracking completion/failure.
/// * **Routing messages** between agents.
/// * **Monitoring** background agents and collecting execution traces.
///
/// ## Example
///
/// ```dart
/// final runtime = AgentRuntime.instance;
///
/// final agentId = runtime.spawnAgent(AgentSpawnConfig(
///   type: AgentType.coder,
///   name: 'CodeGen-1',
///   model: 'claude-sonnet-4-20250514',
///   toolAccess: {'read_file', 'write_file', 'edit_file'},
/// ));
///
/// runtime.assignTask(agentId, AgentTask(
///   id: 'task-1',
///   description: 'Implement login screen',
/// ));
/// ```
class AgentRuntime {
  // ---------------------------------------------------------------------------
  // Singleton
  // ---------------------------------------------------------------------------

  AgentRuntime._internal();

  /// The global [AgentRuntime] instance.
  static final AgentRuntime instance = AgentRuntime._internal();

  /// Factory constructor that returns the singleton [instance].
  factory AgentRuntime() => instance;

  // ---------------------------------------------------------------------------
  // Internal state
  // ---------------------------------------------------------------------------

  /// All registered agents keyed by ID.
  final Map<String, AgentRegistration> _agents = {};

  /// Reference to the event bus for publishing lifecycle events.
  final EventBus _eventBus = EventBus.instance;

  /// UUID generator.
  static const _uuid = Uuid();

  /// Background monitoring timer.
  Timer? _monitorTimer;

  // ---------------------------------------------------------------------------
  // Registration & Spawning
  // ---------------------------------------------------------------------------

  /// Spawns a new agent from the given [config] and returns its ID.
  ///
  /// The agent is immediately registered and set to [AgentStatus.idle].
  /// A [BackgroundAgentStarted] event is published if the agent type is
  /// [AgentType.background].
  String spawnAgent(AgentSpawnConfig config) {
    final id = 'agent_${_uuid.v4().substring(0, 8)}';

    final registration = AgentRegistration(
      id: id,
      type: config.type,
      name: config.name,
      model: config.model,
      toolAccess: Set<String>.from(config.toolAccess),
      parentAgentId: config.parentAgentId,
    );

    _agents[id] = registration;
    registration.trace('Spawned as ${config.type.name}');

    // Track parent → child relationship.
    if (config.parentAgentId != null) {
      _agents[config.parentAgentId]?.childAgentIds.add(id);
    }

    if (config.type == AgentType.background) {
      _eventBus.publish(BackgroundAgentStarted(
        agentId: id,
        agentName: config.name,
        agentType: config.type.name,
        source: 'AgentRuntime',
      ));
    }

    return id;
  }

  /// Registers an externally-created [AgentRegistration].
  ///
  /// Useful when restoring agents from persistent storage.
  void registerAgent(AgentRegistration registration) {
    _agents[registration.id] = registration;
    registration.trace('Registered externally');
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Kills the agent identified by [agentId].
  ///
  /// Sets the agent's status to [AgentStatus.terminated] and publishes a
  /// [BackgroundAgentStopped] event. Also recursively kills child agents.
  ///
  /// Returns `true` if the agent existed.
  bool killAgent(String agentId, {String reason = 'killed'}) {
    final agent = _agents[agentId];
    if (agent == null) return false;

    agent.status = AgentStatus.terminated;
    agent.trace('Killed — reason: $reason');

    // Recursively kill children.
    for (final childId in List<String>.from(agent.childAgentIds)) {
      killAgent(childId, reason: 'parent killed');
    }

    _eventBus.publish(BackgroundAgentStopped(
      agentId: agentId,
      reason: reason,
      source: 'AgentRuntime',
    ));

    return true;
  }

  /// Returns the [AgentRegistration] for the given [agentId], or `null`.
  AgentRegistration? getAgent(String agentId) => _agents[agentId];

  /// Returns all currently registered agents.
  List<AgentRegistration> listAgents({AgentStatus? status, AgentType? type}) {
    return _agents.values.where((a) {
      if (status != null && a.status != status) return false;
      if (type != null && a.type != type) return false;
      return true;
    }).toList();
  }

  /// Returns the current status of the agent, or `null` if not found.
  AgentStatus? getAgentStatus(String agentId) => _agents[agentId]?.status;

  // ---------------------------------------------------------------------------
  // Task Assignment
  // ---------------------------------------------------------------------------

  /// Assigns a [task] to the agent identified by [agentId].
  ///
  /// Throws [StateError] if the agent is not idle or does not exist.
  void assignTask(String agentId, AgentTask task) {
    final agent = _agents[agentId];
    if (agent == null) {
      throw StateError('Agent $agentId not found');
    }
    if (agent.status != AgentStatus.idle) {
      throw StateError(
        'Agent $agentId is ${agent.status.name}, cannot assign task',
      );
    }

    task.assignedAgentId = agentId;
    task.startedAt = DateTime.now().toUtc();
    agent.currentTask = task;
    agent.status = AgentStatus.working;
    agent.trace('Assigned task: ${task.id} — ${task.description}');

    _eventBus.publish(TaskAssigned(
      taskId: task.id,
      agentId: agentId,
      source: 'AgentRuntime',
    ));
  }

  /// Marks the current task of [agentId] as completed with an optional
  /// [result] payload.
  void completeTask(String agentId, {Map<String, dynamic>? result}) {
    final agent = _agents[agentId];
    if (agent == null || agent.currentTask == null) return;

    final task = agent.currentTask!;
    task.completedAt = DateTime.now().toUtc();
    task.result = result;
    agent.status = AgentStatus.idle;
    agent.trace('Completed task: ${task.id}');
    agent.currentTask = null;

    _eventBus.publish(TaskCompleted(
      taskId: task.id,
      result: result,
      source: 'AgentRuntime',
    ));
  }

  /// Marks the current task of [agentId] as failed.
  ///
  /// If the task is retryable, increments the retry counter and resets
  /// the agent to [AgentStatus.idle].
  void failTask(String agentId, String errorMessage) {
    final agent = _agents[agentId];
    if (agent == null || agent.currentTask == null) return;

    final task = agent.currentTask!;
    task.errorMessage = errorMessage;
    task.retryCount++;
    agent.trace('Failed task: ${task.id} — $errorMessage');

    if (task.canRetry) {
      agent.status = AgentStatus.idle;
      agent.trace('Task ${task.id} eligible for retry '
          '(${task.retryCount}/${task.maxRetries})');
    } else {
      agent.status = AgentStatus.error;
      agent.currentTask = null;
    }

    _eventBus.publish(TaskFailed(
      taskId: task.id,
      errorMessage: errorMessage,
      retryable: task.canRetry,
      source: 'AgentRuntime',
    ));
  }

  // ---------------------------------------------------------------------------
  // Messaging
  // ---------------------------------------------------------------------------

  /// Sends a [message] from one agent to another.
  ///
  /// The message is queued in the recipient's message queue.
  /// Returns `true` if the recipient exists.
  bool sendMessage({
    required String fromAgentId,
    required String toAgentId,
    required String content,
    Map<String, dynamic>? payload,
  }) {
    final recipient = _agents[toAgentId];
    if (recipient == null) return false;

    final message = AgentMessage(
      id: _uuid.v4(),
      fromAgentId: fromAgentId,
      toAgentId: toAgentId,
      content: content,
      payload: payload,
    );

    recipient.messageQueue.add(message);
    _agents[fromAgentId]?.trace('Sent message to $toAgentId');

    return true;
  }

  /// Returns all messages for the given [agentId].
  ///
  /// If [unreadOnly] is `true`, only returns messages that have not been
  /// marked as read.
  List<AgentMessage> getMessages(String agentId, {bool unreadOnly = false}) {
    final agent = _agents[agentId];
    if (agent == null) return [];

    if (unreadOnly) {
      return agent.messageQueue.where((m) => !m.read).toList();
    }
    return List.unmodifiable(agent.messageQueue);
  }

  /// Marks all messages for [agentId] as read.
  void markMessagesRead(String agentId) {
    final agent = _agents[agentId];
    if (agent == null) return;
    for (final msg in agent.messageQueue) {
      msg.read = true;
    }
  }

  // ---------------------------------------------------------------------------
  // Background Monitoring
  // ---------------------------------------------------------------------------

  /// Starts periodic monitoring of all agents.
  ///
  /// Every [interval] the runtime checks for stuck agents (working for more
  /// than [stuckThreshold]) and publishes appropriate events.
  void startMonitoring({
    Duration interval = const Duration(seconds: 30),
    Duration stuckThreshold = const Duration(minutes: 5),
  }) {
    _monitorTimer?.cancel();
    _monitorTimer = Timer.periodic(interval, (_) {
      _checkAgentHealth(stuckThreshold);
    });
  }

  /// Stops background monitoring.
  void stopMonitoring() {
    _monitorTimer?.cancel();
    _monitorTimer = null;
  }

  void _checkAgentHealth(Duration stuckThreshold) {
    final now = DateTime.now().toUtc();
    for (final agent in _agents.values) {
      if (agent.status == AgentStatus.working &&
          agent.currentTask?.startedAt != null) {
        final elapsed = now.difference(agent.currentTask!.startedAt!);
        if (elapsed > stuckThreshold) {
          agent.trace('WARNING: stuck for ${elapsed.inMinutes} minutes');
          // TODO: Integrate with notification service to alert user.
        }
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Execution Trace
  // ---------------------------------------------------------------------------

  /// Returns the execution trace for the given [agentId].
  List<String> getExecutionTrace(String agentId) {
    return _agents[agentId]?.executionTrace ?? [];
  }

  // ---------------------------------------------------------------------------
  // Cleanup
  // ---------------------------------------------------------------------------

  /// Removes all terminated agents from the registry.
  int pruneTerminated() {
    final terminated = _agents.entries
        .where((e) => e.value.status == AgentStatus.terminated)
        .map((e) => e.key)
        .toList();

    for (final id in terminated) {
      _agents.remove(id);
    }
    return terminated.length;
  }

  /// Kills all agents and clears internal state.
  void reset() {
    stopMonitoring();
    for (final id in List<String>.from(_agents.keys)) {
      killAgent(id, reason: 'runtime reset');
    }
    _agents.clear();
  }
}
