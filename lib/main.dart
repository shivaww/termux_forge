import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Color(0xFFF7F2E8),
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );
  runApp(const ForgeChatApp());
}

class ForgeChatApp extends StatelessWidget {
  const ForgeChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    final baseText = GoogleFonts.manropeTextTheme();
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Forge Chat',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF7B4E2E),
          brightness: Brightness.light,
          surface: const Color(0xFFFFFBF2),
        ),
        scaffoldBackgroundColor: const Color(0xFFF7F2E8),
        textTheme: baseText,
      ),
      home: const ChatHomePage(),
    );
  }
}

class ChatHomePage extends StatefulWidget {
  const ChatHomePage({super.key});

  @override
  State<ChatHomePage> createState() => _ChatHomePageState();
}

class _ChatHomePageState extends State<ChatHomePage> {
  static const _secureStorage = FlutterSecureStorage();
  static const _settingsKey = 'provider_settings_v1';
  static const _selectedProviderKey = 'selected_provider_id';

  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final _chatClient = ChatClient();

  SharedPreferences? _prefs;
  Map<String, ProviderSettings> _settings = {};
  final Map<String, List<String>> _modelCache = {};
  var _selectedProviderId = providerCatalog.first.id;
  var _isSending = false;
  var _isFetchingModels = false;

  List<ChatSession> _sessions = [];
  String? _activeSessionId;

  List<ChatMessage> get _messages {
    if (_sessions.isEmpty) {
      _initDefaultSession();
    }
    final active = _sessions.firstWhere(
      (s) => s.id == _activeSessionId,
      orElse: () => _sessions.first,
    );
    return active.messages;
  }

  void _initDefaultSession() {
    final nextId = DateTime.now().millisecondsSinceEpoch.toString();
    final newSession = ChatSession(
      id: nextId,
      title: 'Welcome Chat',
      messages: [
        const ChatMessage(
          role: MessageRole.assistant,
          text:
              'Select a provider, add its API key, fetch or type a model, then start chatting.',
        ),
      ],
      providerId: _selectedProviderId,
      model: _activeModel,
    );
    _sessions = [newSession];
    _activeSessionId = newSession.id;
  }

