// ============================================================================
// TermuxForge — LLM Service
// Multi-provider LLM routing with model selection, streaming, and battle mode.
// ============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:nexon/services/llm/llm_types.dart';
import 'package:nexon/services/event_bus/event_bus.dart';
import 'package:nexon/services/event_bus/event_types.dart';

/// Multi-provider LLM service with intelligent model routing.
///
/// Supports 30+ OpenAI-compatible endpoints, model selection by task type,
/// streaming chat, and battle mode for parallel model comparison.
///
/// ## Example
///
/// ```dart
/// final llm = LLMService.instance;
///
/// llm.addProvider(LLMProvider(
///   id: 'openai',
///   name: 'OpenAI',
///   baseUrl: 'https://api.openai.com/v1',
///   apiKey: 'sk-...',
/// ));
///
/// final result = await llm.chat(
///   modelId: 'gpt-4o',
///   messages: [
///     ChatMessage(role: 'user', content: 'Write a Dart hello world'),
///   ],
/// );
/// ```
class LLMService {
  // ---------------------------------------------------------------------------
  // Singleton
  // ---------------------------------------------------------------------------

  LLMService._internal();

  /// The global [LLMService] instance.
  static final LLMService instance = LLMService._internal();

  /// Factory constructor that returns the singleton [instance].
  factory LLMService() => instance;

  // ---------------------------------------------------------------------------
  // Internal state
  // ---------------------------------------------------------------------------

  /// Registered providers keyed by ID.
  final Map<String, LLMProvider> _providers = {};

  /// Event bus reference.
  final EventBus _eventBus = EventBus.instance;

  /// HTTP client for API requests.
  final HttpClient _httpClient = HttpClient();

  // ---------------------------------------------------------------------------
  // Provider Management
  // ---------------------------------------------------------------------------

  /// Registers a new LLM provider.
  ///
  /// If a provider with the same [LLMProvider.id] already exists, it is
  /// replaced.
  void addProvider(LLMProvider provider) {
    _providers[provider.id] = provider;
  }

  /// Removes the provider with the given [providerId].
  ///
  /// Returns `true` if the provider existed.
  bool removeProvider(String providerId) {
    return _providers.remove(providerId) != null;
  }

  /// Returns all registered providers.
  List<LLMProvider> listProviders() => List.unmodifiable(_providers.values);

  /// Returns the provider with the given [providerId], or `null`.
  LLMProvider? getProvider(String providerId) => _providers[providerId];

  // ---------------------------------------------------------------------------
  // Model Management
  // ---------------------------------------------------------------------------

  /// Returns all models across all providers.
  List<LLMModel> listModels({ModelCapability? capability}) {
    final allModels = _providers.values.expand((p) => p.models).toList();
    if (capability != null) {
      return allModels.where((m) => m.hasCapability(capability)).toList();
    }
    return allModels;
  }

  /// Finds the best model for a given task type.
  ///
  /// [taskType] can be: 'code', 'reason', 'fast', 'cheap', 'long_context',
  /// 'multimodal', 'image', 'video'.
  ///
  /// Returns `null` if no suitable model is found.
  LLMModel? selectModelForTask(String taskType) {
    final capability = _taskTypeToCapability(taskType);
    if (capability == null) return null;

    final candidates = listModels(capability: capability)
        .where((m) => m.isAvailable)
        .toList();

    if (candidates.isEmpty) return null;

    // Sort by provider priority, then by speed for fast tasks or cost for
    // cheap tasks.
    candidates.sort((a, b) {
      final provA = _providers[a.providerId]?.priority ?? 99;
      final provB = _providers[b.providerId]?.priority ?? 99;
      if (provA != provB) return provA.compareTo(provB);

      if (taskType == 'fast') return b.speed.compareTo(a.speed);
      if (taskType == 'cheap') {
        return a.costPerOutputToken.compareTo(b.costPerOutputToken);
      }
      return 0;
    });

    final selected = candidates.first;
    _eventBus.publish(ModelSelected(
      modelId: selected.id,
      providerId: selected.providerId,
      taskType: taskType,
      source: 'LLMService',
    ));

    return selected;
  }

