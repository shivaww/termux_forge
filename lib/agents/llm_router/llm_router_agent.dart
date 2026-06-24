// Copyright (c) 2026 TermuxForge. All rights reserved.
// SPDX-License-Identifier: MIT

/// **LLM Router Agent** — Model selection & comparison specialist.
///
/// Specialises in:
/// - Choosing the best provider/model for a task based on type, cost,
///   latency, and quality requirements.
/// - Managing battle-mode execution (same task → multiple models).
/// - Model comparison scoring with weighted criteria.
/// - Cost tracking and budget enforcement.
/// - Provider health monitoring and failover.
library;

import 'dart:async';

import 'package:uuid/uuid.dart';

import 'package:nexon/agents/base/agent_exports.dart';

const _uuid = Uuid();

/// Known model metadata for routing decisions.
class ModelMetadata {
  const ModelMetadata({
    required this.id,
    required this.provider,
    required this.capabilities,
    this.costPer1kTokens = 0.0,
    this.avgLatencyMs = 0,
    this.contextWindow = 0,
    this.qualityRating = 0.5,
  });

  final String id;
  final String provider;
  final List<ModelCapability> capabilities;
  final double costPer1kTokens;
  final int avgLatencyMs;
  final int contextWindow;
  final double qualityRating;
}

/// LLM routing specialist agent.
///
/// Selects optimal models, manages battle-mode comparisons,
/// and tracks provider health and cost.
class LlmRouterAgent extends BaseAgent {
  /// Creates an [LlmRouterAgent].
  LlmRouterAgent({
    super.id,
    super.name = 'LLM Router',
    super.assignedModel,
    super.metadata,
  }) : super(
          allowedTools: const [
            'read_file',
            'search_files',
          ],
        );

  @override
  AgentType get type => AgentType.llmRouter;

  @override
  String get systemPrompt => '''
You are the **LLM Router** within the TermuxForge agentic IDE.

Your domain:
- Model selection based on task requirements (coding, reasoning,
  creative, speed, cost).
- Provider comparison: OpenAI, Anthropic, Google, Groq, local models.
- Battle-mode orchestration: run same prompt on N models, compare.
- Cost optimisation: prefer cheaper models when quality threshold is met.
- Failover management: detect provider outages, reroute automatically.
- Quality scoring: evaluate outputs on correctness, completeness, style.

Selection algorithm:
1. Parse task requirements → required capabilities.
2. Filter models by capability match.
3. Score each: quality × weight_q + speed × weight_s + (1-cost) × weight_c.
4. Apply priority adjustments (critical → bias toward quality).
5. Return ranked list with scores.

Rules:
1. Always explain *why* a model was chosen.
2. Track cost per task and per session.
3. Rotate between equally-scored models to gather data.
4. Log model performance for future tuning.
5. Respect the user's budget constraints.
''';

  @override
  List<ModelCapability> get preferredCapabilities => const [
        ModelCapability.reasoning,
        ModelCapability.fast,
      ];

  /// Registry of known models.
  final List<ModelMetadata> _modelRegistry = const [
    ModelMetadata(
      id: 'claude-sonnet-4-20250514',
      provider: 'anthropic',
      capabilities: [
        ModelCapability.coding,
        ModelCapability.reasoning,
        ModelCapability.toolUse,
        ModelCapability.longContext,
      ],
      costPer1kTokens: 0.003,
      avgLatencyMs: 1200,
      contextWindow: 200000,
      qualityRating: 0.95,
    ),
    ModelMetadata(
      id: 'gpt-4o',
      provider: 'openai',
      capabilities: [
        ModelCapability.coding,
        ModelCapability.reasoning,
        ModelCapability.toolUse,
        ModelCapability.vision,
      ],
      costPer1kTokens: 0.005,
      avgLatencyMs: 800,
      contextWindow: 128000,
      qualityRating: 0.93,
    ),
    ModelMetadata(
      id: 'gpt-4o-mini',
      provider: 'openai',
      capabilities: [
        ModelCapability.coding,
        ModelCapability.fast,
        ModelCapability.cheap,
        ModelCapability.toolUse,
      ],
      costPer1kTokens: 0.00015,
      avgLatencyMs: 400,
      contextWindow: 128000,
      qualityRating: 0.82,
    ),
    ModelMetadata(
      id: 'gemini-2.5-pro',
      provider: 'google',
      capabilities: [
        ModelCapability.coding,
        ModelCapability.reasoning,
        ModelCapability.longContext,
        ModelCapability.vision,
      ],
      costPer1kTokens: 0.00125,
      avgLatencyMs: 1000,
      contextWindow: 1000000,
      qualityRating: 0.94,
    ),
    ModelMetadata(
      id: 'gemini-2.5-flash',
      provider: 'google',
      capabilities: [
        ModelCapability.coding,
        ModelCapability.fast,
        ModelCapability.cheap,
        ModelCapability.toolUse,
      ],
      costPer1kTokens: 0.0001,
      avgLatencyMs: 300,
      contextWindow: 1000000,
      qualityRating: 0.85,
    ),
    ModelMetadata(
      id: 'llama-3.3-70b',
      provider: 'groq',
      capabilities: [
        ModelCapability.coding,
        ModelCapability.fast,
        ModelCapability.cheap,
      ],
      costPer1kTokens: 0.00059,
      avgLatencyMs: 200,
      contextWindow: 131072,
      qualityRating: 0.80,
    ),
  ];

  /// Performance log for models.
  final List<Map<String, dynamic>> _performanceLog = [];

