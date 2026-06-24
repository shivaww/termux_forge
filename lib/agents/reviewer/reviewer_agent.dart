// Copyright (c) 2026 TermuxForge. All rights reserved.
// SPDX-License-Identifier: MIT

/// **Reviewer Agent** — Code review specialist.
///
/// Specialises in:
/// - Code quality analysis and scoring.
/// - Security vulnerability detection.
/// - Maintainability and readability assessment.
/// - Architecture conformance checking.
/// - Performance anti-pattern detection.
/// - Refactoring suggestions with concrete examples.
library;

import 'dart:async';

import 'package:uuid/uuid.dart';

import 'package:nexon/agents/base/agent_exports.dart';

const _uuid = Uuid();

/// Code review specialist agent.
///
/// Performs comprehensive code reviews focusing on quality, security,
/// maintainability, and adherence to project conventions.
class ReviewerAgent extends BaseAgent {
  /// Creates a [ReviewerAgent].
  ReviewerAgent({
    super.id,
    super.name = 'Reviewer',
    super.assignedModel,
    super.metadata,
  }) : super(
          allowedTools: const [
            'read_file',
            'search_files',
            'flutter_analyze',
          ],
        );

  @override
  AgentType get type => AgentType.reviewer;

  @override
  String get systemPrompt => '''
You are a **Code Review Specialist** within the TermuxForge agentic IDE.

Your domain:
- Code quality: naming, structure, complexity, documentation.
- Security: input validation, secrets exposure, SQL injection, XSS.
- Maintainability: coupling, cohesion, DRY, SOLID principles.
- Architecture: layer violations, dependency direction, module boundaries.
- Performance: unnecessary allocations, O(n²) loops, memory leaks.
- Dart/Flutter best practices: null safety, const, immutability.
- Test quality: coverage, assertions, edge cases.

Review format:
1. **Summary** — one-paragraph overall assessment.
2. **Critical** — issues that must be fixed (security, bugs, crashes).
3. **Important** — issues that should be fixed (quality, maintainability).
4. **Suggestions** — nice-to-have improvements.
5. **Positives** — things done well (always include at least one).
6. **Score** — rate 1-10 on: quality, security, maintainability.

Rules:
1. Be constructive — explain *why* something is a problem.
2. Provide concrete fix suggestions with code examples.
3. Never just say "looks good" — always find something to improve.
4. Check for clean-architecture layer violations.
5. Verify error handling is comprehensive.
6. Flag any hard-coded values that should be configurable.
7. Ensure dartdoc exists on all public APIs.
''';

  @override
  List<ModelCapability> get preferredCapabilities => const [
        ModelCapability.reasoning,
        ModelCapability.longContext,
        ModelCapability.coding,
      ];

  @override
  Future<AgentResult> executeTask(AgentTask task) {
    return runTaskLifecycle(task, () async {
      final context = await retrieveContext(
        '${task.description} code review quality',
      );

      final outputs = <String>[];
      final filesToReview = _extractFilePaths(task);

      // 1. Read each file.
      for (final filePath in filesToReview) {
        final readResult = await useTool('read_file', {'path': filePath});
        if (readResult.success) {
          final review = _generateReviewStructure(filePath, readResult.output);
          outputs.add(review);
        }
      }

      // 2. Run static analysis.
      final analyzeResult = await useTool('flutter_analyze', {
        'paths': filesToReview,
      });

      if (analyzeResult.success) {
        outputs.add('## Static Analysis\n${analyzeResult.output}');
      }

      // 3. Check for pattern violations.
      final patternCheck = await _checkPatterns(filesToReview);
      outputs.add(patternCheck);

      // 4. Save review to memory.
      await saveToMemory(MemoryEntry(
        id: _uuid.v4(),
        content: 'Code review: ${task.description}\n'
            'Files reviewed: ${filesToReview.length}\n'
            'Issues found: ${_countIssues(outputs)}',
        source: id,
        timestamp: DateTime.now(),
        tags: ['review', 'quality', task.type.name],
      ));

      return AgentResult(
        taskId: task.id,
        success: true,
        output: outputs.join('\n\n'),
        nextSteps: [
          'Address critical issues first',
          'Apply suggested refactoring for important issues',
          'Update tests to cover any bugs found',
        ],
      );
    });
  }

  List<String> _extractFilePaths(AgentTask task) {
    final files = task.context['files'] as List<dynamic>?;
    if (files != null) return files.cast<String>();

    final path = task.context['path'] as String?;
    if (path != null) return [path];

    return <String>[];
  }

  String _generateReviewStructure(String filePath, String content) {
    final lines = content.split('\n').length;
    return '''
## Review: $filePath
- **Lines**: $lines
- **Summary**: Pending LLM analysis
- **Critical**: Pending
- **Important**: Pending
- **Suggestions**: Pending
- **Positives**: Pending
- **Scores**: Quality: ?/10, Security: ?/10, Maintainability: ?/10
''';
  }

  Future<String> _checkPatterns(List<String> files) async {
    final issues = <String>[];

    for (final file in files) {
      // Search for common anti-patterns.
      final hardcodedResult = await useTool('search_files', {
        'query': 'TODO|FIXME|HACK|XXX',
        'paths': [file],
      });

      if (hardcodedResult.success && hardcodedResult.output.isNotEmpty) {
        issues.add('⚠️ $file contains TODO/FIXME/HACK markers');
      }
    }

    return issues.isEmpty
        ? '## Pattern Check\n✅ No anti-pattern markers found'
        : '## Pattern Check\n${issues.join("\n")}';
  }

  int _countIssues(List<String> outputs) {
    return outputs
        .where((o) => o.contains('Critical') || o.contains('⚠️'))
        .length;
  }
}
