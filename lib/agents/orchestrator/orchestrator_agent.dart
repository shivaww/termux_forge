// Copyright (c) 2026 TermuxForge. All rights reserved.
// SPDX-License-Identifier: MIT

/// The **Orchestrator Agent** — the team lead of TermuxForge.
///
/// Responsible for:
/// - Analysing user requests and loading project memory.
/// - Decomposing complex tasks into subtasks with dependency graphs.
/// - Assigning subtasks to the best-suited specialist agent.
/// - Selecting the optimal model/provider per subtask.
/// - Tracking progress, dependencies, and cross-agent consistency.
/// - Merging partial results into a cohesive final output.
/// - Auto-updating to-do / progress lists.
/// - Spawning and killing agents dynamically.
/// - Supporting **autonomous** and **manual** execution modes.
library;

import 'dart:async';

import 'package:uuid/uuid.dart';

import 'package:nexon/agents/base/agent_exports.dart';

const _uuid = Uuid();

/// Execution mode for the orchestrator.
enum OrchestratorMode {
  /// Orchestrator picks agents, models, and flow automatically.
  autonomous,

  /// User confirms every major decision.
  manual,
}

/// Tracks the state of a decomposed subtask.
class SubtaskRecord {
  SubtaskRecord({
    required this.task,
    required this.assignedAgentId,
    this.status = AgentStatus.idle,
    this.result,
    this.dependsOn = const [],
  });

  /// The subtask itself.
  final AgentTask task;

  /// Which agent was assigned to execute it.
  final String assignedAgentId;

  /// Current execution status.
  AgentStatus status;

  /// The result once completed.
  AgentResult? result;

  /// IDs of subtasks this one depends on.
  final List<String> dependsOn;

  /// Whether all dependencies have been satisfied.
  bool dependenciesMet(Map<String, SubtaskRecord> registry) {
    return dependsOn.every((depId) {
      final dep = registry[depId];
      return dep != null &&
          dep.status == AgentStatus.idle &&
          dep.result != null &&
          dep.result!.success;
    });
  }
}

/// The orchestrator / team-lead agent.
///
/// This is the most important agent in the system. It receives
/// high-level user requests, breaks them down, delegates to
/// specialist agents, and assembles the final output.
class OrchestratorAgent extends BaseAgent {
  // ---------------------------------------------------------------------
  // Construction
  // ---------------------------------------------------------------------

  /// Creates an [OrchestratorAgent].
  OrchestratorAgent({
    super.id,
    super.name = 'Orchestrator',
    super.allowedTools,
    super.assignedModel,
    this.mode = OrchestratorMode.autonomous,
  });

  // ---------------------------------------------------------------------
  // Configuration
  // ---------------------------------------------------------------------

  @override
  AgentType get type => AgentType.orchestrator;

  @override
  String get systemPrompt => '''
You are the **Team Lead / Orchestrator** of TermuxForge, a mobile agentic IDE.

Your responsibilities:
1. **Understand** the user's request thoroughly before acting.
2. **Load context** — retrieve relevant project memory, file structures,
   and prior decisions.
3. **Plan** — decompose the request into well-scoped subtasks with clear
   acceptance criteria.
4. **Assign** — pick the best specialist agent for each subtask based on
   domain expertise.
5. **Select models** — choose the optimal LLM provider/model per subtask
   considering cost, quality, and latency.
6. **Coordinate** — manage dependencies between subtasks, resolve conflicts,
   and ensure cross-agent consistency.
7. **Merge** — combine partial results into a cohesive, production-quality
   output.
8. **Review** — validate the merged output before presenting it to the user.
9. **Update** — auto-update to-do lists and progress trackers.
10. **Adapt** — if a subtask fails, reassign, retry, or escalate.

Guidelines:
- Prefer smaller, well-scoped subtasks over monolithic ones.
- Always retrieve memory before planning.
- In autonomous mode, make decisions yourself. In manual mode, present
  options and wait for user confirmation.
- Track cost carefully and prefer cheaper models when quality allows.
- Publish events for every state change so the UI stays in sync.
''';

  @override
  List<ModelCapability> get preferredCapabilities => const [
        ModelCapability.reasoning,
        ModelCapability.longContext,
        ModelCapability.toolUse,
      ];

  /// Execution mode.
  OrchestratorMode mode;

  // ---------------------------------------------------------------------
  // Internal state
  // ---------------------------------------------------------------------

  /// Registry of all subtasks managed by this orchestrator.
  final Map<String, SubtaskRecord> _subtaskRegistry = {};

  /// Live agent pool — maps agent ID → reference (placeholder).
  final Map<String, BaseAgent> _agentPool = {};

