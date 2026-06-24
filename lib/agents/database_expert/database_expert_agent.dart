// Copyright (c) 2026 TermuxForge. All rights reserved.
// SPDX-License-Identifier: MIT

/// **Database Expert Agent** — Database specialist.
///
/// Specialises in:
/// - Isar database schema design and optimisation.
/// - Migration strategies and version management.
/// - Query optimisation and index design.
/// - Data integrity and validation.
/// - Cache strategies and offline-first patterns.
library;

import 'dart:async';

import 'package:uuid/uuid.dart';

import 'package:nexon/agents/base/agent_exports.dart';

const _uuid = Uuid();

/// Database specialist agent.
///
/// Handles Isar schema design, migrations, query optimisation,
/// indexing strategies, and data-layer architecture.
class DatabaseExpertAgent extends BaseAgent {
  /// Creates a [DatabaseExpertAgent].
  DatabaseExpertAgent({
    super.id,
    super.name = 'Database Expert',
    super.assignedModel,
    super.metadata,
  }) : super(
          allowedTools: const [
            'read_file',
            'write_file',
            'edit_file',
            'run_command',
            'search_files',
          ],
        );

  @override
  AgentType get type => AgentType.databaseExpert;

  @override
  String get systemPrompt => '''
You are a **Database Expert** within the TermuxForge agentic IDE.

Your domain:
- Isar NoSQL database: collections, schemas, links, embedded objects.
- Index design: composite indexes, hash indexes, case-insensitive indexes.
- Query optimisation: filters, sorting, pagination, where clauses.
- Migration strategies: schema versioning, data migration scripts.
- Offline-first architecture: sync queues, conflict resolution.
- Data validation and integrity constraints.
- Cache layers: in-memory LRU, TTL-based expiry.

Rules:
1. Always annotate Isar collections with `@collection`.
2. Design indexes based on actual query patterns — never over-index.
3. Use embedded objects for small, frequently-accessed nested data.
4. Use links for large or independently-queried related data.
5. Write migration functions for every schema change.
6. Add dartdoc to every collection and field.
7. Keep collection files in `data/local/collections/`.
8. Provide repository interfaces in `domain/repositories/`.
9. Test queries with representative data volumes.
10. Consider storage size on mobile — Termux has limited space.
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
        '${task.description} isar database schema query',
      );

      final analysis = _analyzeDatabaseTask(task, context);
      final artifacts = <String>[];
      final outputs = <String>[];

      for (final step in analysis['steps'] as List<String>) {
        final result = await _executeDatabaseStep(step, task);
        if (result.success) {
          outputs.add(result.output);
          if (result.metadata.containsKey('filePath')) {
            artifacts.add(result.metadata['filePath'] as String);
          }
        }
      }

      await saveToMemory(MemoryEntry(
        id: _uuid.v4(),
        content: 'Database task: ${task.description}\n'
            'Collections affected: ${analysis["collections"]}\n'
            'Files: ${artifacts.join(", ")}',
        source: id,
        timestamp: DateTime.now(),
        tags: ['database', 'isar', task.type.name],
      ));

      return AgentResult(
        taskId: task.id,
        success: true,
        output: outputs.join('\n\n'),
        artifacts: artifacts,
        nextSteps: [
          'Run isar_generator via build_runner',
          'Write migration if schema changed',
          'Add query-performance tests with mock data',
        ],
      );
    });
  }

  Map<String, dynamic> _analyzeDatabaseTask(
    AgentTask task,
    List<MemoryEntry> context,
  ) {
    final desc = task.description.toLowerCase();
    final steps = <String>[];
    final collections = <String>[];

    if (desc.contains('schema') || desc.contains('collection')) {
      steps.addAll(['design_schema', 'add_indexes', 'generate_code']);
      collections.add('new_collection');
    } else if (desc.contains('migration')) {
      steps.addAll(['read_current_schema', 'write_migration', 'test_migration']);
    } else if (desc.contains('query') || desc.contains('search')) {
      steps.addAll(['analyze_query', 'optimize_index', 'implement_query']);
    } else {
      steps.addAll(['analyze_requirement', 'implement_database_layer']);
    }

    return {
      'steps': steps,
      'collections': collections,
      'contextEntries': context.length,
    };
  }

  Future<ToolResult> _executeDatabaseStep(String step, AgentTask task) async {
    return useTool('write_file', {
      'step': step,
      'description': task.description,
      'context': task.context,
    });
  }
}