  Future<void> _loadSessions() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('chat_sessions_v1');
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final List decoded = jsonDecode(raw);
        setState(() {
          _sessions = decoded.map((s) => ChatSession.fromJson(s)).toList();
          _activeSessionId = prefs.getString('active_session_id_v1') ??
              (_sessions.isNotEmpty ? _sessions.first.id : 'default');
        });
      } catch (_) {
        setState(() {
          _initDefaultSession();
        });
      }
    } else {
      setState(() {
        _initDefaultSession();
      });
    }
  }

  Future<void> _saveSessions() async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    final serialized = _sessions.map((s) => s.toJson()).toList();
    await prefs.setString('chat_sessions_v1', jsonEncode(serialized));
    if (_activeSessionId != null) {
      await prefs.setString('active_session_id_v1', _activeSessionId!);
    }
  }

  void _switchSession(String sessionId) {
    setState(() {
      _activeSessionId = sessionId;
      final session = _sessions.firstWhere((s) => s.id == sessionId);
      _selectedProviderId = session.providerId;
      final settings = _settings[_selectedProviderId] ??
          ProviderSettings.defaults(_provider);
      if (session.model.isNotEmpty) {
        _settings[_selectedProviderId] =
            settings.copyWith(model: session.model);
      }
    });
    _saveSettings();
    _saveSessions();
    if (MediaQuery.sizeOf(context).width < 840 && mounted) {
      Navigator.of(context).maybePop();
    }
  }

  void _deleteSession(String sessionId) {
    if (_sessions.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot delete the last remaining chat.')),
      );
      return;
    }
    setState(() {
      _sessions.removeWhere((s) => s.id == sessionId);
      if (_activeSessionId == sessionId) {
        _activeSessionId = _sessions.first.id;
      }
    });
    _saveSessions();
  }

  ProviderDefinition get _provider =>
      providerCatalog.firstWhere((item) => item.id == _selectedProviderId);

  ProviderSettings get _activeSettings =>
      _settings[_selectedProviderId] ?? ProviderSettings.defaults(_provider);

  String get _activeModel {
    final settings = _activeSettings;
    if (settings.model.trim().isNotEmpty) return settings.model.trim();
    return _provider.models.first;
  }

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_settingsKey);
    final selected = prefs.getString(_selectedProviderKey);
    final nextSettings = <String, ProviderSettings>{};

    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        for (final entry in decoded.entries) {
          nextSettings[entry.key] = ProviderSettings.fromJson(
            Map<String, dynamic>.from(entry.value as Map),
          );
        }
      } catch (_) {
        nextSettings.clear();
      }
    }

    for (final provider in providerCatalog) {
      final key = await _secureStorage.read(key: _keyStorageName(provider.id));
      final current = nextSettings[provider.id] ??
          ProviderSettings.defaults(provider);
      final normalized = current.maxTokens < 1
          ? current.copyWith(maxTokens: provider.defaultMaxTokens)
          : current;
      nextSettings[provider.id] = normalized.copyWith(apiKey: key ?? '');
    }

    if (!mounted) return;
    setState(() {
      _prefs = prefs;
      _settings = nextSettings;
      if (selected != null &&
          providerCatalog.any((provider) => provider.id == selected)) {
        _selectedProviderId = selected;
      }
    });

    await _loadSessions();
  }

  Future<void> _saveSettings() async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    final metadata = <String, Map<String, dynamic>>{};
    for (final entry in _settings.entries) {
      metadata[entry.key] = entry.value.copyWith(apiKey: '').toJson();
      final key = entry.value.apiKey.trim();
      if (key.isEmpty) {
        await _secureStorage.delete(key: _keyStorageName(entry.key));
      } else {
        await _secureStorage.write(key: _keyStorageName(entry.key), value: key);
      }
    }
    await prefs.setString(_settingsKey, jsonEncode(metadata));
    await prefs.setString(_selectedProviderKey, _selectedProviderId);
  }

  Future<void> _selectProvider(String providerId) async {
    setState(() {
      _selectedProviderId = providerId;
      final sessionIndex = _sessions.indexWhere((s) => s.id == _activeSessionId);
      if (sessionIndex != -1) {
        _sessions[sessionIndex] = _sessions[sessionIndex].copyWith(providerId: providerId);
      }
    });
    await _saveSettings();
    await _saveSessions();
    if (MediaQuery.sizeOf(context).width < 840 && mounted) {
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _openProviderSheet([String? providerId]) async {
    final provider = providerCatalog.firstWhere(
      (item) => item.id == (providerId ?? _selectedProviderId),
    );
    final current = _settings[provider.id] ?? ProviderSettings.defaults(provider);
    final result = await showModalBottomSheet<ProviderSettings>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return ProviderSettingsSheet(
          provider: provider,
          settings: current,
          cachedModels: _modelCache[provider.id] ?? provider.models,
          onFetchModels: () => _fetchModels(provider),
        );
      },
    );

    if (result == null) return;
    setState(() {
      _settings = {
        ..._settings,
        provider.id: result,
      };
      _selectedProviderId = provider.id;
    });
    await _saveSettings();
  }

  Future<List<String>> _fetchModels(ProviderDefinition provider) async {
    final settings = _settings[provider.id] ?? ProviderSettings.defaults(provider);
    setState(() => _isFetchingModels = true);
    try {
      final models = await _chatClient.fetchModels(provider, settings);
      final uniqueModels = {
        ...models,
        ...provider.models,
      }.where((model) => model.trim().isNotEmpty).toList()
        ..sort();
      setState(() => _modelCache[provider.id] = uniqueModels);
      return uniqueModels;
    } finally {
      if (mounted) setState(() => _isFetchingModels = false);
    }
  }

  Future<void> _openModelSheet() async {
    final provider = _provider;
    final settings = _activeSettings;
    final models = _modelCache[provider.id] ?? provider.models;
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return ModelPickerSheet(
          provider: provider,
          models: models,
          selectedModel: _activeModel,
          isFetching: _isFetchingModels,
          onFetchModels: () => _fetchModels(provider),
        );
      },
    );

    if (selected == null || selected.trim().isEmpty) return;
    setState(() {
      _settings = {
        ..._settings,
        provider.id: settings.copyWith(model: selected.trim()),
      };
    });
    await _saveSettings();
  }

  Future<void> _sendMessage() async {
    final prompt = _messageController.text.trim();
    if (prompt.isEmpty || _isSending) return;

    final provider = _provider;
    final settings = _activeSettings;
    if (provider.requiresKey && settings.apiKey.trim().isEmpty) {
      await _openProviderSheet(provider.id);
      return;
    }

    _messageController.clear();
    final userMessage = ChatMessage(role: MessageRole.user, text: prompt);
    
    final sessionIndex = _sessions.indexWhere((s) => s.id == _activeSessionId);
    if (sessionIndex != -1) {
      final session = _sessions[sessionIndex];
      String updatedTitle = session.title;
      if (session.title == 'Welcome Chat' || session.title == 'New Chat') {
        updatedTitle = prompt.length > 25 ? '${prompt.substring(0, 25)}...' : prompt;
      }
      setState(() {
        final updatedMessages = List<ChatMessage>.from(session.messages)..add(userMessage);
        _sessions[sessionIndex] = session.copyWith(
          messages: updatedMessages,
          title: updatedTitle,
          providerId: _selectedProviderId,
          model: _activeModel,
        );
      });
    }

    _scrollToBottom();

    final assistantMessageIndex = _messages.length;
    setState(() {
      _messages.add(const ChatMessage(role: MessageRole.assistant, text: ''));
      _isSending = true;
    });
    _scrollToBottom();

    try {
      final stream = _chatClient.sendChatStream(
        provider: provider,
        settings: settings,
        model: _activeModel,
        messages: _messages
            .take(assistantMessageIndex)
            .where((message) => message.role != MessageRole.system)
            .toList(),
      );

      var fullText = '';
      await for (final chunk in stream) {
        if (!mounted) return;
        fullText += chunk;
        setState(() {
          _messages[assistantMessageIndex] = ChatMessage(
            role: MessageRole.assistant,
            text: fullText,
          );
        });
        _scrollToBottom();
      }
      await _saveSessions();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        final currentText = _messages[assistantMessageIndex].text;
        _messages[assistantMessageIndex] = ChatMessage(
          role: MessageRole.assistant,
          text: currentText.isNotEmpty
              ? '$currentText\n\n[Error: $error]'
              : 'Request failed: $error',
          isError: true,
        );
      });
      await _saveSessions();
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
        _scrollToBottom();
      }
    }
  }

  void _newChat() {
    final newId = DateTime.now().millisecondsSinceEpoch.toString();
    final newSession = ChatSession(
      id: newId,
      title: 'New Chat',
      messages: [
        const ChatMessage(
          role: MessageRole.assistant,
          text: 'New chat ready. Choose any configured provider and model.',
        ),
      ],
      providerId: _selectedProviderId,
      model: _activeModel,
    );
    setState(() {
      _sessions.insert(0, newSession);
      _activeSessionId = newId;
    });
    _saveSessions();
  }

  Future<void> _openPlusBottomSheet() async {
    final provider = _provider;
    final settings = _activeSettings;
    final models = _modelCache[provider.id] ?? provider.models;
    
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return MediaAndModelSheet(
          provider: provider,
          settings: settings,
          cachedModels: models,
          onProviderChanged: (newProviderId) async {
            setState(() {
              _selectedProviderId = newProviderId;
            });
            await _saveSettings();
            final nextProvider = providerCatalog.firstWhere((p) => p.id == newProviderId);
            final nextSettings = _settings[newProviderId] ?? ProviderSettings.defaults(nextProvider);
            final nextModel = nextSettings.model.isNotEmpty ? nextSettings.model : nextProvider.models.first;
            setState(() {
              _settings[newProviderId] = nextSettings.copyWith(model: nextModel);
            });
          },
          onModelChanged: (newModel) async {
            setState(() {
              _settings[provider.id] = settings.copyWith(model: newModel);
            });
            await _saveSettings();
          },
          onMaxTokensChanged: (newMaxTokens) async {
            setState(() {
              _settings[provider.id] = settings.copyWith(maxTokens: newMaxTokens);
            });
            await _saveSettings();
          },
          onFetchModels: () => _fetchModels(provider),
          onConfigureKey: () {
            _openProviderSheet(provider.id);
          },
        );
      },
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 840;
    
    final chatHistoryPanel = ChatHistoryPanel(
      sessions: _sessions,
      activeSessionId: _activeSessionId,
      onSessionTap: _switchSession,
      onSessionDelete: _deleteSession,
      onNewChat: _newChat,
    );

    return Scaffold(
      drawer: wide ? null : Drawer(width: 330, child: chatHistoryPanel),
      body: SafeArea(
        child: Row(
          children: [
            if (wide)
              SizedBox(
                width: 330,
                child: chatHistoryPanel,
              ),
            Expanded(
              child: ChatSurface(
                provider: _provider,
                settings: _activeSettings,
                model: _activeModel,
                messages: _messages,
                messageController: _messageController,
                scrollController: _scrollController,
                isSending: _isSending,
                onOpenProvider: () => _openProviderSheet(_selectedProviderId),
                onOpenModel: _openModelSheet,
                onSend: _sendMessage,
                onPlusPressed: _openPlusBottomSheet,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _keyStorageName(String providerId) => 'provider_api_key_$providerId';
}

class ChatHistoryPanel extends StatelessWidget {
  const ChatHistoryPanel({
    required this.sessions,
    required this.activeSessionId,
    required this.onSessionTap,
    required this.onSessionDelete,
    required this.onNewChat,
    super.key,
  });

  final List<ChatSession> sessions;
  final String? activeSessionId;
  final ValueChanged<String> onSessionTap;
  final ValueChanged<String> onSessionDelete;
  final VoidCallback onNewChat;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFEFE6D6),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
            child: Row(
              children: [
                const AppMark(),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Forge Chat',
                    style: GoogleFonts.notoSerif(
                      fontSize: 25,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF2D241C),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'New chat',
                  onPressed: onNewChat,
                  icon: const Icon(Icons.add_comment_outlined),
                ),
              ],
            ),
          ),
          const Divider(color: Color(0xFFDCCBB8), height: 1),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 18),
              itemCount: sessions.length,
              itemBuilder: (context, index) {
                final session = sessions[index];
                final selected = session.id == activeSessionId;
                final messageCount = session.messages.length;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  margin: const EdgeInsets.symmetric(vertical: 3),
                  decoration: BoxDecoration(
                    color: selected ? const Color(0xFFFFF8EA) : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: selected ? const Color(0xFFD8B98D) : Colors.transparent,
                    ),
                  ),
                  child: ListTile(
                    dense: true,
                    selected: selected,
                    leading: const Icon(Icons.chat_bubble_outline, size: 20),
                    title: Text(
                      session.title,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                        color: const Color(0xFF33291F),
                      ),
                    ),
                    subtitle: Text(
                      '$messageCount message${messageCount == 1 ? '' : 's'}',
                      style: const TextStyle(color: Color(0xFF6C5946), fontSize: 11),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, size: 18),
                      color: const Color(0xFF9B4D39),
                      onPressed: () => onSessionDelete(session.id),
                    ),
                    onTap: () => onSessionTap(session.id),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class ChatSurface extends StatelessWidget {
  const ChatSurface({
    required this.provider,
    required this.settings,
    required this.model,
    required this.messages,
    required this.messageController,
    required this.scrollController,
    required this.isSending,
    required this.onOpenProvider,
    required this.onOpenModel,
    required this.onSend,
    required this.onPlusPressed,
    super.key,
  });

  final ProviderDefinition provider;
  final ProviderSettings settings;
  final String model;
  final List<ChatMessage> messages;
  final TextEditingController messageController;
  final ScrollController scrollController;
  final bool isSending;
  final VoidCallback onOpenProvider;
  final VoidCallback onOpenModel;
  final VoidCallback onSend;
  final VoidCallback onPlusPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFFBF6EC),
            Color(0xFFF5EFE4),
            Color(0xFFEFE5D5),
          ],
        ),
      ),
      child: Column(
        children: [
          ChatHeader(
            provider: provider,
            settings: settings,
            model: model,
            onOpenProvider: onOpenProvider,
            onOpenModel: onOpenModel,
          ),
          Expanded(
            child: ListView.builder(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
              itemCount: messages.length + (isSending ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == messages.length) {
                  return const TypingBubble();
                }
                return MessageBubble(
                  message: messages[index],
                  index: index,
                );
              },
            ),
          ),
          Composer(
            controller: messageController,
            isSending: isSending,
            onSend: onSend,
            onPlusPressed: onPlusPressed,
          ),
        ],
      ),
    );
  }
}