  /// Accumulated results from subtasks.
  final List<AgentResult> _partialResults = [];

  // ---------------------------------------------------------------------
  // Task execution
  // ---------------------------------------------------------------------

  @override
  Future<AgentResult> executeTask(AgentTask task) {
    return runTaskLifecycle(task, () async {
      // 1. Load context
      final context = await retrieveContext(task.description);
      logger.i('[Orchestrator] Loaded ${context.length} memory entries');

      // 2. Plan & decompose
      final plan = await planTask(task, context);
      final subtasks = await decomposeTask(task, plan);

      // 3. Assign subtasks to agents
      for (final subtask in subtasks) {
        final agentId = await assignToAgent(subtask);
        final modelId = await selectModel(subtask);

        _subtaskRegistry[subtask.id] = SubtaskRecord(
          task: subtask.copyWith(model: modelId),
          assignedAgentId: agentId,
          dependsOn: _inferDependencies(subtask, subtasks),
        );
      }

      // 4. Execute subtasks respecting dependencies
      await _executeSubtasks();

      // 5. Merge results
      final mergedResult = await mergeResults(task.id, _partialResults);

      // 6. Review output
      final finalResult = await reviewOutput(mergedResult);

      // 7. Update progress
      await updateProgress(task.id, 1.0, 'Task completed');

      // 8. Save summary to memory
      await saveToMemory(MemoryEntry(
        id: _uuid.v4(),
        content:
            'Completed task: ${task.description}\nOutcome: ${finalResult.output}',
        source: id,
        timestamp: DateTime.now(),
        tags: ['orchestrator', 'task-summary', task.type.name],
      ));

      return finalResult;
    });
  }

  // ---------------------------------------------------------------------
  // Planning
  // ---------------------------------------------------------------------

  /// Generates a high-level plan for the given [task].
  ///
  /// Uses the LLM with relevant [context] to produce a structured plan.
  Future<Map<String, dynamic>> planTask(
    AgentTask task,
    List<MemoryEntry> context,
  ) async {
    logger.i('[Orchestrator] Planning task: ${task.description}');
    publishEvent('orchestrator.planning', data: {'taskId': task.id});

    // Build plan prompt
    final contextSummary = context.map((e) => '- ${e.content}').join('\n');

    // In a real implementation this would call the LLM.
    // For now we return a structured plan skeleton.
    return {
      'taskId': task.id,
      'description': task.description,
      'contextEntries': context.length,
      'contextSummary': contextSummary,
      'strategy': 'decompose-delegate-merge',
      'estimatedSubtasks': _estimateSubtaskCount(task),
      'suggestedAgents': _suggestAgentTypes(task),
    };
  }

  /// Decomposes [task] into a list of subtasks based on [plan].
  Future<List<AgentTask>> decomposeTask(
    AgentTask task,
    Map<String, dynamic> plan,
  ) async {
    logger.i('[Orchestrator] Decomposing task: ${task.id}');
    publishEvent('orchestrator.decomposing', data: {'taskId': task.id});

    // The real implementation would use the LLM to generate subtasks.
    // Here we create a sensible default decomposition based on task type.
    final subtasks = <AgentTask>[];
    final agentTypes =
        plan['suggestedAgents'] as List<AgentType>? ?? [AgentType.backendExpert];

    for (var i = 0; i < agentTypes.length; i++) {
      subtasks.add(AgentTask(
        id: _uuid.v4(),
        description: '${task.description} — subtask ${i + 1} '
            '(${agentTypes[i].name})',
        type: _agentTypeToTaskType(agentTypes[i]),
        priority: task.priority,
        context: {
          ...task.context,
          'parentPlan': plan,
          'subtaskIndex': i,
        },
        parentTaskId: task.id,
        deadline: task.deadline,
        tools: _toolsForAgentType(agentTypes[i]),
        createdAt: DateTime.now(),
      ));
    }

    return subtasks;
  }

  // ---------------------------------------------------------------------
  // Agent & model selection
  // ---------------------------------------------------------------------

  /// Selects the best agent from the pool for [subtask].
  ///
  /// Returns the agent ID. If no suitable agent exists, one is spawned.
  Future<String> assignToAgent(AgentTask subtask) async {
    final desiredType = _taskTypeToAgentType(subtask.type);

    // Look for an idle agent of the right type.
    final candidate = _agentPool.values.where(
      (a) => a.type == desiredType && a.status == AgentStatus.idle,
    );

    if (candidate.isNotEmpty) {
      final agent = candidate.first;
      logger.i(
        '[Orchestrator] Assigning ${subtask.id} to existing ${agent.name}',
      );
      return agent.id;
    }

    // Spawn a placeholder — the runtime will materialise the real agent.
    final agentId = _uuid.v4();
    logger.i(
      '[Orchestrator] Will spawn ${desiredType.name} agent ($agentId) '
      'for subtask ${subtask.id}',
    );

    publishEvent('orchestrator.spawn_requested', data: {
      'agentType': desiredType.name,
      'agentId': agentId,
      'subtaskId': subtask.id,
    });

    return agentId;
  }

