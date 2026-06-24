// Copyright (c) 2026 TermuxForge. All rights reserved.
// SPDX-License-Identifier: MIT

/// **Tester Agent** — Testing specialist.
///
/// Specialises in:
/// - Unit test design and generation.
/// - Widget test creation with pump and golden tests.
/// - Integration test strategies.
/// - Test coverage analysis and gap identification.
/// - Mock and stub generation.
/// - Test-driven development guidance.
library;

import 'dart:async';

import 'package:uuid/uuid.dart';

import 'package:nexon/agents/base/agent_exports.dart';

const _uuid = Uuid();

/// Testing specialist agent.
///
/// Generates and runs unit tests, widget tests, and integration tests.
/// Analyses test coverage and identifies gaps.
class TesterAgent extends BaseAgent {
  /// Creates a [TesterAgent].
  TesterAgent({
    super.id,
    super.name = 'Tester',
    super.assignedModel,
    super.metadata,
  }) : super(
          allowedTools: const [
            'flutter_test',
            'read_file',
            'write_file',
            'edit_file',
            'run_command',
            'search_files',
          ],
        );

  @override
  AgentType get type => AgentType.tester;

  @override
  String get systemPrompt => '''
You are a **Testing Specialist** within the TermuxForge agentic IDE.

Your domain:
- Unit testing with `flutter_test` and `test` packages.
- Widget testing with `WidgetTester`, `pumpWidget`, `find`, `expect`.
- Golden tests for visual regression.
- Integration testing with `integration_test`.
- Mocking with `mockito` and `@GenerateMocks`.
- Test coverage analysis and gap identification.
- Test-driven development (TDD) guidance.

Rules:
1. Follow Arrange-Act-Assert (AAA) pattern.
2. One logical assertion per test — split complex tests.
3. Use descriptive test names: `should [expected] when [condition]`.
4. Group related tests with `group()`.
5. Mock all external dependencies — never hit real APIs in tests.
6. Test edge cases: null, empty, boundary values, error states.
7. Generate `@GenerateMocks` annotations for mockito.
8. Place tests in `test/` mirroring the `lib/` structure.
9. Aim for 80%+ code coverage on business logic.
10. Use `setUp` and `tearDown` for shared test fixtures.
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
      final context = await retrieveContext(
        '${task.description} test unit widget mock',
      );

      final analysis = _analyzeTestTask(task, context);
      final artifacts = <String>[];
      final outputs = <String>[];

      // 1. Generate test files.
      for (final testSpec in analysis['tests'] as List<Map<String, String>>) {
        final result = await _generateTest(testSpec, task);
        if (result.success) {
          outputs.add(result.output);
          if (result.metadata.containsKey('filePath')) {
            artifacts.add(result.metadata['filePath'] as String);
          }
        }
      }

      // 2. Run the tests.
      final runResult = await useTool('flutter_test', {
        'paths': artifacts,
        'coverage': true,
      });

      if (runResult.success) {
        outputs.add('## Test Results\n${runResult.output}');
      }

      // 3. Save results.
      await saveToMemory(MemoryEntry(
        id: _uuid.v4(),
        content: 'Testing task: ${task.description}\n'
            'Tests created: ${artifacts.length}\n'
            'Pass: ${runResult.success}',
        source: id,
        timestamp: DateTime.now(),
        tags: ['testing', 'quality', task.type.name],
      ));

      return AgentResult(
        taskId: task.id,
        success: runResult.success,
        output: outputs.join('\n\n'),
        artifacts: artifacts,
        nextSteps: [
          'Review test coverage report',
          'Add edge-case tests for uncovered branches',
          'Consider golden tests for UI components',
        ],
      );
    });
  }

  Map<String, dynamic> _analyzeTestTask(
    AgentTask task,
    List<MemoryEntry> context,
  ) {
    final desc = task.description.toLowerCase();
    final tests = <Map<String, String>>[];

    if (desc.contains('unit')) {
      tests.add({'type': 'unit', 'target': 'business_logic'});
    }
    if (desc.contains('widget')) {
      tests.add({'type': 'widget', 'target': 'ui_component'});
    }
    if (desc.contains('integration')) {
      tests.add({'type': 'integration', 'target': 'feature_flow'});
    }

    // Default: generate unit tests.
    if (tests.isEmpty) {
      tests.add({'type': 'unit', 'target': 'auto_detected'});
    }

    return {'tests': tests, 'contextEntries': context.length};
  }

  Future<ToolResult> _generateTest(
    Map<String, String> spec,
    AgentTask task,
  ) async {
    return useTool('write_file', {
      'testType': spec['type'],
      'target': spec['target'],
      'description': task.description,
      'context': task.context,
    });
  }
}