class ChatHeader extends StatelessWidget {
  const ChatHeader({
    required this.provider,
    required this.settings,
    required this.model,
    required this.onOpenProvider,
    required this.onOpenModel,
    super.key,
  });

  final ProviderDefinition provider;
  final ProviderSettings settings;
  final String model;
  final VoidCallback onOpenProvider;
  final VoidCallback onOpenModel;

  @override
  Widget build(BuildContext context) {
    final hasKey = settings.apiKey.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      child: Row(
        children: [
          Builder(
            builder: (context) {
              final hasDrawer = Scaffold.hasDrawer(context);
              if (!hasDrawer) return const SizedBox.shrink();
              return IconButton(
                tooltip: 'Chats',
                onPressed: () => Scaffold.of(context).openDrawer(),
                icon: const Icon(Icons.menu),
              );
            },
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onOpenProvider,
            child: Tooltip(
              message: '${provider.name} settings',
              child: ProviderAvatar(label: provider.shortName, small: true),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: onOpenModel,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFCF6),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE7D8C4)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.tune, size: 16, color: Color(0xFF7B4E2E)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              model,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF2D241C),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  hasKey || !provider.requiresKey
                      ? Icons.lock_outline
                      : Icons.lock_open_outlined,
                  size: 18,
                  color: hasKey || !provider.requiresKey
                      ? const Color(0xFF36764D)
                      : const Color(0xFF9B4D39),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String formatMathText(String text) {
  var formatted = text;
  
  // Replace double dollar sign math blocks with markdown code block
  final blockMathRegex = RegExp(r'\$\$(.*?)\$\$', dotAll: true);
  formatted = formatted.replaceAllMapped(blockMathRegex, (match) {
    final eq = match.group(1)?.trim() ?? '';
    return '\n```math\n$eq\n```\n';
  });

  // Replace \[ ... \] with code blocks
  final bracketMathRegex = RegExp(r'\\\[(.*?)\\\]', dotAll: true);
  formatted = formatted.replaceAllMapped(bracketMathRegex, (match) {
    final eq = match.group(1)?.trim() ?? '';
    return '\n```math\n$eq\n```\n';
  });

  // Replace \( ... \) with inline code blocks
  final parenMathRegex = RegExp(r'\\\((.*?)\\\)', dotAll: true);
  formatted = formatted.replaceAllMapped(parenMathRegex, (match) {
    final eq = match.group(1)?.trim() ?? '';
    return ' `$eq` ';
  });

  return formatted;
}

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    required this.message,
    required this.index,
    super.key,
  });

  final ChatMessage message;
  final int index;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == MessageRole.user;
    final align = isUser ? Alignment.centerRight : Alignment.centerLeft;
    final bubbleColor = message.isError
        ? const Color(0xFFFFE7DD)
        : isUser
            ? const Color(0xFF382E25)
            : const Color(0xFFFFFCF6);
    final textColor = isUser ? Colors.white : const Color(0xFF2D241C);

    return TweenAnimationBuilder<double>(
      duration: Duration(milliseconds: 240 + (index % 5) * 24),
      curve: Curves.easeOutCubic,
      tween: Tween(begin: 0, end: 1),
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, (1 - value) * 12),
            child: child,
          ),
        );
      },
      child: Align(
        alignment: align,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 7),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            decoration: BoxDecoration(
              color: bubbleColor,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(18),
                topRight: const Radius.circular(18),
                bottomLeft: Radius.circular(isUser ? 18 : 6),
                bottomRight: Radius.circular(isUser ? 6 : 18),
              ),
              border: Border.all(
                color: isUser ? const Color(0xFF382E25) : const Color(0xFFE7D8C4),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: isUser
                ? SelectableText(
                    message.text,
                    style: TextStyle(
                      height: 1.45,
                      color: textColor,
                      fontSize: 15.5,
                      fontWeight: FontWeight.w600,
                    ),
                  )
                : MarkdownBody(
                    data: formatMathText(message.text),
                    selectable: true,
                    styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                      p: TextStyle(
                        height: 1.45,
                        color: textColor,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w500,
                      ),
                      code: GoogleFonts.manrope(
                        fontSize: 13,
                        color: const Color(0xFF7B4E2E),
                        backgroundColor: const Color(0xFFF7F2E8),
                      ),
                      codeblockDecoration: BoxDecoration(
                        color: const Color(0xFFF7F2E8),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFDCCBB8)),
                      ),
                      tableBorder: TableBorder.all(
                        color: const Color(0xFFDCCBB8),
                        width: 1,
                      ),
                      tableBody: TextStyle(
                        color: textColor,
                        fontSize: 14,
                      ),
                      tableHead: TextStyle(
                        color: textColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                      h1: TextStyle(
                        color: textColor,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                      h2: TextStyle(
                        color: textColor,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      h3: TextStyle(
                        color: textColor,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class TypingBubble extends StatelessWidget {
  const TypingBubble({super.key});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 7),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFCF6),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE7D8C4)),
        ),
        child: const SizedBox(
          width: 42,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              PulseDot(delay: 0),
              PulseDot(delay: 110),
              PulseDot(delay: 220),
            ],
          ),
        ),
      ),
    );
  }
}