  /// Selects the optimal model for [subtask] based on its type and priority.
  Future<String> selectModel(AgentTask subtask) async {
    // Prefer the explicitly assigned model.
    if (subtask.model != null) return subtask.model!;

    // Heuristic mapping — in production the LLM router agent refines this.
    switch (subtask.priority) {
      case TaskPriority.critical:
        return 'claude-sonnet-4-20250514';
      case TaskPriority.high:
        return 'gpt-4o';
      case TaskPriority.normal:
        return 'claude-sonnet-4-20250514';
      case TaskPriority.low:
        return 'gpt-4o-mini';
    }
  }

  // ---------------------------------------------------------------------
  // Subtask execution
  // ---------------------------------------------------------------------

  /// Executes all registered subtasks respecting their dependency graph.
  Future<void> _executeSubtasks() async {
    final pending = Set<String>.from(_subtaskRegistry.keys);

    while (pending.isNotEmpty) {
      // Find subtasks whose dependencies are met.
      final ready = pending.where((id) {
        final record = _subtaskRegistry[id]!;
        return record.dependenciesMet(_subtaskRegistry);
      }).toList();

      if (ready.isEmpty && pending.isNotEmpty) {
        logger.e('[Orchestrator] Deadlock detected — breaking cycle');
        // Break deadlock by force-starting the first pending task.
        ready.add(pending.first);
      }

      // Execute ready subtasks concurrently.
      final futures = ready.map((id) => _executeSingleSubtask(id));
      await Future.wait(futures);

      pending.removeAll(ready);
    }
  }

  /// Executes a single subtask by delegating to the assigned agent.
  Future<void> _executeSingleSubtask(String subtaskId) async {
    final record = _subtaskRegistry[subtaskId]!;
    record.status = AgentStatus.busy;

    publishEvent('orchestrator.subtask_started', data: {
      'subtaskId': subtaskId,
      'agentId': record.assignedAgentId,
    });

    try {
      final agent = _agentPool[record.assignedAgentId];

      if (agent != null) {
        final result = await agent.executeTask(record.task);
        record.result = result;
        record.status = AgentStatus.idle;
        _partialResults.add(result);
      } else {
        // Agent not yet in pool — record a placeholder result.
        // The runtime will handle late-binding.
        logger.w(
          '[Orchestrator] Agent ${record.assignedAgentId} not in pool '
          '— recording pending result',
        );
        record.result = AgentResult(
          taskId: record.task.id,
          success: true,
          output: 'Delegated to agent ${record.assignedAgentId} (pending)',
        );
        record.status = AgentStatus.idle;
        _partialResults.add(record.result!);
      }
    } catch (e, st) {
      logger.e(
        '[Orchestrator] Subtask $subtaskId failed',
        error: e,
        stackTrace: st,
      );
      record.status = AgentStatus.error;
      record.result = AgentResult(
        taskId: record.task.id,
        success: false,
        error: e.toString(),
      );
      _partialResults.add(record.result!);
    }
  }

  // ---------------------------------------------------------------------
  // Result merging & review
  // ---------------------------------------------------------------------

  /// Merges partial results from subtasks into one cohesive [AgentResult].
  Future<AgentResult> mergeResults(
    String parentTaskId,
    List<AgentResult> results,
  ) async {
    logger.i('[Orchestrator] Merging ${results.length} subtask results');
    publishEvent('orchestrator.merging', data: {
      'parentTaskId': parentTaskId,
      'resultCount': results.length,
    });

    final allArtifacts = results.expand((r) => r.artifacts).toList();
    final allMemory = results.expand((r) => r.memoryEntries).toList();
    final allNextSteps = results.expand((r) => r.nextSteps).toList();
    final totalCost = results.fold<double>(0, (sum, r) => sum + r.cost);
    final allSucceeded = results.every((r) => r.success);
    final outputBuffer = StringBuffer();

    for (final result in results) {
      if (result.output.isNotEmpty) {
        outputBuffer.writeln('--- Subtask ${result.taskId} ---');
        outputBuffer.writeln(result.output);
        outputBuffer.writeln();
      }
    }

    final failures =
        results.where((r) => !r.success).map((r) => r.error).toList();

    return AgentResult(
      taskId: parentTaskId,
      success: allSucceeded,
      output: outputBuffer.toString(),
      artifacts: allArtifacts,
      memoryEntries: allMemory,
      nextSteps: allNextSteps,
      cost: totalCost,
      error: failures.isEmpty ? null : failures.join('; '),
    );
  }

