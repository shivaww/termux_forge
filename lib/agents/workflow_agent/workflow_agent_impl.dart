// Copyright (c) 2026 TermuxForge. All rights reserved.
// SPDX-License-Identifier: MIT

/// **Workflow Agent** — Workflow execution specialist.
///
/// Specialises in:
/// - Executing multi-step workflow graphs (DAGs).
/// - Scheduling recurring jobs and cron-like automations.
/// - Pipeline orchestration with conditional branching.
/// - Retry logic with exponential backoff.
/// - Workflow state persistence and resumption.
library;

import 'dart:async';

import 'package:uuid/uuid.dart';

import 'package:nexon/agents/base/agent_exports.dart';

const _uuid = Uuid();

/// A node in a workflow graph.
class WorkflowNode {
  WorkflowNode({
    required this.id,
    required this.name,
    required this.action,
    this.dependsOn = const [],
    this.condition,
    this.retryCount = 0,
    this.maxRetries = 3,
    this.timeoutMs = 60000,
    this.metadata = const {},
  });

  final String id;
  final String name;
  final String action;
  final List<String> dependsOn;
  final String? condition;
  int retryCount;
  final int maxRetries;
  final int timeoutMs;
  final Map<String, dynamic> metadata;

  /// Status of this node.
  String status = 'pending';

  /// Output from execution.
  String? output;
}

/// A complete workflow definition.
class WorkflowDefinition {
  const WorkflowDefinition({
    required this.id,
    required this.name,
    required this.nodes,
    this.description = '',
    this.schedule,
    this.metadata = const {},
  });

  final String id;
  final String name;
  final String description;
  final List<WorkflowNode> nodes;

  /// Optional cron expression for recurring workflows.
  final String? schedule;
  final Map<String, dynamic> metadata;
}