class PulseDot extends StatefulWidget {
  const PulseDot({required this.delay, super.key});

  final int delay;

  @override
  State<PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 780),
    );
    Future<void>.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _controller.repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.32, end: 1).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
      ),
      child: const CircleAvatar(
        radius: 4,
        backgroundColor: Color(0xFF8A6A4F),
      ),
    );
  }
}

class Composer extends StatelessWidget {
  const Composer({
    required this.controller,
    required this.isSending,
    required this.onSend,
    required this.onPlusPressed,
    super.key,
  });

  final TextEditingController controller;
  final bool isSending;
  final VoidCallback onSend;
  final VoidCallback onPlusPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 920),
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFCF6),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFDCCBB8)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 6,
                textInputAction: TextInputAction.newline,
                decoration: const InputDecoration(
                  hintText: 'Message any provider...',
                  border: InputBorder.none,
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onPlusPressed,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFFFF8EA),
                  border: Border.all(color: const Color(0xFFD8B98D), width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF7B4E2E).withValues(alpha: 0.1),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.add,
                  color: Color(0xFF7B4E2E),
                  size: 20,
                ),
              ),
            ),
            const SizedBox(width: 8),
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                color: isSending
                    ? const Color(0xFFCBBBA4)
                    : const Color(0xFF2E241C),
                borderRadius: BorderRadius.circular(16),
              ),
              child: IconButton(
                tooltip: 'Send',
                onPressed: isSending ? null : onSend,
                icon: isSending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.arrow_upward, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MediaAndModelSheet extends StatefulWidget {
  const MediaAndModelSheet({
    required this.provider,
    required this.settings,
    required this.cachedModels,
    required this.onProviderChanged,
    required this.onModelChanged,
    required this.onMaxTokensChanged,
    required this.onFetchModels,
    required this.onConfigureKey,
    super.key,
  });

  final ProviderDefinition provider;
  final ProviderSettings settings;
  final List<String> cachedModels;
  final ValueChanged<String> onProviderChanged;
  final ValueChanged<String> onModelChanged;
  final ValueChanged<int> onMaxTokensChanged;
  final Future<List<String>> Function() onFetchModels;
  final VoidCallback onConfigureKey;

  @override
  State<MediaAndModelSheet> createState() => _MediaAndModelSheetState();
}

class _MediaAndModelSheetState extends State<MediaAndModelSheet> {
  late int _maxTokens;
  var _fetching = false;
  late String _selectedProviderId;
  late String _selectedModel;

  @override
  void initState() {
    super.initState();
    _maxTokens = widget.settings.maxTokens;
    _selectedProviderId = widget.provider.id;
    _selectedModel = widget.settings.model;
  }

  Future<void> _fetch() async {
    setState(() => _fetching = true);
    try {
      final models = await widget.onFetchModels();
      if (mounted) {
        setState(() {
          if (!models.contains(_selectedModel) && models.isNotEmpty) {
            _selectedModel = models.first;
            widget.onModelChanged(_selectedModel);
          }
        });
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Model fetch failed: $error')),
      );
    } finally {
      if (mounted) setState(() => _fetching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentProvider = providerCatalog.firstWhere((p) => p.id == _selectedProviderId);
    final models = widget.cachedModels.isNotEmpty ? widget.cachedModels : currentProvider.models;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      decoration: const BoxDecoration(
        color: Color(0xFFFFFBF2),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 16,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 42,
              height: 5,
              decoration: BoxDecoration(
                color: const Color(0xFFDCCBB8),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Input & Settings',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Color(0xFF2D241C),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Media Attachment (Soon)',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Color(0xFF6C5946),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildMediaItem(Icons.image_outlined, 'Photos'),
              _buildMediaItem(Icons.camera_alt_outlined, 'Camera'),
              _buildMediaItem(Icons.insert_drive_file_outlined, 'Document'),
              _buildMediaItem(Icons.mic_none_outlined, 'Audio'),
            ],
          ),
          const SizedBox(height: 24),
          const Divider(color: Color(0xFFE7D8C4)),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _selectedProviderId,
                  dropdownColor: const Color(0xFFFFFBF2),
                  decoration: const InputDecoration(
                    labelText: 'AI Provider',
                    labelStyle: TextStyle(color: Color(0xFF6C5946)),
                    border: OutlineInputBorder(
                      borderSide: BorderSide(color: Color(0xFFDCCBB8)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Color(0xFFDCCBB8)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Color(0xFF7B4E2E)),
                    ),
                    prefixIcon: Icon(Icons.hub_outlined, color: Color(0xFF7B4E2E)),
                  ),
                  items: providerCatalog.map((p) {
                    return DropdownMenuItem<String>(
                      value: p.id,
                      child: Text(p.name),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      final nextProvider = providerCatalog.firstWhere((p) => p.id == val);
                      setState(() {
                        _selectedProviderId = val;
                        _selectedModel = nextProvider.models.first;
                      });
                      widget.onProviderChanged(val);
                    }
                  },
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 56,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFFDCCBB8)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    widget.onConfigureKey();
                  },
                  child: const Icon(Icons.key, color: Color(0xFF7B4E2E)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: models.contains(_selectedModel) ? _selectedModel : models.first,
                  dropdownColor: const Color(0xFFFFFBF2),
                  decoration: const InputDecoration(
                    labelText: 'Model Name',
                    labelStyle: TextStyle(color: Color(0xFF6C5946)),
                    border: OutlineInputBorder(
                      borderSide: BorderSide(color: Color(0xFFDCCBB8)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Color(0xFFDCCBB8)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Color(0xFF7B4E2E)),
                    ),
                    prefixIcon: Icon(Icons.memory_outlined, color: Color(0xFF7B4E2E)),
                  ),
                  items: models.map((m) {
                    return DropdownMenuItem<String>(
                      value: m,
                      child: Text(
                        m,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13),
                      ),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _selectedModel = val);
                      widget.onModelChanged(val);
                    }
                  },
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 56,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFFDCCBB8)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: _fetching ? null : _fetch,
                  child: _fetching
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync, color: Color(0xFF7B4E2E)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Max Output Tokens',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2D241C),
                    ),
                  ),
                  Text(
                    '$_maxTokens tokens',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF7B4E2E),
                    ),
                  ),
                ],
              ),
              Slider(
                value: _maxTokens.toDouble().clamp(128, 16384),
                min: 128,
                max: 16384,
                divisions: 63,
                activeColor: const Color(0xFF7B4E2E),
                inactiveColor: const Color(0xFFE7D8C4),
                onChanged: (val) {
                  setState(() => _maxTokens = val.round());
                  widget.onMaxTokensChanged(val.round());
                },
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [512, 1024, 2048, 4096, 8192].map((preset) {
                  final selected = _maxTokens == preset;
                  return ChoiceChip(
                    label: Text(
                      preset.toString(),
                      style: TextStyle(
                        fontSize: 11,
                        color: selected ? Colors.white : const Color(0xFF2D241C),
                      ),
                    ),
                    selected: selected,
                    selectedColor: const Color(0xFF7B4E2E),
                    backgroundColor: const Color(0xFFFFFCF6),
                    onSelected: (sel) {
                      if (sel) {
                        setState(() => _maxTokens = preset);
                        widget.onMaxTokensChanged(preset);
                      }
                    },
                  );
                }).toList(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMediaItem(IconData icon, String label) {
    return Opacity(
      opacity: 0.4,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFE7D8C4),
              border: Border.all(color: const Color(0xFFDCCBB8)),
            ),
            child: Icon(icon, color: const Color(0xFF6C5946)),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: Color(0xFF6C5946),
            ),
          ),
        ],
      ),
    );
  }
}