  /// Reviews the merged output for quality, consistency, and completeness.
  ///
  /// In a real implementation this would call the LLM for a final review pass.
  Future<AgentResult> reviewOutput(AgentResult merged) async {
    logger.i('[Orchestrator] Reviewing merged output');
    publishEvent('orchestrator.reviewing', data: {
      'taskId': merged.taskId,
      'success': merged.success,
    });

    // Placeholder: in production, send the merged output to the LLM
    // for a quality-assurance pass and return a refined result.
    return merged;
  }

  // ---------------------------------------------------------------------
  // Progress tracking
  // ---------------------------------------------------------------------

  /// Updates the progress of a task and publishes an event.
  Future<void> updateProgress(
    String taskId,
    double percentage,
    String note,
  ) async {
    await reportProgress(percentage, note);
    publishEvent('orchestrator.progress', data: {
      'taskId': taskId,
      'percentage': percentage,
      'note': note,
    });
  }

  // ---------------------------------------------------------------------
  // Battle mode support
  // ---------------------------------------------------------------------

  /// Runs a "battle" — sends the same task to multiple models and compares.
  ///
  /// Returns a map of model IDs to their [AgentResult]s plus a
  /// synthesised comparison.
  Future<Map<String, dynamic>> synthesizeBattleResults(
    AgentTask task,
    List<String> modelIds,
  ) async {
    logger.i('[Orchestrator] Starting battle with ${modelIds.length} models');
    publishEvent('orchestrator.battle_started', data: {
      'taskId': task.id,
      'models': modelIds,
    });

    final results = <String, AgentResult>{};

    // Execute the same task with each model (sequentially to limit cost).
    for (final modelId in modelIds) {
      final modelTask = task.copyWith(model: modelId);

      // Delegate to self with the forced model.
      final result = await executeTask(modelTask);
      results[modelId] = result;
    }

    // Synthesise comparison.
    final comparison = <String, dynamic>{
      'taskId': task.id,
      'models': modelIds,
      'results': results.map((k, v) => MapEntry(k, v.toJson())),
      'winner': _pickBattleWinner(results),
    };

    publishEvent('orchestrator.battle_completed', data: comparison);
    return comparison;
  }

  /// Picks the best result from a battle based on success and cost.
  String _pickBattleWinner(Map<String, AgentResult> results) {
    // Simple heuristic: prefer success, then cheapest.
    final successful =
        results.entries.where((e) => e.value.success).toList();

    if (successful.isEmpty) return results.keys.first;

    successful.sort((a, b) => a.value.cost.compareTo(b.value.cost));
    return successful.first.key;
  }

  // ---------------------------------------------------------------------
  // Agent pool management
  // ---------------------------------------------------------------------

  /// Registers an agent in the pool.
  void registerAgent(BaseAgent agent) {
    _agentPool[agent.id] = agent;
    publishEvent('orchestrator.agent_registered', data: {
      'agentId': agent.id,
      'agentType': agent.type.name,
    });
  }

  /// Removes and disposes an agent from the pool.
  Future<void> killAgent(String agentId) async {
    final agent = _agentPool.remove(agentId);
    if (agent != null) {
      await agent.dispose();
      publishEvent('orchestrator.agent_killed', data: {
        'agentId': agentId,
        'agentType': agent.type.name,
      });
    }
  }

  /// Returns agents currently in the pool.
  List<BaseAgent> get agents => List.unmodifiable(_agentPool.values);

  // ---------------------------------------------------------------------
  // Heuristic helpers
  // ---------------------------------------------------------------------

  int _estimateSubtaskCount(AgentTask task) {
    switch (task.type) {
      case TaskType.codeGeneration:
        return 3; // plan + implement + test
      case TaskType.bugFix:
        return 2; // diagnose + fix
      case TaskType.refactor:
        return 3; // analyse + refactor + review
      case TaskType.testing:
        return 2; // strategy + implement
      case TaskType.research:
        return 1;
      case TaskType.review:
        return 1;
      case TaskType.planning:
        return 1;
      default:
        return 2;
    }
  }

