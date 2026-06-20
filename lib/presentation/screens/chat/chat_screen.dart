/// TermuxForge — Chat Screen
///
/// Functional LLM chat interface that:
/// - Loads the first configured provider from AppStorage
/// - Sends messages to the provider's OpenAI-compatible /chat/completions endpoint
/// - Streams responses via SSE (Server-Sent Events)
/// - Supports per-mode system prompts (code, architect, debug, ask, review, plan)
/// - Persists chat history in shared_preferences via AppStorage
/// - Renders markdown in assistant messages with code highlighting
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:termux_forge/core/theme/app_colors.dart';
import 'package:termux_forge/presentation/widgets/forge_app_bar.dart';
import 'package:termux_forge/presentation/widgets/glass_card.dart';
import 'package:termux_forge/services/storage/app_storage.dart';

// ─────────────────────────────────────────────────
//  Constants
// ─────────────────────────────────────────────────

const _kSystemPrompts = <String, String>{
  'code':
      'You are an expert programmer. Write clean, efficient code. Explain your approach briefly.',
  'architect':
      'You are a software architect. Design scalable systems and explain trade-offs.',
  'debug':
      'You are a debugging expert. Analyze errors systematically and provide fixes.',
  'ask':
      'You are a helpful AI assistant. Answer questions clearly and concisely.',
  'review':
      'You are a code reviewer. Analyze code for bugs, performance, and best practices.',
  'plan':
      'You are a project planner. Break down tasks, estimate effort, and create actionable plans.',
};

const _kModes = ['code', 'architect', 'debug', 'ask', 'review', 'plan'];

const _kModeIcons = <String, IconData>{
  'code': Icons.code_rounded,
  'architect': Icons.architecture_rounded,
  'debug': Icons.bug_report_rounded,
  'ask': Icons.chat_rounded,
  'review': Icons.rate_review_rounded,
  'plan': Icons.assignment_rounded,
};

// ─────────────────────────────────────────────────
//  Chat Message Model
// ─────────────────────────────────────────────────

class _ChatMessage {
  _ChatMessage({
    required this.role,
    required this.content,
    required this.timestamp,
    this.isStreaming = false,
  });

  final String role; // 'user' | 'assistant'
  String content;
  final DateTime timestamp;
  bool isStreaming;

  Map<String, dynamic> toJson() => {
        'role': role,
        'content': content,
        'timestamp': timestamp.toIso8601String(),
      };

  factory _ChatMessage.fromJson(Map<String, dynamic> json) => _ChatMessage(
        role: json['role'] as String,
        content: json['content'] as String,
        timestamp: DateTime.parse(json['timestamp'] as String),
      );

  /// Convert to the OpenAI messages format.
  Map<String, String> toApiMessage() => {
        'role': role,
        'content': content,
      };
}