class ProviderSettingsSheet extends StatefulWidget {
  const ProviderSettingsSheet({
    required this.provider,
    required this.settings,
    required this.cachedModels,
    required this.onFetchModels,
    super.key,
  });

  final ProviderDefinition provider;
  final ProviderSettings settings;
  final List<String> cachedModels;
  final Future<List<String>> Function() onFetchModels;

  @override
  State<ProviderSettingsSheet> createState() => _ProviderSettingsSheetState();
}

class _ProviderSettingsSheetState extends State<ProviderSettingsSheet> {
  late final TextEditingController _keyController;
  late final TextEditingController _baseUrlController;
  late final TextEditingController _modelController;
  late final TextEditingController _maxTokensController;
  List<String> _models = [];
  var _fetching = false;

  @override
  void initState() {
    super.initState();
    _keyController = TextEditingController(text: widget.settings.apiKey);
    _baseUrlController = TextEditingController(text: widget.settings.baseUrl);
    _modelController = TextEditingController(text: widget.settings.model);
    _maxTokensController = TextEditingController(
      text: widget.settings.maxTokens.toString(),
    );
    _models = widget.cachedModels;
  }

  @override
  void dispose() {
    _keyController.dispose();
    _baseUrlController.dispose();
    _modelController.dispose();
    _maxTokensController.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    setState(() => _fetching = true);
    try {
      final models = await widget.onFetchModels();
      setState(() => _models = models);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Model fetch failed: $error')),
      );
    } finally {
      if (mounted) setState(() => _fetching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SheetFrame(
      title: widget.provider.name,
      subtitle: '${widget.provider.keyLabel}  |  ${widget.provider.baseUrl}',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _keyController,
            obscureText: true,
            decoration: InputDecoration(
              labelText: widget.provider.requiresKey
                  ? 'API key'
                  : 'API key (optional)',
              prefixIcon: const Icon(Icons.key),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _baseUrlController,
            decoration: const InputDecoration(
              labelText: 'Base URL',
              prefixIcon: Icon(Icons.link),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _modelController,
                  decoration: const InputDecoration(
                    labelText: 'Selected model',
                    prefixIcon: Icon(Icons.memory),
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: _fetching ? null : _fetch,
                icon: _fetching
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync),
                label: const Text('Fetch'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _maxTokensController,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Max tokens',
              helperText: 'Lower this if a provider says you do not have enough credits.',
              prefixIcon: Icon(Icons.speed),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 138,
            child: ListView.builder(
              itemCount: _models.length,
              itemBuilder: (context, index) {
                final model = _models[index];
                return ListTile(
                  dense: true,
                  leading: const Icon(Icons.radio_button_unchecked, size: 18),
                  title: Text(model, overflow: TextOverflow.ellipsis),
                  onTap: () => _modelController.text = model,
                );
              },
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: () {
                    final parsedMaxTokens = int.tryParse(
                          _maxTokensController.text.trim(),
                        ) ??
                        widget.provider.defaultMaxTokens;
                    Navigator.of(context).pop(
                      ProviderSettings(
                        apiKey: _keyController.text.trim(),
                        baseUrl: _baseUrlController.text.trim(),
                        model: _modelController.text.trim(),
                        maxTokens: parsedMaxTokens.clamp(1, 131072).toInt(),
                      ),
                    );
                  },
                  child: const Text('Save provider'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class ModelPickerSheet extends StatefulWidget {
  const ModelPickerSheet({
    required this.provider,
    required this.models,
    required this.selectedModel,
    required this.isFetching,
    required this.onFetchModels,
    super.key,
  });

  final ProviderDefinition provider;
  final List<String> models;
  final String selectedModel;
  final bool isFetching;
  final Future<List<String>> Function() onFetchModels;

  @override
  State<ModelPickerSheet> createState() => _ModelPickerSheetState();
}

class _ModelPickerSheetState extends State<ModelPickerSheet> {
  final _searchController = TextEditingController();
  final _manualController = TextEditingController();
  late List<String> _models;
  var _fetching = false;

  @override
  void initState() {
    super.initState();
    _models = widget.models;
    _manualController.text = widget.selectedModel;
  }

  @override
  void dispose() {
    _searchController.dispose();
    _manualController.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    setState(() => _fetching = true);
    try {
      final models = await widget.onFetchModels();
      setState(() => _models = models);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Model fetch failed: $error')),
      );
    } finally {
      if (mounted) setState(() => _fetching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim().toLowerCase();
    final filtered = _models.where((model) {
      return query.isEmpty || model.toLowerCase().contains(query);
    }).toList();

    return SheetFrame(
      title: 'Select model',
      subtitle: widget.provider.name,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: SearchBox(
                  controller: _searchController,
                  hint: 'Search models or type below',
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: _fetching ? null : _fetch,
                icon: _fetching
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cloud_download_outlined),
                label: const Text('Fetch'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _manualController,
            decoration: const InputDecoration(
              labelText: 'Manual model ID',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 260,
            child: ListView.builder(
              itemCount: filtered.length,
              itemBuilder: (context, index) {
                final model = filtered[index];
                final selected = model == widget.selectedModel;
                return ListTile(
                  dense: true,
                  leading: Icon(
                    selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                  ),
                  title: Text(model),
                  onTap: () => Navigator.of(context).pop(model),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop(_manualController.text),
              child: const Text('Use typed model'),
            ),
          ),
        ],
      ),
    );
  }
}

class SheetFrame extends StatelessWidget {
  const SheetFrame({
    required this.title,
    required this.subtitle,
    required this.child,
    super.key,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 10,
        right: 10,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 10,
      ),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 720),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFBF3),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: const Color(0xFFE0CEB8)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.16),
              blurRadius: 34,
              offset: const Offset(0, 18),
            ),
          ],
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: GoogleFonts.notoSerif(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF2D241C),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(color: Color(0xFF77624F)),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 18),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class SearchBox extends StatelessWidget {
  const SearchBox({
    required this.controller,
    required this.hint,
    required this.onChanged,
    super.key,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: const Icon(Icons.search),
        filled: true,
        fillColor: const Color(0xFFFFFBF4),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFE2D0BA)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFE2D0BA)),
        ),
      ),
    );
  }
}

class AppMark extends StatelessWidget {
  const AppMark({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: const Color(0xFF2E241C),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Icon(Icons.auto_awesome, color: Color(0xFFFFE0A8)),
    );
  }
}

class ProviderAvatar extends StatelessWidget {
  const ProviderAvatar({
    required this.label,
    this.small = false,
    super.key,
  });

  final String label;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final size = small ? 24.0 : 38.0;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFF3B3027),
        borderRadius: BorderRadius.circular(small ? 8 : 13),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: const Color(0xFFFFE0A8),
          fontSize: small ? 10 : 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class ChatClient {
  Future<List<String>> fetchModels(
    ProviderDefinition provider,
    ProviderSettings settings,
  ) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    try {
      final uri = Uri.parse('${_baseUrl(provider, settings)}/models');
      final request = await client.getUrl(uri);
      _setHeaders(request, provider, settings, stream: false);
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('HTTP ${response.statusCode}: $body');
      }
      final decoded = jsonDecode(body);
      final data = decoded is Map<String, dynamic> ? decoded['data'] : null;
      if (data is List) {
        return data
            .map((item) {
              if (item is String) return item;
              if (item is Map) return item['id']?.toString() ?? '';
              return '';
            })
            .where((model) => model.trim().isNotEmpty)
            .toSet()
            .toList();
      }
      if (decoded is Map<String, dynamic> && decoded['models'] is List) {
        return (decoded['models'] as List)
            .map((item) => item.toString())
            .where((model) => model.trim().isNotEmpty)
            .toSet()
            .toList();
      }
      return provider.models;
    } finally {
      client.close(force: true);
    }
  }