  List<AgentType> _suggestAgentTypes(AgentTask task) {
    switch (task.type) {
      case TaskType.codeGeneration:
        return [AgentType.planner, AgentType.backendExpert, AgentType.tester];
      case TaskType.bugFix:
        return [AgentType.debugger, AgentType.backendExpert];
      case TaskType.refactor:
        return [
          AgentType.reviewer,
          AgentType.backendExpert,
          AgentType.tester,
        ];
      case TaskType.testing:
        return [AgentType.tester];
      case TaskType.research:
        return [AgentType.researcher];
      case TaskType.review:
        return [AgentType.reviewer];
      case TaskType.planning:
        return [AgentType.planner];
      case TaskType.database:
        return [AgentType.databaseExpert];
      case TaskType.ui:
        return [AgentType.frontendExpert, AgentType.tester];
      case TaskType.debugging:
        return [AgentType.debugger];
      case TaskType.media:
        return [AgentType.mediaAgent];
      case TaskType.workflow:
        return [AgentType.workflowAgent];
      case TaskType.observability:
        return [AgentType.observability];
      case TaskType.devops:
        return [AgentType.backendExpert];
      case TaskType.general:
        return [AgentType.backendExpert];
    }
  }

  AgentType _taskTypeToAgentType(TaskType type) {
    switch (type) {
      case TaskType.codeGeneration:
      case TaskType.refactor:
      case TaskType.devops:
      case TaskType.general:
        return AgentType.backendExpert;
      case TaskType.bugFix:
      case TaskType.debugging:
        return AgentType.debugger;
      case TaskType.testing:
        return AgentType.tester;
      case TaskType.research:
        return AgentType.researcher;
      case TaskType.review:
        return AgentType.reviewer;
      case TaskType.planning:
        return AgentType.planner;
      case TaskType.database:
        return AgentType.databaseExpert;
      case TaskType.ui:
        return AgentType.frontendExpert;
      case TaskType.media:
        return AgentType.mediaAgent;
      case TaskType.workflow:
        return AgentType.workflowAgent;
      case TaskType.observability:
        return AgentType.observability;
    }
  }

  TaskType _agentTypeToTaskType(AgentType agentType) {
    switch (agentType) {
      case AgentType.orchestrator:
        return TaskType.general;
      case AgentType.frontendExpert:
        return TaskType.ui;
      case AgentType.backendExpert:
        return TaskType.codeGeneration;
      case AgentType.databaseExpert:
        return TaskType.database;
      case AgentType.researcher:
        return TaskType.research;
      case AgentType.tester:
        return TaskType.testing;
      case AgentType.debugger:
        return TaskType.debugging;
      case AgentType.reviewer:
        return TaskType.review;
      case AgentType.planner:
        return TaskType.planning;
      case AgentType.llmRouter:
        return TaskType.general;
      case AgentType.mcpDiscovery:
        return TaskType.general;
      case AgentType.workflowAgent:
        return TaskType.workflow;
      case AgentType.mediaAgent:
        return TaskType.media;
      case AgentType.observability:
        return TaskType.observability;
    }
  }

  List<String> _toolsForAgentType(AgentType agentType) {
    switch (agentType) {
      case AgentType.frontendExpert:
        return [
          'flutter_run',
          'flutter_build',
          'read_file',
          'write_file',
          'edit_file',
        ];
      case AgentType.backendExpert:
        return [
          'read_file',
          'write_file',
          'edit_file',
          'run_command',
          'search_files',
        ];
      case AgentType.databaseExpert:
        return ['read_file', 'write_file', 'edit_file', 'run_command'];
      case AgentType.researcher:
        return [
          'search_web_via_mcp',
          'research_query_via_mcp',
          'read_file',
        ];
      case AgentType.tester:
        return [
          'flutter_test',
          'read_file',
          'write_file',
          'edit_file',
          'run_command',
        ];
      case AgentType.debugger:
        return [
          'read_file',
          'edit_file',
          'run_command',
          'flutter_analyze',
          'search_files',
        ];
      case AgentType.reviewer:
        return ['read_file', 'search_files', 'flutter_analyze'];
      case AgentType.planner:
        return ['read_file', 'search_files'];
      default:
        return ['read_file'];
    }
  }

  List<String> _inferDependencies(
    AgentTask subtask,
    List<AgentTask> allSubtasks,
  ) {
    // Simple heuristic: research/planning subtasks come first.
    final deps = <String>[];
    final index = allSubtasks.indexOf(subtask);

    if (index > 0) {
      final previous = allSubtasks[index - 1];
      if (previous.type == TaskType.planning ||
          previous.type == TaskType.research) {
        deps.add(previous.id);
      }
    }

    return deps;
  }
}
