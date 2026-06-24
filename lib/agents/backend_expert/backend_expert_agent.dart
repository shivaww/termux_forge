// Copyright (c) 2026 TermuxForge. All rights reserved.
// SPDX-License-Identifier: MIT

/// **Backend Expert Agent** — Architecture & logic specialist.
///
/// Specialises in:
/// - Clean architecture: data / domain / presentation layers.
/// - State management with Riverpod 3.x.
/// - API integration, service layers, repository patterns.
/// - Dependency injection and inversion of control.
/// - Error handling, logging, and resilience patterns.
/// - Performance optimisation and code organisation.
library;

import 'dart:async';

import 'package:uuid/uuid.dart';

import 'package:nexon/agents/base/agent_exports.dart';

const _uuid = Uuid();

/// Architecture & backend-logic specialist agent.
///
/// Handles all non-UI Dart code: services, repositories, state management,
/// API clients, data models, use cases, and architectural decisions.
class BackendExpertAgent extends BaseAgent {
  /// Creates a [BackendExpertAgent].
  BackendExpertAgent({
    super.id,
    super.name = 'Backend Expert',
    super.assignedModel,
    super.metadata,
  }) : super(
          allowedTools: const [
            'read_file',
            'write_file',
            'edit_file',
            'run_command',
            'search_files',
            'flutter_analyze',
          ],
        );

  @override
  AgentType get type => AgentType.backendExpert;

  @override
  String get systemPrompt => '''
You are a **Backend / Architecture Expert** within the TermuxForge agentic IDE.

Your domain:
- Clean Architecture: entities, use cases, repositories, data sources.
- Riverpod 3.x state management: providers, notifiers, code generation.
- RESTful and GraphQL API integration via Dio.
- Repository pattern with abstract interfaces and concrete implementations.
- Error handling: Result types, custom exceptions, graceful degradation.
- Dependency injection via Riverpod's provider system.
- Dart best practices: immutability, null safety, strong typing.

Rules:
1. Always use clean architecture layers: domain → data → presentation.
2. Define abstract repository interfaces in `domain/repositories/`.
3. Implement concrete repositories in `data/repositories/`.
4. Use Riverpod providers for all injectable dependencies.
5. Never import `data/` from `domain/` — the dependency arrow points inward.
6. Use `freezed` + `json_serializable` for data models.
7. Add comprehensive error handling — no unhandled exceptions.
8. Write dartdoc for every public API.
9. Keep files under 300 lines — split large files.
10. Use barrel exports for every module.
''';

  @override
  List<ModelCapability> get preferredCapabilities => const [
        ModelCapability.coding,
        ModelCapability.reasoning,
        ModelCapability.toolUse,
      ];

  @override
  Future<AgentResult> executeTask(AgentTask task) {
    return runTaskLifecycle(task, () async {
      // 1. Retrieve architectural context.
      final context = await retrieveContext(
        '${task.description} architecture clean code dart',
      );

      // 2. Analyse the task for architectural impact.
      final analysis = _analyzeArchitecturalTask(task, context);

      // 3. Execute code generation / modification steps.
      final artifacts = <String>[];
      final outputs = <String>[];

      for (final step in analysis['steps'] as List<Map<String, String>>) {
        final result = await _executeArchStep(step, task);
        if (result.success) {
          outputs.add(result.output);
          if (result.metadata.containsKey('filePath')) {
            artifacts.add(result.metadata['filePath'] as String);
          }
        }
      }

      // 4. Run static analysis.
      final analyzeResult = await useTool('flutter_analyze', {
        'paths': artifacts,
      });

      // 5. Persist knowledge.
      await saveToMemory(MemoryEntry(
        id: _uuid.v4(),
        content: 'Architecture task: ${task.description}\n'
            'Files modified: ${artifacts.join(", ")}\n'
            'Layers affected: ${analysis["layers"]}',
        source: id,
        timestamp: DateTime.now(),
        tags: ['backend', 'architecture', task.type.name],
      ));

      return AgentResult(
        taskId: task.id,
        success: true,
        output: outputs.join('\n\n'),
        artifacts: artifacts,
        nextSteps: _suggestArchNextSteps(analysis),
      );
    });
  }

  /// Analyses the architectural scope of a task.
  Map<String, dynamic> _analyzeArchitecturalTask(
    AgentTask task,
    List<MemoryEntry> context,
  ) {
    final desc = task.description.toLowerCase();
    final layers = <String>[];
    final steps = <Map<String, String>>[];

    if (desc.contains('api') || desc.contains('service')) {
      layers.addAll(['data', 'domain']);
      steps.addAll([
        {'action': 'create_interface', 'layer': 'domain'},
        {'action': 'implement_service', 'layer': 'data'},
        {'action': 'create_provider', 'layer': 'providers'},
      ]);
    } else if (desc.contains('repository')) {
      layers.addAll(['data', 'domain']);
      steps.addAll([
        {'action': 'define_repository', 'layer': 'domain'},
        {'action': 'implement_repository', 'layer': 'data'},
        {'action': 'create_provider', 'layer': 'providers'},
      ]);
    } else if (desc.contains('model') || desc.contains('entity')) {
      layers.add('domain');
      steps.add({'action': 'create_entity', 'layer': 'domain'});
    } else if (desc.contains('state') || desc.contains('provider')) {
      layers.add('providers');
      steps.add({'action': 'create_provider', 'layer': 'providers'});
    } else {
      layers.addAll(['domain', 'data']);
      steps.addAll([
        {'action': 'analyze_structure', 'layer': 'all'},
        {'action': 'implement', 'layer': 'data'},
      ]);
    }

    return {
      'layers': layers,
      'steps': steps,
      'contextEntries': context.length,
    };
  }

  /// Executes a single architectural step.
  Future<ToolResult> _executeArchStep(
    Map<String, String> step,
    AgentTask task,
  ) async {
    return useTool('write_file', {
      'action': step['action'],
      'layer': step['layer'],
      'description': task.description,
      'context': task.context,
    });
  }

  /// Suggests follow-up steps after an architecture task.
  List<String> _suggestArchNextSteps(Map<String, dynamic> analysis) {
    final steps = <String>[
      'Write unit tests for new services/repositories',
      'Update barrel exports for affected modules',
    ];

    final layers = analysis['layers'] as List<String>;
    if (layers.contains('data')) {
      steps.add('Verify error handling in data-layer implementations');
    }
    if (layers.contains('domain')) {
      steps.add('Review domain interfaces for completeness');
    }

    return steps;
  }
}
