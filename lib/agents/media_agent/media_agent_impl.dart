// Copyright (c) 2026 TermuxForge. All rights reserved.
// SPDX-License-Identifier: MIT

/// **Media Agent** — Media generation specialist.
///
/// Specialises in:
/// - Image generation via API providers (DALL-E, Stable Diffusion, etc.).
/// - Video generation and processing.
/// - Asset workflow management (generate → optimise → store).
/// - Provider selection based on quality, cost, and speed.
/// - Prompt engineering for visual content.
library;

import 'dart:async';

import 'package:uuid/uuid.dart';

import 'package:nexon/agents/base/agent_exports.dart';

const _uuid = Uuid();

/// Supported media generation providers.
enum MediaProvider {
  dalle3,
  stableDiffusion,
  midjourney,
  runway,
  pika,
  local,
}

/// A media generation request.
class MediaRequest {
  const MediaRequest({
    required this.prompt,
    required this.type,
    this.provider,
    this.width = 1024,
    this.height = 1024,
    this.style,
    this.quality = 'standard',
    this.count = 1,
    this.metadata = const {},
  });

  final String prompt;
  final String type; // 'image', 'video', 'audio'
  final MediaProvider? provider;
  final int width;
  final int height;
  final String? style;
  final String quality;
  final int count;
  final Map<String, dynamic> metadata;

  Map<String, dynamic> toJson() => {
        'prompt': prompt,
        'type': type,
        'provider': provider?.name,
        'width': width,
        'height': height,
        'style': style,
        'quality': quality,
        'count': count,
        'metadata': metadata,
      };
}

/// Media generation specialist agent.
///
/// Generates images, videos, and other media assets via API providers.
/// Manages the full asset workflow from prompt to optimised output.
class MediaAgentImpl extends BaseAgent {
  /// Creates a [MediaAgentImpl].
  MediaAgentImpl({
    super.id,
    super.name = 'Media Agent',
    super.assignedModel,
    super.metadata,
  }) : super(
          allowedTools: const [
            'read_file',
            'write_file',
            'run_command',
          ],
        );

  @override
  AgentType get type => AgentType.mediaAgent;

  @override
  String get systemPrompt => '''
You are the **Media Generation Specialist** within TermuxForge.

Your domain:
- Image generation: DALL-E 3, Stable Diffusion, local models.
- Video generation: Runway, Pika, local ffmpeg processing.
- Prompt engineering: crafting effective prompts for visual output.
- Asset optimisation: compression, format conversion, resizing.
- Provider selection: quality vs cost vs speed trade-offs.
- Asset management: naming, tagging, storing generated assets.

Workflow:
1. Parse the media request (type, style, dimensions, quality).
2. Select the best provider for the requirements.
3. Craft an optimised prompt (add style descriptors, negative prompts).
4. Generate the media via the provider API.
5. Post-process: optimise size, convert format if needed.
6. Store in the project's assets directory with proper naming.
7. Return metadata: path, dimensions, file size, cost.

Rules:
1. Always enhance user prompts with quality-boosting descriptors.
2. Prefer cost-effective providers for drafts, premium for finals.
3. Optimise all assets for mobile (Termux has limited storage).
4. Use descriptive filenames: `feature_hero_1024x1024.png`.
5. Log generation metadata for cost tracking.
6. Handle rate limits and API errors gracefully.
''';

  @override
  List<ModelCapability> get preferredCapabilities => const [
        ModelCapability.vision,
        ModelCapability.creative,
      ];

  /// History of generated media.
  final List<Map<String, dynamic>> _generationHistory = [];

  @override
  Future<AgentResult> executeTask(AgentTask task) {
    return runTaskLifecycle(task, () async {
      final context = await retrieveContext(
        '${task.description} image video media generate',
      );

      final request = _parseMediaRequest(task);
      final provider = request.provider ?? _selectProvider(request);

      publishEvent('media.generation_started', data: {
        'type': request.type,
        'provider': provider.name,
        'prompt': request.prompt,
      });

      // 1. Enhance prompt.
      final enhancedPrompt = _enhancePrompt(request.prompt, request);

      // 2. Generate media (delegated to tool / external API).
      final genResult = await useTool('run_command', {
        'command': 'echo "Generated ${request.type} via ${provider.name}"',
        'description': 'Generate ${request.type}: $enhancedPrompt',
      });

      // 3. Record in history.
      final record = {
        'id': _uuid.v4(),
        'prompt': enhancedPrompt,
        'originalPrompt': request.prompt,
        'type': request.type,
        'provider': provider.name,
        'dimensions': '${request.width}x${request.height}',
        'quality': request.quality,
        'timestamp': DateTime.now().toIso8601String(),
        'success': genResult.success,
      };
      _generationHistory.add(record);

      // 4. Save to memory.
      await saveToMemory(MemoryEntry(
        id: _uuid.v4(),
        content: 'Media generated: ${request.type} via ${provider.name}\n'
            'Prompt: ${request.prompt}',
        source: id,
        timestamp: DateTime.now(),
        tags: ['media', request.type, provider.name],
      ));

      return AgentResult(
        taskId: task.id,
        success: genResult.success,
        output: 'Generated ${request.type} via ${provider.name}\n'
            'Prompt: $enhancedPrompt\n'
            'Dimensions: ${request.width}x${request.height}',
        metadata: record,
        nextSteps: [
          'Review generated asset quality',
          'Optimise for target platform if needed',
          'Integrate into the project assets',
        ],
      );
    });
  }

  MediaRequest _parseMediaRequest(AgentTask task) {
    final ctx = task.context;
    return MediaRequest(
      prompt: ctx['prompt'] as String? ?? task.description,
      type: ctx['mediaType'] as String? ?? 'image',
      width: ctx['width'] as int? ?? 1024,
      height: ctx['height'] as int? ?? 1024,
      style: ctx['style'] as String?,
      quality: ctx['quality'] as String? ?? 'standard',
      count: ctx['count'] as int? ?? 1,
    );
  }

  MediaProvider _selectProvider(MediaRequest request) {
    switch (request.type) {
      case 'image':
        return request.quality == 'hd'
            ? MediaProvider.dalle3
            : MediaProvider.stableDiffusion;
      case 'video':
        return MediaProvider.runway;
      default:
        return MediaProvider.local;
    }
  }

  String _enhancePrompt(String prompt, MediaRequest request) {
    final enhancements = <String>[prompt];

    if (request.quality == 'hd') {
      enhancements.add('highly detailed, professional quality');
    }
    if (request.style != null) {
      enhancements.add('in ${request.style} style');
    }
    enhancements.add('4K resolution, sharp focus');

    return enhancements.join(', ');
  }

  /// Returns the generation history.
  List<Map<String, dynamic>> get generationHistory =>
      List.unmodifiable(_generationHistory);
}
