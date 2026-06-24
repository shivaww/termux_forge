// Copyright (c) 2026 TermuxForge. All rights reserved.
// SPDX-License-Identifier: MIT

/// **Frontend Expert Agent** — Flutter UI specialist.
///
/// Specialises in:
/// - Building Flutter widgets with Material You / Material 3 design.
/// - Responsive layouts across phone, tablet, and desktop.
/// - Animations, transitions, and micro-interactions.
/// - Theme integration and design tokens.
/// - Accessibility and internationalisation.
library;

import 'dart:async';

import 'package:uuid/uuid.dart';

import 'package:nexon/agents/base/agent_exports.dart';

const _uuid = Uuid();

/// Flutter UI specialist agent.
///
/// This agent handles all presentation-layer tasks including widget
/// construction, theming, responsive layout, and animation work.
class FrontendExpertAgent extends BaseAgent {
  /// Creates a [FrontendExpertAgent].
  FrontendExpertAgent({
    super.id,
    super.name = 'Frontend Expert',
    super.assignedModel,
    super.metadata,
  }) : super(
          allowedTools: const [
            'flutter_run',
            'flutter_build',
            'flutter_analyze',
            'read_file',
            'write_file',
            'edit_file',
            'search_files',
          ],
        );

  @override
  AgentType get type => AgentType.frontendExpert;

  @override
  String get systemPrompt => '''
You are a **Flutter UI Expert** within the TermuxForge agentic IDE.

Your domain:
- Flutter widgets, Material 3 / Material You design system.
- Responsive layouts using LayoutBuilder, MediaQuery, and breakpoints.
- Animations with flutter_animate, Hero, AnimatedContainer, custom tweens.
- Theme creation: ColorScheme, TextTheme, component themes.
- State-to-UI binding with Riverpod consumers.
- Accessibility: semantics, contrast, touch targets.
- Performance: const constructors, RepaintBoundary, lazy loading.

Rules:
1. Always use Material 3 components (FilledButton, NavigationBar, etc.).
2. Extract reusable widgets into separate files.
3. Keep build methods under 50 lines — extract helper methods.
4. Add dartdoc comments to every public widget.
5. Use const constructors wherever possible.
6. Follow the project's theme tokens — never hard-code colours.
7. Test widgets with golden tests when visual fidelity matters.
8. Make every screen responsive — support 320dp to 1200dp+.
''';

  @override
  List<ModelCapability> get preferredCapabilities => const [
        ModelCapability.coding,
        ModelCapability.creative,
        ModelCapability.toolUse,
      ];

  @override
  Future<AgentResult> executeTask(AgentTask task) {
    return runTaskLifecycle(task, () async {
      // 1. Retrieve relevant UI context.
      final context = await retrieveContext(
        '${task.description} flutter widget material design',
      );

      // 2. Analyse the task.
      final analysis = _analyzeUiTask(task, context);

      // 3. Generate UI code via tools.
      final artifacts = <String>[];
      final outputs = <String>[];

      for (final step in analysis['steps'] as List<String>) {
        final toolResult = await _executeUiStep(step, task);
        if (toolResult.success) {
          outputs.add(toolResult.output);
          if (toolResult.metadata.containsKey('filePath')) {
            artifacts.add(toolResult.metadata['filePath'] as String);
          }
        }
      }

      // 4. Verify with flutter_analyze.
      final analyzeResult = await useTool('flutter_analyze', {
        'paths': artifacts,
      });

      // 5. Save learning to memory.
      await saveToMemory(MemoryEntry(
        id: _uuid.v4(),
        content: 'UI task: ${task.description}\n'
            'Components created: ${artifacts.join(", ")}\n'
            'Analysis clean: ${analyzeResult.success}',
        source: id,
        timestamp: DateTime.now(),
        tags: ['frontend', 'ui', 'flutter', task.type.name],
      ));

      return AgentResult(
        taskId: task.id,
        success: analyzeResult.success || artifacts.isNotEmpty,
        output: outputs.join('\n\n'),
        artifacts: artifacts,
        nextSteps: _suggestUiNextSteps(task),
      );
    });
  }

  /// Analyses a UI task and returns a structured step plan.
  Map<String, dynamic> _analyzeUiTask(
    AgentTask task,
    List<MemoryEntry> context,
  ) {
    final steps = <String>[];

    // Determine what kind of UI work is needed.
    final desc = task.description.toLowerCase();

    if (desc.contains('screen') || desc.contains('page')) {
      steps.addAll([
        'scaffold_screen',
        'add_app_bar',
        'build_body',
        'add_navigation',
        'make_responsive',
      ]);
    } else if (desc.contains('widget') || desc.contains('component')) {
      steps.addAll([
        'create_widget',
        'add_theming',
        'add_animation',
      ]);
    } else if (desc.contains('theme') || desc.contains('design')) {
      steps.addAll([
        'define_color_scheme',
        'define_text_theme',
        'create_component_themes',
      ]);
    } else {
      steps.addAll(['analyze_requirement', 'implement_ui', 'verify']);
    }

    return {
      'taskType': 'ui',
      'steps': steps,
      'contextCount': context.length,
    };
  }

  /// Executes a single UI generation step.
  Future<ToolResult> _executeUiStep(String step, AgentTask task) async {
    switch (step) {
      case 'scaffold_screen':
      case 'create_widget':
      case 'implement_ui':
        return useTool('write_file', {
          'description': 'Generate Flutter widget for: ${task.description}',
          'step': step,
          'context': task.context,
        });
      case 'add_theming':
      case 'define_color_scheme':
      case 'define_text_theme':
      case 'create_component_themes':
        return useTool('write_file', {
          'description': 'Generate theme configuration',
          'step': step,
        });
      case 'verify':
      case 'make_responsive':
        return useTool('flutter_analyze', {
          'description': 'Verify generated code',
        });
      default:
        return useTool('read_file', {
          'description': 'Read context for step: $step',
        });
    }
  }

  /// Suggests follow-up steps after a UI task.
  List<String> _suggestUiNextSteps(AgentTask task) {
    return [
      'Run widget tests for new components',
      'Check responsive breakpoints on multiple device sizes',
      'Verify theme consistency with existing screens',
      'Add golden test snapshots if visual fidelity is important',
    ];
  }
}