/// Workflow execution specialist agent.
///
/// Executes workflow graphs, handles scheduling, manages retries,
/// and persists workflow state for resumption.
class WorkflowAgentImpl extends BaseAgent {
  /// Creates a [WorkflowAgentImpl].
  WorkflowAgentImpl({
    super.id,
    super.name = 'Workflow Agent',
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
  AgentType get type => AgentType.workflowAgent;

  @override
  String get systemPrompt => '''
You are the **Workflow Execution Specialist** within TermuxForge.

Your domain:
- DAG-based workflow execution with dependency resolution.
- Job scheduling: cron expressions, one-shot timers, event triggers.
- Pipeline orchestration: sequential, parallel, conditional branching.
- Retry logic: exponential backoff, max retries, dead-letter handling.
- State persistence: checkpoint, resume, rollback.
- Automation recipes: build pipelines, deploy flows, data processing.

Rules:
1. Always validate the DAG for cycles before execution.
2. Execute nodes in topological order, respecting dependencies.
3. Run independent nodes in parallel when possible.
4. Implement idempotent operations for safe retries.
5. Persist checkpoint state after every node completion.
6. Log all state transitions for auditability.
7. Respect timeouts — kill stuck nodes gracefully.
8. Report progress after each node completes.
''';

  @override
  List<ModelCapability> get preferredCapabilities => const [
        ModelCapability.reasoning,
        ModelCapability.toolUse,
      ];

  /// Active workflows.
  final Map<String, WorkflowDefinition> _activeWorkflows = {};

  @override
  Future<AgentResult> executeTask(AgentTask task) {
    return runTaskLifecycle(task, () async {
      final context = await retrieveContext(
        '${task.description} workflow pipeline automation',
      );

      final desc = task.description.toLowerCase();

      if (desc.contains('schedule') || desc.contains('cron')) {
        return _scheduleWorkflow(task);
      }

      return _executeWorkflow(task);
    });
  }

  /// Executes a workflow graph.
  Future<AgentResult> _executeWorkflow(AgentTask task) async {
    final workflowId = task.context['workflowId'] as String? ?? _uuid.v4();
    final nodes = _buildNodesFromTask(task);

    final workflow = WorkflowDefinition(
      id: workflowId,
      name: task.description,
      nodes: nodes,
    );

    _activeWorkflows[workflowId] = workflow;
    publishEvent('workflow.started', data: {'workflowId': workflowId});

    // Validate DAG.
    if (_hasCycle(nodes)) {
      return AgentResult(
        taskId: task.id,
        success: false,
        error: 'Workflow DAG contains a cycle',
      );
    }

    // Execute in topological order.
    final pending = Set<String>.from(nodes.map((n) => n.id));
    final outputs = <String>[];

    while (pending.isNotEmpty) {
      final ready = nodes.where((n) {
        return pending.contains(n.id) &&
            n.dependsOn.every((dep) => !pending.contains(dep));
      }).toList();

      if (ready.isEmpty && pending.isNotEmpty) {
        break; // deadlock
      }

      final futures = ready.map((n) => _executeNode(n, task));
      final results = await Future.wait(futures);

      for (var i = 0; i < ready.length; i++) {
        ready[i].status = results[i].success ? 'completed' : 'failed';
        ready[i].output = results[i].output;
        outputs.add('${ready[i].name}: ${results[i].output}');
        pending.remove(ready[i].id);

        await reportProgress(
          1.0 - (pending.length / nodes.length),
          'Completed: ${ready[i].name}',
        );
      }
    }

    _activeWorkflows.remove(workflowId);
    publishEvent('workflow.completed', data: {'workflowId': workflowId});

    await saveToMemory(MemoryEntry(
      id: _uuid.v4(),
      content: 'Workflow completed: ${task.description}\n'
          'Nodes: ${nodes.length}, '
          'Completed: ${nodes.where((n) => n.status == "completed").length}',
      source: id,
      timestamp: DateTime.now(),
      tags: ['workflow', 'automation'],
    ));

    return AgentResult(
      taskId: task.id,
      success: nodes.every((n) => n.status == 'completed'),
      output: outputs.join('\n'),
      metadata: {'workflowId': workflowId},
    );
  }

  /// Schedules a recurring workflow.
  Future<AgentResult> _scheduleWorkflow(AgentTask task) async {
    final schedule = task.context['schedule'] as String? ?? '0 * * * *';

    publishEvent('workflow.scheduled', data: {
      'taskId': task.id,
      'schedule': schedule,
    });

    return AgentResult(
      taskId: task.id,
      success: true,
      output: 'Workflow scheduled with cron: $schedule',
      metadata: {'schedule': schedule},
    );
  }

  Future<AgentResult> _executeNode(WorkflowNode node, AgentTask task) async {
    publishEvent('workflow.node_started', data: {'nodeId': node.id});

    try {
      final result = await useTool('run_command', {
        'command': node.action,
        'timeout': node.timeoutMs,
      });

      return AgentResult(
        taskId: task.id,
        success: result.success,
        output: result.output,
      );
    } catch (e) {
      if (node.retryCount < node.maxRetries) {
        node.retryCount++;
        // Exponential backoff.
        await Future<void>.delayed(
          Duration(milliseconds: 1000 * (1 << node.retryCount)),
        );
        return _executeNode(node, task);
      }

      return AgentResult(
        taskId: task.id,
        success: false,
        error: 'Node ${node.name} failed after ${node.maxRetries} retries: $e',
      );
    }
  }

  List<WorkflowNode> _buildNodesFromTask(AgentTask task) {
    final nodeData = task.context['nodes'] as List<dynamic>?;
    if (nodeData != null) {
      return nodeData.map((n) {
        final map = n as Map<String, dynamic>;
        return WorkflowNode(
          id: map['id'] as String? ?? _uuid.v4(),
          name: map['name'] as String? ?? 'unnamed',
          action: map['action'] as String? ?? 'echo "no-op"',
          dependsOn:
              (map['dependsOn'] as List<dynamic>?)?.cast<String>() ?? [],
        );
      }).toList();
    }

    // Default single-node workflow.
    return [
      WorkflowNode(
        id: _uuid.v4(),
        name: 'main',
        action: 'echo "Executing: ${task.description}"',
      ),
    ];
  }

  bool _hasCycle(List<WorkflowNode> nodes) {
    final visited = <String>{};
    final stack = <String>{};

    bool dfs(String nodeId) {
      visited.add(nodeId);
      stack.add(nodeId);

      final node = nodes.where((n) => n.id == nodeId).firstOrNull;
      if (node == null) return false;

      for (final dep in node.dependsOn) {
        if (!visited.contains(dep)) {
          if (dfs(dep)) return true;
        } else if (stack.contains(dep)) {
          return true;
        }
      }

      stack.remove(nodeId);
      return false;
    }

    for (final node in nodes) {
      if (!visited.contains(node.id)) {
        if (dfs(node.id)) return true;
      }
    }

    return false;
  }

  /// Returns active workflows.
  Map<String, WorkflowDefinition> get activeWorkflows =>
      Map.unmodifiable(_activeWorkflows);
}