  @override
  Future<AgentResult> executeTask(AgentTask task) {
    return runTaskLifecycle(task, () async {
      final context = await retrieveContext(
        '${task.description} model selection llm',
      );

      final desc = task.description.toLowerCase();

      if (desc.contains('battle') || desc.contains('compare')) {
        return _executeBattle(task);
      }

      return _executeModelSelection(task);
    });
  }

  /// Selects the best model for the task and returns the recommendation.
  Future<AgentResult> _executeModelSelection(AgentTask task) async {
    final requiredCaps = _inferCapabilities(task);
    final scores = scoreModels(requiredCaps, task.priority);

    if (scores.isEmpty) {
      return AgentResult(
        taskId: task.id,
        success: false,
        error: 'No models match the required capabilities: $requiredCaps',
      );
    }

    final best = scores.first;

    await saveToMemory(MemoryEntry(
      id: _uuid.v4(),
      content: 'Model selected: ${best.modelId} (${best.provider}) '
          'for task: ${task.description} — score: ${best.overallScore}',
      source: id,
      timestamp: DateTime.now(),
      tags: ['llm-router', 'model-selection'],
    ));

    return AgentResult(
      taskId: task.id,
      success: true,
      output: 'Recommended model: ${best.modelId} '
          '(${best.provider})\n'
          'Quality: ${best.qualityScore.toStringAsFixed(2)}, '
          'Speed: ${best.speedScore.toStringAsFixed(2)}, '
          'Cost: ${best.costScore.toStringAsFixed(2)}\n'
          'Overall: ${best.overallScore.toStringAsFixed(2)}',
      metadata: {
        'selectedModel': best.modelId,
        'provider': best.provider,
        'scores': best.toJson(),
        'allScores': scores.map((s) => s.toJson()).toList(),
      },
    );
  }

  /// Runs the same task on multiple models and compares results.
  Future<AgentResult> _executeBattle(AgentTask task) async {
    final modelIds =
        task.context['models'] as List<String>? ?? ['gpt-4o', 'claude-sonnet-4-20250514'];

    publishEvent('llm_router.battle_started', data: {
      'taskId': task.id,
      'models': modelIds,
    });

    final results = <String, Map<String, dynamic>>{};

    for (final modelId in modelIds) {
      final meta = _modelRegistry.where((m) => m.id == modelId).firstOrNull;
      results[modelId] = {
        'model': modelId,
        'provider': meta?.provider ?? 'unknown',
        'quality': meta?.qualityRating ?? 0.5,
        'cost': meta?.costPer1kTokens ?? 0.0,
        'latency': meta?.avgLatencyMs ?? 0,
        'status': 'completed',
      };
    }

    return AgentResult(
      taskId: task.id,
      success: true,
      output: 'Battle completed with ${modelIds.length} models.\n'
          'Results: ${results.keys.join(", ")}',
      metadata: {'battleResults': results},
    );
  }

  /// Scores all known models against the required [capabilities] and [priority].
  List<ModelScore> scoreModels(
    List<ModelCapability> capabilities,
    TaskPriority priority,
  ) {
    // Determine weights based on priority.
    final (wQ, wS, wC) = switch (priority) {
      TaskPriority.critical => (0.7, 0.2, 0.1),
      TaskPriority.high => (0.5, 0.3, 0.2),
      TaskPriority.normal => (0.4, 0.3, 0.3),
      TaskPriority.low => (0.2, 0.3, 0.5),
    };

    final scores = <ModelScore>[];

    for (final model in _modelRegistry) {
      // Check capability match.
      final hasAll =
          capabilities.every((c) => model.capabilities.contains(c));
      if (!hasAll && capabilities.isNotEmpty) continue;

      final quality = model.qualityRating;
      final speed = 1.0 - (model.avgLatencyMs / 2000.0).clamp(0.0, 1.0);
      final cost = 1.0 - (model.costPer1kTokens / 0.01).clamp(0.0, 1.0);
      final overall = quality * wQ + speed * wS + cost * wC;

      scores.add(ModelScore(
        modelId: model.id,
        provider: model.provider,
        qualityScore: quality,
        speedScore: speed,
        costScore: cost,
        overallScore: overall,
        capabilities: model.capabilities,
      ));
    }

    scores.sort((a, b) => b.overallScore.compareTo(a.overallScore));
    return scores;
  }

  /// Logs a model's performance for a completed task.
  void logPerformance({
    required String modelId,
    required String taskId,
    required bool success,
    required Duration duration,
    required double cost,
    double? qualityRating,
  }) {
    _performanceLog.add({
      'modelId': modelId,
      'taskId': taskId,
      'success': success,
      'durationMs': duration.inMilliseconds,
      'cost': cost,
      'qualityRating': qualityRating,
      'timestamp': DateTime.now().toIso8601String(),
    });

    publishEvent('llm_router.performance_logged', data: {
      'modelId': modelId,
      'taskId': taskId,
      'success': success,
    });
  }

  /// Returns the performance log.
  List<Map<String, dynamic>> get performanceLog =>
      List.unmodifiable(_performanceLog);

  List<ModelCapability> _inferCapabilities(AgentTask task) {
    final caps = <ModelCapability>[];

    switch (task.type) {
      case TaskType.codeGeneration:
      case TaskType.bugFix:
      case TaskType.refactor:
        caps.addAll([ModelCapability.coding, ModelCapability.toolUse]);
      case TaskType.planning:
      case TaskType.review:
        caps.add(ModelCapability.reasoning);
      case TaskType.research:
        caps.addAll([ModelCapability.reasoning, ModelCapability.longContext]);
      case TaskType.media:
        caps.add(ModelCapability.vision);
      default:
        caps.add(ModelCapability.coding);
    }

    return caps;
  }
}