  Future<String> sendChat({
    required ProviderDefinition provider,
    required ProviderSettings settings,
    required String model,
    required List<ChatMessage> messages,
  }) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
    try {
      final uri = Uri.parse('${_baseUrl(provider, settings)}/chat/completions');
      final request = await client.postUrl(uri);
      _setHeaders(request, provider, settings, stream: false);
      request.headers.contentType = ContentType.json;

      final payload = <String, dynamic>{
        'model': model,
        'messages': messages
            .map((message) => {
                  'role': message.role.apiName,
                  'content': message.text,
                })
            .toList(),
        'max_tokens': settings.maxTokens,
        'temperature': 1.0,
        'top_p': 0.95,
        'stream': false,
      };

      request.write(jsonEncode(payload));
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('HTTP ${response.statusCode}: $body');
      }
      return _extractAnswer(jsonDecode(body));
    } finally {
      client.close(force: true);
    }
  }

  Stream<String> sendChatStream({
    required ProviderDefinition provider,
    required ProviderSettings settings,
    required String model,
    required List<ChatMessage> messages,
  }) async* {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
    try {
      final uri = Uri.parse('${_baseUrl(provider, settings)}/chat/completions');
      final request = await client.postUrl(uri);
      _setHeaders(request, provider, settings, stream: true);
      request.headers.contentType = ContentType.json;

      final payload = <String, dynamic>{
        'model': model,
        'messages': messages
            .map((message) => {
                  'role': message.role.apiName,
                  'content': message.text,
                })
            .toList(),
        'max_tokens': settings.maxTokens,
        'temperature': 1.0,
        'top_p': 0.95,
        'stream': true,
      };

      request.write(jsonEncode(payload));
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final body = await response.transform(utf8.decoder).join();
        throw HttpException('HTTP ${response.statusCode}: $body');
      }

      final lines = response
          .transform(utf8.decoder)
          .transform(const LineSplitter());

      await for (final line in lines) {
        if (line.trim().isEmpty) continue;
        if (line.startsWith('data: ')) {
          final dataStr = line.substring(6).trim();
          if (dataStr == '[DONE]') {
            break;
          }
          try {
            final decoded = jsonDecode(dataStr);
            if (decoded is Map<String, dynamic>) {
              final choices = decoded['choices'];
              if (choices is List && choices.isNotEmpty) {
                final first = choices.first;
                if (first is Map) {
                  final delta = first['delta'];
                  if (delta is Map && delta['content'] != null) {
                    yield delta['content'].toString();
                  } else if (first['text'] != null) {
                    yield first['text'].toString();
                  }
                }
              }
            }
          } catch (_) {
            // Ignore JSON decode errors of partial/empty lines
          }
        }
      }
    } finally {
      client.close(force: true);
    }
  }

  String _baseUrl(ProviderDefinition provider, ProviderSettings settings) {
    final raw = settings.baseUrl.trim().isEmpty
        ? provider.baseUrl
        : settings.baseUrl.trim();
    return raw.replaceAll(RegExp(r'/+$'), '');
  }

  void _setHeaders(
    HttpClientRequest request,
    ProviderDefinition provider,
    ProviderSettings settings, {
    required bool stream,
  }) {
    request.headers.set('Accept', stream ? 'text/event-stream' : 'application/json');
    final apiKey = settings.apiKey.trim();
    if (apiKey.isNotEmpty) {
      request.headers.set('Authorization', 'Bearer $apiKey');
    }
    for (final entry in provider.extraHeaders.entries) {
      request.headers.set(entry.key, entry.value);
    }
  }

  String _extractAnswer(dynamic decoded) {
    if (decoded is! Map<String, dynamic>) return decoded.toString();
    final choices = decoded['choices'];
    if (choices is List && choices.isNotEmpty) {
      final first = choices.first;
      if (first is Map) {
        final message = first['message'];
        if (message is Map && message['content'] != null) {
          final content = message['content'];
          if (content is String) return content;
          return jsonEncode(content);
        }
        if (first['text'] != null) return first['text'].toString();
      }
    }
    if (decoded['output_text'] != null) return decoded['output_text'].toString();
    if (decoded['content'] != null) return decoded['content'].toString();
    return const JsonEncoder.withIndent('  ').convert(decoded);
  }
}

class ProviderDefinition {
  const ProviderDefinition({
    required this.id,
    required this.name,
    required this.shortName,
    required this.keyLabel,
    required this.baseUrl,
    required this.models,
    this.defaultMaxTokens = 4096,
    this.requiresKey = true,
    this.extraHeaders = const {},
  });

  final String id;
  final String name;
  final String shortName;
  final String keyLabel;
  final String baseUrl;
  final List<String> models;
  final int defaultMaxTokens;
  final bool requiresKey;
  final Map<String, String> extraHeaders;
}

class ProviderSettings {
  const ProviderSettings({
    required this.apiKey,
    required this.baseUrl,
    required this.model,
    required this.maxTokens,
  });

  factory ProviderSettings.defaults(ProviderDefinition provider) {
    return ProviderSettings(
      apiKey: '',
      baseUrl: provider.baseUrl,
      model: provider.models.first,
      maxTokens: provider.defaultMaxTokens,
    );
  }

  factory ProviderSettings.fromJson(Map<String, dynamic> json) {
    return ProviderSettings(
      apiKey: json['apiKey']?.toString() ?? '',
      baseUrl: json['baseUrl']?.toString() ?? '',
      model: json['model']?.toString() ?? '',
      maxTokens: _readInt(json['maxTokens'], 0),
    );
  }