  /// Discovers available models from a provider by calling its API.
  ///
  /// Requires the provider to support the `/v1/models` endpoint.
  Future<List<LLMModel>> discoverModels(String providerId) async {
    final provider = _providers[providerId];
    if (provider == null) {
      throw StateError('Provider "$providerId" not found');
    }

    try {
      final uri = Uri.parse('${provider.baseUrl}/models');
      final request = await _httpClient.getUrl(uri);
      _setProviderHeaders(request, provider);

      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final data = json['data'] as List<dynamic>? ?? [];

      final models = data.map<LLMModel>((item) {
        final modelData = item as Map<String, dynamic>;
        return LLMModel(
          id: modelData['id'] as String,
          name: modelData['id'] as String,
          providerId: providerId,
        );
      }).toList();

      // Merge discovered models with existing ones.
      final existingIds = provider.models.map((m) => m.id).toSet();
      for (final model in models) {
        if (!existingIds.contains(model.id)) {
          provider.models.add(model);
        }
      }

      return models;
    } catch (e) {
      throw StateError('Failed to discover models from "$providerId": $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Chat Completion
  // ---------------------------------------------------------------------------

  /// Sends a chat completion request to the specified model.
  ///
  /// Returns a [ChatResult] with the response and token usage.
  Future<ChatResult> chat({
    required String modelId,
    required List<ChatMessage> messages,
    double temperature = 0.7,
    int? maxTokens,
    List<Map<String, dynamic>>? tools,
  }) async {
    final model = _findModel(modelId);
    if (model == null) {
      throw StateError('Model "$modelId" not found');
    }

    final provider = _providers[model.providerId];
    if (provider == null) {
      throw StateError('Provider "${model.providerId}" not found');
    }

    final stopwatch = Stopwatch()..start();

    try {
      final uri = Uri.parse(_chatCompletionsEndpoint(provider));
      final request = await _httpClient.postUrl(uri);
      request.headers.set('Content-Type', 'application/json');
      _setProviderHeaders(request, provider);

      final body = <String, dynamic>{
        'model': modelId,
        'messages': messages.map((m) => m.toJson()).toList(),
        'temperature': temperature,
        if (maxTokens != null) 'max_tokens': maxTokens,
        if (tools != null) 'tools': tools,
      };

      request.write(jsonEncode(body));
      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();
      stopwatch.stop();

      if (response.statusCode != 200) {
        throw HttpException(
          'LLM API returned ${response.statusCode}: $responseBody',
        );
      }

      final json = jsonDecode(responseBody) as Map<String, dynamic>;
      final choice = (json['choices'] as List<dynamic>).first
          as Map<String, dynamic>;
      final message = choice['message'] as Map<String, dynamic>;
      final usage = json['usage'] as Map<String, dynamic>? ?? {};

      final inputTokens = (usage['prompt_tokens'] as int?) ?? 0;
      final outputTokens = (usage['completion_tokens'] as int?) ?? 0;
      final cost = model.estimateCost(inputTokens, outputTokens);

      _eventBus.publish(CostUpdated(
        providerId: model.providerId,
        totalCostUsd: cost,
        tokensUsed: inputTokens + outputTokens,
        source: 'LLMService',
      ));

      return ChatResult(
        modelId: modelId,
        content: (message['content'] as String?) ?? '',
        inputTokens: inputTokens,
        outputTokens: outputTokens,
        toolCalls: message['tool_calls'] as List<Map<String, dynamic>>?,
        finishReason: (choice['finish_reason'] as String?) ?? 'stop',
        duration: stopwatch.elapsed,
        estimatedCostUsd: cost,
      );
    } catch (e) {
      stopwatch.stop();
      rethrow;
    }
  }

  /// Sends a streaming chat completion request.
  ///
  /// Yields partial content strings as they arrive via SSE.
  Stream<String> streamChat({
    required String modelId,
    required List<ChatMessage> messages,
    double temperature = 0.7,
    int? maxTokens,
  }) async* {
    final model = _findModel(modelId);
    if (model == null) {
      throw StateError('Model "$modelId" not found');
    }

    final provider = _providers[model.providerId];
    if (provider == null) {
      throw StateError('Provider "${model.providerId}" not found');
    }

    try {
      final uri = Uri.parse(_chatCompletionsEndpoint(provider));
      final request = await _httpClient.postUrl(uri);
      request.headers.set('Content-Type', 'application/json');
      request.headers.set('Accept', 'text/event-stream');
      _setProviderHeaders(request, provider);

      final body = <String, dynamic>{
        'model': modelId,
        'messages': messages.map((m) => m.toJson()).toList(),
        'temperature': temperature,
        'stream': true,
        if (maxTokens != null) 'max_tokens': maxTokens,
      };

      request.write(jsonEncode(body));
      final response = await request.close();

      if (response.statusCode != 200) {
        final errorBody = await response.transform(utf8.decoder).join();
        throw HttpException(
          'LLM streaming API returned ${response.statusCode}: $errorBody',
        );
      }

      // Parse SSE stream. A JSON event can be split across network chunks.
      var buffer = '';
      await for (final chunk in response.transform(utf8.decoder)) {
        buffer += chunk;
        final lines = buffer.split('\n');
        buffer = lines.removeLast();
        for (final line in lines) {
          final content = _contentFromSseLine(line);
          if (content == null) continue;
          yield content;
        }
      }

      if (buffer.trim().isNotEmpty) {
        final content = _contentFromSseLine(buffer);
        if (content != null) yield content;
      }
    } catch (e) {
      // Re-yield error as a stream error.
      yield* Stream<String>.error(e);
    }
  }

  String? _contentFromSseLine(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || !trimmed.startsWith('data:')) return null;

    final data = trimmed.substring(5).trim();
    if (data == '[DONE]') return null;

    try {
      final json = jsonDecode(data) as Map<String, dynamic>;
      final choices = json['choices'] as List<dynamic>?;
      if (choices == null || choices.isEmpty) return null;

      final choice = choices.first as Map<String, dynamic>;
      final delta = choice['delta'] as Map<String, dynamic>?;
      final message = choice['message'] as Map<String, dynamic>?;
      final content = (delta?['content'] ??
              delta?['reasoning_content'] ??
              message?['content'] ??
              choice['text'])
          ?.toString();
      return content == null || content.isEmpty ? null : content;
    } catch (_) {
      // Skip malformed SSE chunks.
      return null;
    }
  }

  String _chatCompletionsEndpoint(LLMProvider provider) {
    final baseUrl = provider.baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (baseUrl.endsWith('/chat/completions')) return baseUrl;
    return '$baseUrl/chat/completions';
  }

  void _setProviderHeaders(HttpClientRequest request, LLMProvider provider) {
    if (provider.apiKey.trim().isNotEmpty) {
      request.headers.set('Authorization', 'Bearer ${provider.apiKey.trim()}');
    }
    for (final entry in provider.customHeaders.entries) {
      request.headers.set(entry.key, entry.value);
    }
  }

  // ---------------------------------------------------------------------------
  // Battle Mode
  // ---------------------------------------------------------------------------

  /// Runs a prompt against multiple models in parallel and returns all results.
  ///
  /// This is the "battle mode" feature for comparing model outputs.
  Future<BattleResult> battleMode({
    required String prompt,
    required List<String> modelIds,
    double temperature = 0.7,
    int? maxTokens,
  }) async {
    final messages = [ChatMessage(role: 'user', content: prompt)];
    final stopwatch = Stopwatch()..start();

    final futures = modelIds.map((modelId) async {
      try {
        return MapEntry(
          modelId,
          await chat(
            modelId: modelId,
            messages: messages,
            temperature: temperature,
            maxTokens: maxTokens,
          ),
        );
      } catch (e) {
        return MapEntry(
          modelId,
          ChatResult(
            modelId: modelId,
            content: 'ERROR: $e',
            finishReason: 'error',
          ),
        );
      }
    });

    final entries = await Future.wait(futures);
    stopwatch.stop();

    final results = Map<String, ChatResult>.fromEntries(entries);

    _eventBus.publish(ModelCompared(
      modelIds: modelIds,
      prompt: prompt,
      source: 'LLMService',
    ));

    return BattleResult(
      prompt: prompt,
      results: results,
      totalDuration: stopwatch.elapsed,
    );
  }

  // ---------------------------------------------------------------------------
  // Internal Helpers
  // ---------------------------------------------------------------------------

  /// Finds a model by ID across all providers.
  LLMModel? _findModel(String modelId) {
    for (final provider in _providers.values) {
      for (final model in provider.models) {
        if (model.id == modelId) return model;
      }
    }
    return null;
  }

  /// Maps a human-readable task type string to a [ModelCapability].
  ModelCapability? _taskTypeToCapability(String taskType) {
    return switch (taskType) {
      'code' => ModelCapability.coding,
      'reason' => ModelCapability.reasoning,
      'fast' => ModelCapability.fast,
      'cheap' => ModelCapability.cheap,
      'long_context' => ModelCapability.longContext,
      'multimodal' => ModelCapability.multimodal,
      'image' => ModelCapability.imageGeneration,
      'video' => ModelCapability.videoGeneration,
      'tool_use' => ModelCapability.toolUse,
      'web_search' => ModelCapability.webSearch,
      _ => null,
    };
  }

  // ---------------------------------------------------------------------------
  // Cleanup
  // ---------------------------------------------------------------------------

  /// Clears all providers and models.
  void reset() {
    _providers.clear();
  }

  /// Closes the HTTP client. Call only during app shutdown.
  void dispose() {
    _httpClient.close(force: true);
  }
}
