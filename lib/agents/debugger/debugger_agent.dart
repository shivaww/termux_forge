// Copyright (c) 2026 TermuxForge. All rights reserved.
// SPDX-License-Identifier: MIT

/// **Debugger Agent** — Debug specialist.
///
/// Specialises in:
/// - Runtime error diagnosis and stack trace analysis.
/// - Flutter-specific issues (widget errors, rendering, state).
/// - Termux environment issues (paths, permissions, packages).
/// - Python bridge issues (process spawning, IPC).
/// - MCP connection and protocol issues.
/// - Memory leaks and performance bottlenecks.
library;

import 'dart:async';

import 'package:uuid/uuid.dart';

import 'package:nexon/agents/base/agent_exports.dart';

const _uuid = Uuid();

/// Debugging specialist agent.
///
/// Diagnoses runtime errors, Flutter issues, Termux environment
/// problems, and cross-layer integration bugs.
class DebuggerAgent extends BaseAgent {
  /// Creates a [DebuggerAgent].
  DebuggerAgent({
    super.id,
    super.name = 'Debugger',
    super.assignedModel,
    super.metadata,
  }) : super(
          allowedTools: const [
            'read_file',
            'edit_file',
            'run_command',
            'flutter_analyze',
            'search_files',
            'flutter_run',
          ],
        );

  @override
  AgentType get type => AgentType.debugger;

  @override
  String get systemPrompt => '''
You are a **Debug Specialist** within the TermuxForge agentic IDE.

Your domain:
- Stack trace analysis and root-cause identification.
- Flutter widget errors: RenderFlex overflow, setState after dispose,
  missing keys, infinite rebuilds.
- Dart runtime errors: null safety violations, type mismatches,
  async/await issues, isolate problems.
- Termux-specific issues: missing packages, path problems, permission
  denied, proot limitations.
- Python bridge issues: subprocess spawning, stdin/stdout IPC, encoding.
- MCP protocol issues: connection timeouts, malformed messages,
  capability mismatches.
- Performance: jank, memory leaks, excessive rebuilds.

Rules:
1. Always start by reading the error message and stack trace carefully.
2. Reproduce the issue before attempting a fix.
3. Identify the root cause — don't just suppress symptoms.
4. Explain the diagnosis clearly to aid learning.
5. Provide the minimal fix — don't refactor unrelated code.
6. Suggest preventive measures (tests, assertions, linting rules).
7. Check for regression after fixing.
8. Log useful debugging information to memory for future reference.
''';

  @override
  List<ModelCapability> get preferredCapabilities => const [
        ModelCapability.coding,
        ModelCapability.reasoning,
        ModelCapability.longContext,
        ModelCapability.toolUse,
      ];

  @override
  Future<AgentResult> executeTask(AgentTask task) {
    return runTaskLifecycle(task, () async {
      final context = await retrieveContext(
        '${task.description} error debug fix',
      );

      final outputs = <String>[];
      final artifacts = <String>[];

      // 1. Analyse the error.
      final diagnosis = await _diagnoseError(task, context);
      outputs.add('## Diagnosis\n${diagnosis["summary"]}');

      // 2. Locate the problematic code.
      final searchResult = await useTool('search_files', {
        'query': diagnosis['searchQuery'] ?? task.description,
        'fileTypes': ['dart'],
      });

      if (searchResult.success) {
        outputs.add('## Relevant Files\n${searchResult.output}');
      }

      // 3. Read the suspect files.
      for (final filePath
          in (diagnosis['suspectFiles'] as List<String>? ?? <String>[])) {
        final readResult = await useTool('read_file', {'path': filePath});
        if (readResult.success) {
          outputs.add('## File: $filePath\n${readResult.output}');
        }
      }

      // 4. Apply fix.
      final fixResult = await _applyFix(diagnosis, task);
      if (fixResult.success) {
        outputs.add('## Fix Applied\n${fixResult.output}');
        if (fixResult.metadata.containsKey('filePath')) {
          artifacts.add(fixResult.metadata['filePath'] as String);
        }
      }

      // 5. Verify fix.
      final verifyResult = await useTool('flutter_analyze', {
        'paths': artifacts,
      });
      outputs.add('## Verification\n'
          'Clean: ${verifyResult.success}\n${verifyResult.output}');

      // 6. Save to memory.
      await saveToMemory(MemoryEntry(
        id: _uuid.v4(),
        content: 'Debug: ${task.description}\n'
            'Root cause: ${diagnosis["rootCause"]}\n'
            'Fix: ${diagnosis["fixSummary"]}',
        source: id,
        timestamp: DateTime.now(),
        tags: ['debug', 'fix', diagnosis['category'] as String? ?? 'general'],
      ));

      return AgentResult(
        taskId: task.id,
        success: verifyResult.success,
        output: outputs.join('\n\n'),
        artifacts: artifacts,
        nextSteps: [
          'Add a regression test for the fixed issue',
          'Review related code for similar patterns',
          'Update error handling to prevent recurrence',
        ],
      );
    });
  }

  Future<Map<String, dynamic>> _diagnoseError(
    AgentTask task,
    List<MemoryEntry> context,
  ) async {
    final desc = task.description.toLowerCase();
    String category = 'general';
    String searchQuery = task.description;

    if (desc.contains('render') || desc.contains('overflow')) {
      category = 'flutter_render';
      searchQuery = 'RenderFlex overflow widget';
    } else if (desc.contains('null') || desc.contains('type')) {
      category = 'dart_runtime';
      searchQuery = 'null check type mismatch';
    } else if (desc.contains('termux') || desc.contains('permission')) {
      category = 'termux_env';
      searchQuery = 'termux permission path';
    } else if (desc.contains('mcp') || desc.contains('connection')) {
      category = 'mcp_protocol';
      searchQuery = 'mcp connection timeout';
    } else if (desc.contains('python') || desc.contains('bridge')) {
      category = 'python_bridge';
      searchQuery = 'python subprocess ipc';
    }

    return {
      'category': category,
      'searchQuery': searchQuery,
      'summary': 'Analysing $category issue: ${task.description}',
      'rootCause': 'Pending diagnosis via LLM analysis',
      'fixSummary': 'Pending fix generation',
      'suspectFiles': task.context['files'] as List<String>? ?? <String>[],
    };
  }

  Future<ToolResult> _applyFix(
    Map<String, dynamic> diagnosis,
    AgentTask task,
  ) async {
    return useTool('edit_file', {
      'diagnosis': diagnosis,
      'description': task.description,
      'context': task.context,
    });
  }
}