  final String apiKey;
  final String baseUrl;
  final String model;
  final int maxTokens;

  ProviderSettings copyWith({
    String? apiKey,
    String? baseUrl,
    String? model,
    int? maxTokens,
  }) {
    return ProviderSettings(
      apiKey: apiKey ?? this.apiKey,
      baseUrl: baseUrl ?? this.baseUrl,
      model: model ?? this.model,
      maxTokens: maxTokens ?? this.maxTokens,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'apiKey': apiKey,
      'baseUrl': baseUrl,
      'model': model,
      'maxTokens': maxTokens,
    };
  }

  static int _readInt(dynamic value, int fallback) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }
}

enum MessageRole {
  system('system'),
  user('user'),
  assistant('assistant');

  const MessageRole(this.apiName);
  final String apiName;
}

class ChatMessage {
  const ChatMessage({
    required this.role,
    required this.text,
    this.isError = false,
  });

  final MessageRole role;
  final String text;
  final bool isError;
}

class ChatSession {
  final String id;
  final String title;
  final List<ChatMessage> messages;
  final String providerId;
  final String model;

  ChatSession({
    required this.id,
    required this.title,
    required this.messages,
    required this.providerId,
    required this.model,
  });

  ChatSession copyWith({
    String? id,
    String? title,
    List<ChatMessage>? messages,
    String? providerId,
    String? model,
  }) {
    return ChatSession(
      id: id ?? this.id,
      title: title ?? this.title,
      messages: messages ?? this.messages,
      providerId: providerId ?? this.providerId,
      model: model ?? this.model,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'messages': messages.map((m) => {
          'role': m.role.apiName,
          'text': m.text,
          'isError': m.isError,
        }).toList(),
        'providerId': providerId,
        'model': model,
      };

  factory ChatSession.fromJson(Map<String, dynamic> json) {
    final messagesList = (json['messages'] as List?)
            ?.map((m) => ChatMessage(
                  role: MessageRole.values.firstWhere(
                    (v) => v.apiName == m['role'],
                    orElse: () => MessageRole.user,
                  ),
                  text: m['text']?.toString() ?? '',
                  isError: m['isError'] as bool? ?? false,
                ))
            .toList() ??
        [];
    return ChatSession(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      messages: messagesList,
      providerId: json['providerId']?.toString() ?? providerCatalog.first.id,
      model: json['model']?.toString() ?? '',
    );
  }
}

const providerCatalog = <ProviderDefinition>[
  ProviderDefinition(
    id: 'nvidia',
    name: 'NVIDIA NIM',
    shortName: 'NV',
    keyLabel: 'NVIDIA_API_KEY',
    baseUrl: 'https://integrate.api.nvidia.com/v1',
    models: [
      'minimaxai/minimax-m3',
      'meta/llama-3.1-405b-instruct',
      'nvidia/llama-3.1-nemotron-ultra-253b-v1',
      'deepseek-ai/deepseek-r1',
    ],
    defaultMaxTokens: 8192,
  ),
  ProviderDefinition(
    id: 'openai',
    name: 'OpenAI',
    shortName: 'OA',
    keyLabel: 'OPENAI_API_KEY',
    baseUrl: 'https://api.openai.com/v1',
    models: ['gpt-4.1', 'gpt-4.1-mini', 'gpt-4o', 'o4-mini'],
  ),
  ProviderDefinition(
    id: 'openrouter',
    name: 'OpenRouter',
    shortName: 'OR',
    keyLabel: 'OPENROUTER_API_KEY',
    baseUrl: 'https://openrouter.ai/api/v1',
    models: [
      'anthropic/claude-3.5-sonnet',
      'openai/gpt-4o',
      'google/gemini-2.5-pro',
    ],
    defaultMaxTokens: 2048,
    extraHeaders: {
      'HTTP-Referer': 'https://termuxforge.local',
      'X-Title': 'Forge Chat',
    },
  ),
  ProviderDefinition(
    id: 'google',
    name: 'Google Gemini',
    shortName: 'GG',
    keyLabel: 'GEMINI_API_KEY',
    baseUrl: 'https://generativelanguage.googleapis.com/v1beta/openai',
    models: ['gemini-2.5-pro', 'gemini-2.5-flash', 'gemini-2.0-flash'],
  ),
  ProviderDefinition(
    id: 'groq',
    name: 'Groq',
    shortName: 'GQ',
    keyLabel: 'GROQ_API_KEY',
    baseUrl: 'https://api.groq.com/openai/v1',
    models: ['llama-3.3-70b-versatile', 'deepseek-r1-distill-llama-70b'],
  ),
  ProviderDefinition(
    id: 'together',
    name: 'Together AI',
    shortName: 'TG',
    keyLabel: 'TOGETHER_API_KEY',
    baseUrl: 'https://api.together.xyz/v1',
    models: ['meta-llama/Llama-3.3-70B-Instruct-Turbo', 'deepseek-ai/DeepSeek-R1'],
  ),
  ProviderDefinition(
    id: 'fireworks',
    name: 'Fireworks AI',
    shortName: 'FW',
    keyLabel: 'FIREWORKS_API_KEY',
    baseUrl: 'https://api.fireworks.ai/inference/v1',
    models: ['accounts/fireworks/models/llama-v3p1-405b-instruct'],
  ),
  ProviderDefinition(
    id: 'deepinfra',
    name: 'DeepInfra',
    shortName: 'DI',
    keyLabel: 'DEEPINFRA_API_KEY',
    baseUrl: 'https://api.deepinfra.com/v1/openai',
    models: ['meta-llama/Meta-Llama-3.1-70B-Instruct', 'deepseek-ai/DeepSeek-R1'],
  ),
  ProviderDefinition(
    id: 'mistral',
    name: 'Mistral AI',
    shortName: 'MI',
    keyLabel: 'MISTRAL_API_KEY',
    baseUrl: 'https://api.mistral.ai/v1',
    models: ['mistral-large-latest', 'codestral-latest', 'ministral-8b-latest'],
  ),
  ProviderDefinition(
    id: 'xai',
    name: 'xAI',
    shortName: 'xA',
    keyLabel: 'XAI_API_KEY',
    baseUrl: 'https://api.x.ai/v1',
    models: ['grok-4', 'grok-3', 'grok-3-mini'],
  ),
  ProviderDefinition(
    id: 'perplexity',
    name: 'Perplexity',
    shortName: 'PX',
    keyLabel: 'PERPLEXITY_API_KEY',
    baseUrl: 'https://api.perplexity.ai',
    models: ['sonar', 'sonar-pro', 'sonar-reasoning-pro'],
  ),
  ProviderDefinition(
    id: 'deepseek',
    name: 'DeepSeek',
    shortName: 'DS',
    keyLabel: 'DEEPSEEK_API_KEY',
    baseUrl: 'https://api.deepseek.com',
    models: ['deepseek-chat', 'deepseek-reasoner'],
  ),
  ProviderDefinition(
    id: 'cohere',
    name: 'Cohere',
    shortName: 'CO',
    keyLabel: 'COHERE_API_KEY',
    baseUrl: 'https://api.cohere.com/compatibility/v1',
    models: ['command-a-03-2025', 'command-r-plus', 'command-r'],
  ),
  ProviderDefinition(
    id: 'cerebras',
    name: 'Cerebras',
    shortName: 'CB',
    keyLabel: 'CEREBRAS_API_KEY',
    baseUrl: 'https://api.cerebras.ai/v1',
    models: ['llama-4-scout-17b-16e-instruct', 'llama3.1-70b'],
  ),
  ProviderDefinition(
    id: 'sambanova',
    name: 'SambaNova',
    shortName: 'SN',
    keyLabel: 'SAMBANOVA_API_KEY',
    baseUrl: 'https://api.sambanova.ai/v1',
    models: ['Meta-Llama-3.1-405B-Instruct', 'DeepSeek-R1'],
  ),
  ProviderDefinition(
    id: 'novita',
    name: 'Novita AI',
    shortName: 'NO',
    keyLabel: 'NOVITA_API_KEY',
    baseUrl: 'https://api.novita.ai/v3/openai',
    models: ['meta-llama/llama-3.1-8b-instruct', 'deepseek/deepseek-r1'],
  ),
  ProviderDefinition(
    id: 'hyperbolic',
    name: 'Hyperbolic',
    shortName: 'HB',
    keyLabel: 'HYPERBOLIC_API_KEY',
    baseUrl: 'https://api.hyperbolic.xyz/v1',
    models: ['meta-llama/Meta-Llama-3.1-405B-Instruct', 'deepseek-ai/DeepSeek-R1'],
  ),
  ProviderDefinition(
    id: 'aimlapi',
    name: 'AI/ML API',
    shortName: 'AI',
    keyLabel: 'AIMLAPI_KEY',
    baseUrl: 'https://api.aimlapi.com/v1',
    models: ['gpt-4o', 'claude-3-5-sonnet', 'meta-llama/Meta-Llama-3.1-70B-Instruct'],
  ),
  ProviderDefinition(
    id: 'nebius',
    name: 'Nebius AI Studio',
    shortName: 'NB',
    keyLabel: 'NEBIUS_API_KEY',
    baseUrl: 'https://api.studio.nebius.com/v1',
    models: ['meta-llama/Meta-Llama-3.1-70B-Instruct', 'deepseek-ai/DeepSeek-R1'],
  ),
  ProviderDefinition(
    id: 'moonshot',
    name: 'Moonshot Kimi',
    shortName: 'KM',
    keyLabel: 'MOONSHOT_API_KEY',
    baseUrl: 'https://api.moonshot.ai/v1',
    models: ['kimi-k2-0711-preview', 'moonshot-v1-128k'],
  ),
  ProviderDefinition(
    id: 'zhipu',
    name: 'Zhipu GLM',
    shortName: 'GL',
    keyLabel: 'ZHIPU_API_KEY',
    baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
    models: ['glm-4-plus', 'glm-4-air', 'glm-z1-air'],
  ),
  ProviderDefinition(
    id: 'dashscope',
    name: 'Alibaba DashScope',
    shortName: 'DS',
    keyLabel: 'DASHSCOPE_API_KEY',
    baseUrl: 'https://dashscope-intl.aliyuncs.com/compatible-mode/v1',
    models: ['qwen-plus', 'qwen-max', 'qwen-turbo'],
  ),
  ProviderDefinition(
    id: 'siliconflow',
    name: 'SiliconFlow',
    shortName: 'SF',
    keyLabel: 'SILICONFLOW_API_KEY',
    baseUrl: 'https://api.siliconflow.cn/v1',
    models: ['deepseek-ai/DeepSeek-R1', 'Qwen/Qwen2.5-72B-Instruct'],
  ),
  ProviderDefinition(
    id: 'minimax',
    name: 'MiniMax',
    shortName: 'MM',
    keyLabel: 'MINIMAX_API_KEY',
    baseUrl: 'https://api.minimax.chat/v1',
    models: ['MiniMax-M1', 'MiniMax-Text-01'],
  ),
  ProviderDefinition(
    id: 'yi',
    name: '01.AI Yi',
    shortName: 'YI',
    keyLabel: 'YI_API_KEY',
    baseUrl: 'https://api.01.ai/v1',
    models: ['yi-large', 'yi-lightning'],
  ),
  ProviderDefinition(
    id: 'baichuan',
    name: 'Baichuan',
    shortName: 'BC',
    keyLabel: 'BAICHUAN_API_KEY',
    baseUrl: 'https://api.baichuan-ai.com/v1',
    models: ['Baichuan4', 'Baichuan3-Turbo'],
  ),
  ProviderDefinition(
    id: 'qianfan',
    name: 'Baidu Qianfan',
    shortName: 'BD',
    keyLabel: 'QIANFAN_API_KEY',
    baseUrl: 'https://qianfan.baidubce.com/v2',
    models: ['ernie-4.0-turbo-8k', 'ernie-3.5-8k'],
  ),
  ProviderDefinition(
    id: 'volcengine',
    name: 'Volcengine Ark',
    shortName: 'VK',
    keyLabel: 'ARK_API_KEY',
    baseUrl: 'https://ark.cn-beijing.volces.com/api/v3',
    models: ['doubao-1-5-pro-32k', 'deepseek-r1-250120'],
  ),
  ProviderDefinition(
    id: 'lepton',
    name: 'Lepton AI',
    shortName: 'LP',
    keyLabel: 'LEPTON_API_KEY',
    baseUrl: 'https://api.lepton.ai/v1',
    models: ['llama3.1-70b', 'deepseek-r1'],
  ),
  ProviderDefinition(
    id: 'lambda',
    name: 'Lambda Inference',
    shortName: 'LA',
    keyLabel: 'LAMBDA_API_KEY',
    baseUrl: 'https://api.lambdalabs.com/v1',
    models: ['llama3.1-405b-instruct-fp8', 'hermes3-405b'],
  ),
  ProviderDefinition(
    id: 'ollama',
    name: 'Ollama Local',
    shortName: 'OL',
    keyLabel: 'OLLAMA_API_KEY',
    baseUrl: 'http://127.0.0.1:11434/v1',
    models: ['llama3.2', 'qwen2.5', 'mistral'],
    requiresKey: false,
  ),
  ProviderDefinition(
    id: 'lmstudio',
    name: 'LM Studio Local',
    shortName: 'LM',
    keyLabel: 'LMSTUDIO_API_KEY',
    baseUrl: 'http://127.0.0.1:1234/v1',
    models: ['local-model'],
    requiresKey: false,
  ),
  ProviderDefinition(
    id: 'vllm',
    name: 'vLLM Server',
    shortName: 'VL',
    keyLabel: 'VLLM_API_KEY',
    baseUrl: 'http://127.0.0.1:8000/v1',
    models: ['served-model'],
    requiresKey: false,
  ),
  ProviderDefinition(
    id: 'custom',
    name: 'Custom OpenAI-Compatible',
    shortName: 'CU',
    keyLabel: 'CUSTOM_API_KEY',
    baseUrl: 'https://example.com/v1',
    models: ['custom-model'],
  ),
];
