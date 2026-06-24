// Copyright (c) 2026 TermuxForge. All rights reserved.
// SPDX-License-Identifier: MIT

/// **Researcher Agent** — Research & documentation specialist.
///
/// Specialises in:
/// - Web research via MCP server tools.
/// - Package discovery and evaluation.
/// - Documentation lookup and summarisation.
/// - Best-practice research and comparison.
/// - Technology evaluation and recommendation.
library;

import 'dart:async';

import 'package:uuid/uuid.dart';

import 'package:nexon/agents/base/agent_exports.dart';

const _uuid = Uuid();

/// Research specialist agent.
///
/// Uses MCP-connected web search and documentation tools to gather
/// information, evaluate packages, and provide recommendations.
class ResearcherAgent extends BaseAgent {
  /// Creates a [ResearcherAgent].
  ResearcherAgent({
    super.id,
    super.name = 'Researcher',
    super.assignedModel,
    super.metadata,
  }) : super(
          allowedTools: const [
            'search_web_via_mcp',
            'research_query_via_mcp',
            'read_file',
            'write_file',
          ],
        );

  @override
  AgentType get type => AgentType.researcher;

  @override
  String get systemPrompt => '''
You are a **Research Specialist** within the TermuxForge agentic IDE.

Your domain:
- Web research using MCP server tools (search_web_via_mcp).
- Flutter/Dart package research on pub.dev.
- Documentation lookup and API reference summarisation.
- Technology comparison and evaluation.
- Best-practice discovery and synthesis.
- Security advisory and vulnerability checking.

Rules:
1. Always cite sources with URLs.
2. Summarise findings concisely — bullet points over paragraphs.
3. When evaluating packages, check: maintenance status, popularity,
   compatibility, license, and known issues.
4. Prefer official documentation over blog posts.
5. Flag any security concerns immediately.
6. Save key findings to memory for future reference.
7. Provide actionable recommendations, not just raw information.
8. Compare at least 2-3 alternatives when evaluating options.
''';

  @override
  List<ModelCapability> get preferredCapabilities => const [
        ModelCapability.reasoning,
        ModelCapability.longContext,
        ModelCapability.toolUse,
      ];

  @override
  Future<AgentResult> executeTask(AgentTask task) {
    return runTaskLifecycle(task, () async {
      final context = await retrieveContext(task.description);
      final outputs = <String>[];
      final sources = <String>[];

      // 1. Perform web search.
      final searchResult = await useTool('search_web_via_mcp', {
        'query': task.description,
        'maxResults': 10,
      });

      if (searchResult.success) {
        outputs.add('## Search Results\n${searchResult.output}');
        if (searchResult.metadata.containsKey('urls')) {
          sources.addAll(
            (searchResult.metadata['urls'] as List<dynamic>).cast<String>(),
          );
        }
      }

      // 2. Deep research on specific topics.
      final researchResult = await useTool('research_query_via_mcp', {
        'query': task.description,
        'depth': 'detailed',
        'context': context.map((e) => e.content).join('\n'),
      });

      if (researchResult.success) {
        outputs.add('## Detailed Research\n${researchResult.output}');
      }

      // 3. Synthesise findings.
      final synthesis = _synthesizeFindings(outputs, sources);

      // 4. Save to memory.
      await saveToMemory(MemoryEntry(
        id: _uuid.v4(),
        content: 'Research: ${task.description}\n'
            'Sources: ${sources.join(", ")}\n'
            'Summary: $synthesis',
        source: id,
        timestamp: DateTime.now(),
        tags: ['research', 'findings', task.type.name],
      ));

      return AgentResult(
        taskId: task.id,
        success: true,
        output: synthesis,
        nextSteps: [
          'Review research findings and decide on approach',
          'Implement recommended solution',
          'Re-research if findings are inconclusive',
        ],
        metadata: {'sources': sources},
      );
    });
  }

  String _synthesizeFindings(List<String> outputs, List<String> sources) {
    final buffer = StringBuffer();
    buffer.writeln('# Research Findings\n');

    for (final output in outputs) {
      buffer.writeln(output);
      buffer.writeln();
    }

    if (sources.isNotEmpty) {
      buffer.writeln('## Sources');
      for (var i = 0; i < sources.length; i++) {
        buffer.writeln('${i + 1}. ${sources[i]}');
      }
    }

    return buffer.toString();
  }
}