// ─────────────────────────────────────────────────
//  Chat Screen
// ─────────────────────────────────────────────────

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();

  // Provider state
  List<Map<String, dynamic>> _providers = [];
  Map<String, dynamic>? _provider;
  String? _apiKey;
  String? _modelName;
  bool _providerLoading = true;
  String? _providerError;

  // Chat state
  final List<_ChatMessage> _messages = [];
  String _currentMode = 'ask';
  bool _isGenerating = false;
  HttpClient? _httpClient;
  StreamSubscription<dynamic>? _activeStream;

  @override
  void initState() {
    super.initState();
    _httpClient = HttpClient();
    _loadInitialState();
  }

  Future<void> _loadInitialState() async {
    await Future.wait([
      _loadProvider(),
      _loadMode(),
      _loadMessages(),
    ]);
  }

  Future<void> _loadProvider() async {
    try {
      final providers = await AppStorage.loadProviders();
      if (providers.isEmpty) {
        if (mounted) {
          setState(() {
            _providers = [];
            _providerLoading = false;
            _providerError = 'No API provider configured';
          });
        }
        return;
      }

      final normalized = providers.map(AppStorage.normalizeProvider).toList();
      final selectedProviderId = await AppStorage.getSelectedProviderId();
      final provider = normalized.firstWhere(
        (item) => item['id'] == selectedProviderId,
        orElse: () => normalized.first,
      );
      await _applyProvider(provider, allProviders: normalized);
    } catch (e) {
      if (mounted) {
        setState(() {
          _providerLoading = false;
          _providerError = 'Failed to load provider: $e';
        });
      }
    }
  }

  Future<void> _applyProvider(
    Map<String, dynamic> provider, {
    List<Map<String, dynamic>>? allProviders,
  }) async {
    try {
      final providerId = provider['id'] as String? ?? '';
      final apiKey = await AppStorage.getApiKey(providerId);
      final modelName = AppStorage.providerModelName(provider);
      final baseUrl = provider['baseUrl'] as String? ?? '';

      if (baseUrl.isEmpty) {
        if (mounted) {
          setState(() {
            _providerLoading = false;
            _providerError = 'No base URL found for ${provider['name'] ?? providerId}';
          });
        }
        return;
      }

      if (modelName.isEmpty) {
        if (mounted) {
          setState(() {
            _providerLoading = false;
            _providerError = 'No model name found for ${provider['name'] ?? providerId}';
          });
        }
        return;
      }

      if (mounted) {
        setState(() {
          _providers = allProviders ?? _providers;
          _provider = provider;
          _apiKey = apiKey ?? '';
          _modelName = modelName;
          _providerLoading = false;
          _providerError = null;
        });
      }
      await AppStorage.saveSelectedProviderId(providerId);
    } catch (e) {
      if (mounted) {
        setState(() {
          _providerLoading = false;
          _providerError = 'Failed to load provider: $e';
        });
      }
    }
  }

  Future<void> _onProviderChanged(String providerId) async {
    final provider = _providers.firstWhere(
      (item) => item['id'] == providerId,
      orElse: () => _providers.first,
    );
    setState(() {
      _providerLoading = true;
      _providerError = null;
    });
    await _applyProvider(provider);
  }

  Future<void> _loadMode() async {
    final mode = await AppStorage.getSelectedMode();
    if (mounted && _kSystemPrompts.containsKey(mode)) {
      setState(() => _currentMode = mode);
    }
  }

  Future<void> _loadMessages() async {
    try {
      final saved = await AppStorage.loadChatMessages();
      if (mounted && saved.isNotEmpty) {
        setState(() {
          _messages.addAll(saved.map((m) => _ChatMessage.fromJson(m)));
        });
        _scrollToBottom();
      }
    } catch (_) {
      // Corrupted data — start fresh
    }
  }

  Future<void> _saveMessages() async {
    final data = _messages
        .where((m) => !m.isStreaming || m.content.isNotEmpty)
        .map((m) => m.toJson())
        .toList();
    await AppStorage.saveChatMessages(data);
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _activeStream?.cancel();
    _httpClient?.close(force: true);
    super.dispose();
  }

  // ─────────────────────────────────────────────────
  //  Send Message & Stream Response
  // ─────────────────────────────────────────────────

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isGenerating) return;
    if (_provider == null || _modelName == null || _modelName!.isEmpty) return;

    // Add user message
    final userMsg = _ChatMessage(
      role: 'user',
      content: text,
      timestamp: DateTime.now(),
    );

    setState(() {
      _messages.add(userMsg);
      _controller.clear();
      _isGenerating = true;
    });
    _scrollToBottom();
    await _saveMessages();

    // Add placeholder assistant message
    final assistantMsg = _ChatMessage(
      role: 'assistant',
      content: '',
      timestamp: DateTime.now(),
      isStreaming: true,
    );
    setState(() => _messages.add(assistantMsg));
    _scrollToBottom();

    try {
      await _streamCompletion(assistantMsg);
    } catch (e) {
      setState(() {
        assistantMsg.content = _formatError(e);
        assistantMsg.isStreaming = false;
        _isGenerating = false;
      });
    }
    await _saveMessages();
  }

  Future<void> _streamCompletion(_ChatMessage assistantMsg) async {
    final endpoint = _chatCompletionsEndpoint(_provider!);

    // Build messages array with system prompt
    final apiMessages = <Map<String, String>>[
      {'role': 'system', 'content': _kSystemPrompts[_currentMode] ?? _kSystemPrompts['ask']!},
      ..._messages
          .where((m) => !m.isStreaming && m.content.isNotEmpty)
          .map((m) => m.toApiMessage()),
    ];

    final body = jsonEncode({
      'model': _modelName,
      'messages': apiMessages,
      'stream': true,
    });

    final uri = Uri.parse(endpoint);
    final request = await _httpClient!.openUrl('POST', uri);
    if (_apiKey != null && _apiKey!.trim().isNotEmpty) {
      request.headers.set('Authorization', 'Bearer ${_apiKey!.trim()}');
    }
    request.headers.set('Content-Type', 'application/json');
    request.headers.set('Accept', 'text/event-stream');
    final customHeaders = _provider!['customHeaders'];
    if (customHeaders is Map) {
      for (final entry in customHeaders.entries) {
        request.headers.set(entry.key.toString(), entry.value.toString());
      }
    }
    request.add(utf8.encode(body));

    final response = await request.close();

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final errorBody = await response.transform(utf8.decoder).join();
      String errorMsg;
      try {
        final errorJson = jsonDecode(errorBody) as Map<String, dynamic>;
        errorMsg = (errorJson['error'] is Map)
            ? (errorJson['error']['message'] ?? errorBody).toString()
            : errorBody;
      } catch (_) {
        errorMsg = errorBody;
      }
      throw HttpException('API error ${response.statusCode}: $errorMsg');
    }

    // Parse SSE stream. Chunks can split in the middle of a JSON line.
    final completer = Completer<void>();
    String buffer = '';

    void consumeLine(String line) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || !trimmed.startsWith('data:')) return;

      final data = trimmed.substring(5).trim();
      if (data.isEmpty || data == '[DONE]') return;

      try {
        final json = jsonDecode(data) as Map<String, dynamic>;
        final choices = json['choices'] as List<dynamic>?;
        if (choices == null || choices.isEmpty) return;

        final choice = choices[0] as Map<String, dynamic>;
        final delta = choice['delta'] as Map<String, dynamic>?;
        final message = choice['message'] as Map<String, dynamic>?;
        final token = (delta?['content'] ??
                delta?['reasoning_content'] ??
                message?['content'] ??
                choice['text'])
            ?.toString();
        if (token == null || token.isEmpty || !mounted) return;

        setState(() {
          assistantMsg.content += token;
        });
        _scrollToBottom();
      } catch (_) {
        // Skip malformed JSON chunks.
      }
    }

    _activeStream = response.transform(utf8.decoder).listen(
      (chunk) {
        buffer += chunk;
        final lines = buffer.split('\n');
        // Keep the last potentially incomplete line in the buffer.
        buffer = lines.removeLast();

        for (final line in lines) consumeLine(line);
      },
      onDone: () {
        if (buffer.trim().isNotEmpty) consumeLine(buffer);
        if (mounted) {
          setState(() {
            assistantMsg.isStreaming = false;
            _isGenerating = false;
          });
        }
        _activeStream = null;
        if (!completer.isCompleted) completer.complete();
      },
      onError: (Object error) {
        if (mounted) {
          setState(() {
            if (assistantMsg.content.isEmpty) {
              assistantMsg.content = _formatError(error);
            }
            assistantMsg.isStreaming = false;
            _isGenerating = false;
          });
        }
        _activeStream = null;
        if (!completer.isCompleted) completer.complete();
      },
      cancelOnError: true,
    );

    return completer.future;
  }

  String _chatCompletionsEndpoint(Map<String, dynamic> provider) {
    final baseUrl = (provider['baseUrl'] as String? ?? '')
        .trim()
        .replaceAll(RegExp(r'/+$'), '');
    if (baseUrl.endsWith('/chat/completions')) return baseUrl;
    return '$baseUrl/chat/completions';
  }

  String _formatError(Object error) {
    final msg = error.toString();
    if (msg.contains('SocketException') || msg.contains('Connection refused')) {
      return '⚠️ **Connection failed**\n\nCould not reach the API server. Please check:\n- Your internet connection\n- The provider\'s base URL is correct\n- The API server is running';
    }
    if (msg.contains('HandshakeException') || msg.contains('CERTIFICATE')) {
      return '⚠️ **SSL/TLS Error**\n\nCould not establish a secure connection. The server\'s certificate may be invalid.';
    }
    if (msg.contains('401') || msg.contains('Unauthorized')) {
      return '⚠️ **Authentication failed**\n\nYour API key appears to be invalid or expired. Go to **Models** settings to update it.';
    }
    if (msg.contains('429') || msg.contains('rate limit')) {
      return '⚠️ **Rate limited**\n\nToo many requests. Please wait a moment and try again.';
    }
    if (msg.contains('API error')) {
      return '⚠️ **API Error**\n\n${msg.replaceFirst('HttpException: ', '')}';
    }
    return '⚠️ **Error**\n\n$msg';
  }

  void _stopGeneration() {
    _activeStream?.cancel();
    _activeStream = null;
    setState(() {
      _isGenerating = false;
      if (_messages.isNotEmpty && _messages.last.isStreaming) {
        _messages.last.isStreaming = false;
        if (_messages.last.content.isEmpty) {
          _messages.last.content = '*(Generation stopped)*';
        }
      }
    });
    _saveMessages();
  }

  void _clearChat() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.backgroundSecondary,
        title: const Text('Clear Chat'),
        content: const Text('Delete all messages in this conversation?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() => _messages.clear());
              _saveMessages();
            },
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }

  void _onModeChanged(String mode) {
    setState(() => _currentMode = mode);
    AppStorage.saveSelectedMode(mode);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ─────────────────────────────────────────────────
  //  Build
  // ─────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: ForgeAppBar(
        title: 'Chat',
        currentMode: _currentMode,
        currentModel: _modelName,
        showBackButton: true,
        actions: [
          if (_messages.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded, size: 20),
              onPressed: _clearChat,
              tooltip: 'Clear chat',
            ),
        ],
      ),
      body: _providerLoading
          ? const Center(child: CircularProgressIndicator())
          : _providerError != null
              ? _buildNoProviderState(context)
              : Column(
                  children: [
                    _buildModeChips(context),
                    Expanded(
                      child: _messages.isEmpty
                          ? _buildEmptyState(context)
                          : _buildMessageList(context),
                    ),
                    _buildInputBar(context),
                  ],
                ),
    );
  }

  // ─────────────────────────────────────────────────
  //  No Provider State
  // ─────────────────────────────────────────────────

  Widget _buildNoProviderState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: GlassCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.cloud_off_rounded,
                  size: 48,
                  color: AppColors.warning,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'No API Configured',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                _providerError ?? 'Add an API provider to start chatting.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => Navigator.pushNamed(context, '/models'),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Configure Provider'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accentBlue,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────
  //  Mode Chip Bar
  // ─────────────────────────────────────────────────

  Widget _buildModeChips(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.backgroundSecondary,
        border: Border(bottom: BorderSide(color: AppColors.borderSubtle)),
      ),
      child: Column(
        children: [
          if (_provider != null) _buildProviderSelector(context),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: _kModes.map((mode) {
                final isSelected = mode == _currentMode;
                final color = AppColors.modeColor(mode);
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: FilterChip(
                    selected: isSelected,
                    label: Text(
                      mode[0].toUpperCase() + mode.substring(1),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight:
                            isSelected ? FontWeight.w700 : FontWeight.w500,
                        color: isSelected ? color : AppColors.textSecondary,
                      ),
                    ),
                    avatar: Icon(
                      _kModeIcons[mode] ?? Icons.circle,
                      size: 16,
                      color: isSelected ? color : AppColors.textTertiary,
                    ),
                    selectedColor: color.withValues(alpha: 0.15),
                    backgroundColor: AppColors.backgroundTertiary,
                    side: BorderSide(
                      color: isSelected
                          ? color.withValues(alpha: 0.4)
                          : AppColors.borderSubtle,
                      width: isSelected ? 1.2 : 0.5,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    showCheckmark: false,
                    onSelected: (_) => _onModeChanged(mode),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProviderSelector(BuildContext context) {
    final providerId = _provider?['id']?.toString();
    final providerName = _provider?['name']?.toString() ?? 'Provider';
    final modelName = _modelName ?? '';

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: PopupMenuButton<String>(
        initialValue: providerId,
        onSelected: _onProviderChanged,
        itemBuilder: (_) => _providers.map((provider) {
          final name = provider['name']?.toString() ?? 'Provider';
          final model = AppStorage.providerModelName(provider);
          return PopupMenuItem<String>(
            value: provider['id']?.toString(),
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.cloud_outlined, size: 18),
              title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                model,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          );
        }).toList(),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: AppColors.backgroundTertiary,
            border: Border.all(color: AppColors.borderSubtle),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.cloud_outlined,
                size: 18,
                color: AppColors.accentTeal,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$providerName  /  $modelName',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Icon(Icons.expand_more_rounded, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────
  //  Empty State
  // ─────────────────────────────────────────────────

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: AppColors.cardGradient,
              shape: BoxShape.circle,
            ),
            child: Icon(
              _kModeIcons[_currentMode] ?? Icons.chat_bubble_outline_rounded,
              size: 48,
              color: AppColors.modeColor(_currentMode),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Start a conversation',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 48),
            child: Text(
              'Using $_modelName in ${_currentMode.toUpperCase()} mode',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────
  //  Message List
  // ─────────────────────────────────────────────────

  Widget _buildMessageList(BuildContext context) {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: _messages.length,
      itemBuilder: (_, i) => _MessageBubble(
        message: _messages[i],
        modelName: _modelName,
      ),
    );
  }

  // ─────────────────────────────────────────────────
  //  Input Bar
  // ─────────────────────────────────────────────────

  Widget _buildInputBar(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        top: 12,
        bottom: MediaQuery.paddingOf(context).bottom + 12,
      ),
      decoration: BoxDecoration(
        color: AppColors.backgroundSecondary,
        border: Border(top: BorderSide(color: AppColors.borderSubtle)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              maxLines: 5,
              minLines: 1,
              enabled: !_isGenerating,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _sendMessage(),
              decoration: InputDecoration(
                hintText: _isGenerating
                    ? 'Generating response...'
                    : 'Message ($_currentMode mode)...',
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _isGenerating
              ? IconButton.filled(
                  onPressed: _stopGeneration,
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.error.withValues(alpha: 0.2),
                  ),
                  icon: const Icon(
                    Icons.stop_rounded,
                    size: 20,
                    color: AppColors.error,
                  ),
                )
              : IconButton.filled(
                  onPressed: _sendMessage,
                  icon: const Icon(Icons.send_rounded, size: 18),
                ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────
//  Message Bubble Widget
// ─────────────────────────────────────────────────

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    this.modelName,
  });

  final _ChatMessage message;
  final String? modelName;

  bool get _isUser => message.role == 'user';

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment:
            _isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!_isUser) ...[
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                gradient: AppColors.accentGlow,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.auto_awesome_rounded,
                size: 16,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 10),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment:
                  _isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                // Agent label + model
                if (!_isUser)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Assistant',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.accentBlue,
                          ),
                        ),
                        if (modelName != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.accentPurple.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              modelName!,
                              style: const TextStyle(
                                fontSize: 10,
                                color: AppColors.accentPurple,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                // Message body
                Container(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.sizeOf(context).width * 0.78,
                  ),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _isUser
                        ? AppColors.accentBlue.withValues(alpha: 0.15)
                        : AppColors.backgroundSecondary,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: Radius.circular(_isUser ? 16 : 4),
                      bottomRight: Radius.circular(_isUser ? 4 : 16),
                    ),
                    border: Border.all(
                      color: _isUser
                          ? AppColors.accentBlue.withValues(alpha: 0.2)
                          : AppColors.borderSubtle,
                      width: 0.5,
                    ),
                  ),
                  child: message.isStreaming && message.content.isEmpty
                      ? _buildTypingIndicator()
                      : _isUser
                          ? SelectableText(
                              message.content,
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: AppColors.textPrimary,
                                    height: 1.5,
                                  ),
                            )
                          : _buildMarkdownBody(context),
                ),

                // Streaming indicator
                if (message.isStreaming && message.content.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: AppColors.accentBlue,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Text(
                          'Generating...',
                          style: TextStyle(
                            fontSize: 10,
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),

                // Timestamp
                if (!message.isStreaming)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      _formatTime(message.timestamp),
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (_isUser) ...[
            const SizedBox(width: 10),
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppColors.accentBlue.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.person_rounded,
                size: 16,
                color: AppColors.accentBlue,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) {
        return Padding(
          padding: EdgeInsets.only(left: i > 0 ? 4 : 0),
          child: _PulsingDot(delay: Duration(milliseconds: i * 200)),
        );
      }),
    );
  }

  Widget _buildMarkdownBody(BuildContext context) {
    return MarkdownBody(
      data: message.content,
      selectable: true,
      styleSheet: MarkdownStyleSheet.fromTheme(
        Theme.of(context),
      ).copyWith(
        p: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppColors.textPrimary,
              height: 1.5,
            ),
        code: GoogleFonts.jetBrainsMono(
          fontSize: 13,
          color: AppColors.accentBlue,
          backgroundColor: AppColors.backgroundPrimary,
        ),
        codeblockDecoration: BoxDecoration(
          color: AppColors.backgroundPrimary,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.borderSubtle),
        ),
        codeblockPadding: const EdgeInsets.all(12),
        blockquoteDecoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: AppColors.accentBlue.withValues(alpha: 0.5),
              width: 3,
            ),
          ),
        ),
        blockquotePadding: const EdgeInsets.only(left: 12),
        h1: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
        h2: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
        h3: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
        listBullet: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
            ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

// ─────────────────────────────────────────────────
//  Pulsing Dot (typing indicator)
// ─────────────────────────────────────────────────

class _PulsingDot extends StatefulWidget {
  const _PulsingDot({this.delay = Duration.zero});
  final Duration delay;

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _animation = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
    Future.delayed(widget.delay, () {
      if (mounted) _ctrl.repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (_, __) => Opacity(
        opacity: _animation.value,
        child: Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: AppColors.accentBlue,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}
