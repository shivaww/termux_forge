import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

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
  final Set<String> _sendingSessionIds = {};
  var _isFetchingModels = false;
  SearchSettings _searchSettings = SearchSettings.defaults();
  bool _agenticEnabled = true;
  String _agenticWorkspace = '/data/data/com.termux/files/home';
  String _customMcpUrl = '';
  bool _deepResearchEnabled = false;

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
    final searchRaw = prefs.getString('search_settings_v1');
    final nextSettings = <String, ProviderSettings>{};

    SearchSettings loadedSearchSettings = SearchSettings.defaults();
    if (searchRaw != null && searchRaw.trim().isNotEmpty) {
      try {
        loadedSearchSettings = SearchSettings.fromJson(jsonDecode(searchRaw));
      } catch (_) {}
    }

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
      String? key;
      try {
        key = await _secureStorage.read(key: _keyStorageName(provider.id));
      } catch (e) {
        key = prefs.getString('fallback_api_key_${provider.id}');
        debugPrint('Secure storage read failed for ${provider.id}: $e');
      }
      final current = nextSettings[provider.id] ??
          ProviderSettings.defaults(provider);
      final normalized = current.maxTokens < 1
          ? current.copyWith(maxTokens: provider.defaultMaxTokens)
          : current;
      nextSettings[provider.id] = normalized.copyWith(apiKey: key ?? '');
    }

    final agenticRaw = prefs.getBool('agentic_enabled_v1');
    final agenticWorkspaceRaw = prefs.getString('agentic_workspace_v1');
    final customMcpUrlRaw = prefs.getString('custom_mcp_url_v1');
    final deepResearchRaw = prefs.getBool('deep_research_enabled_v1');

    if (!mounted) return;
    setState(() {
      _prefs = prefs;
      _settings = nextSettings;
      _searchSettings = loadedSearchSettings;
      _agenticEnabled = agenticRaw ?? true;
      _agenticWorkspace = agenticWorkspaceRaw ?? '/data/data/com.termux/files/home';
      _customMcpUrl = customMcpUrlRaw ?? '';
      _deepResearchEnabled = deepResearchRaw ?? false;
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
      try {
        if (key.isEmpty) {
          await _secureStorage.delete(key: _keyStorageName(entry.key));
        } else {
          await _secureStorage.write(key: _keyStorageName(entry.key), value: key);
        }
      } catch (e) {
        debugPrint('Secure storage write failed for ${entry.key}: $e');
        if (key.isEmpty) {
          await prefs.remove('fallback_api_key_${entry.key}');
        } else {
          await prefs.setString('fallback_api_key_${entry.key}', key);
        }
      }
    }
    await prefs.setString(_settingsKey, jsonEncode(metadata));
    await prefs.setString(_selectedProviderKey, _selectedProviderId);
    await prefs.setString('search_settings_v1', jsonEncode(_searchSettings.toJson()));
    await prefs.setBool('agentic_enabled_v1', _agenticEnabled);
    await prefs.setBool('deep_research_enabled_v1', _deepResearchEnabled);
    await prefs.setString('agentic_workspace_v1', _agenticWorkspace);
    await prefs.setString('custom_mcp_url_v1', _customMcpUrl);
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
      
      final targetSessionId = _activeSessionId;
      if (targetSessionId != null) {
        final sessionIndex = _sessions.indexWhere((s) => s.id == targetSessionId);
        if (sessionIndex != -1) {
          _sessions[sessionIndex] = _sessions[sessionIndex].copyWith(
            providerId: provider.id,
            model: result.model,
            maxTokens: result.maxTokens,
          );
        }
      }
    });
    await _saveSettings();
    await _saveSessions();
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
      
      final targetSessionId = _activeSessionId;
      if (targetSessionId != null) {
        final sessionIndex = _sessions.indexWhere((s) => s.id == targetSessionId);
        if (sessionIndex != -1) {
          _sessions[sessionIndex] = _sessions[sessionIndex].copyWith(model: selected.trim());
        }
      }
    });
    await _saveSettings();
    await _saveSessions();
  }

  static const String mcpAndSearchSystemPrompt =
      "You have access to a web search tool and local Termux file system tools.\n"
      "If you need to search the web, output a single line: [SEARCH_REQUEST: your search query] and stop generating.\n"
      "If you need to use the local file system MCP server, output a single line: [MCP_REQUEST: {\"method\": \"...\", \"params\": {...}}] and stop generating.\n"
      "MCP methods available:\n"
      "- file_read: params {path: string}\n"
      "- file_write: params {path: string, content: string}\n"
      "- file_edit: params {path: string, start_line: int, end_line: int, replacement: string}\n"
      "- file_delete: params {path: string}\n"
      "- dir_list: params {path: string}\n"
      "- dir_create: params {path: string}\n"
      "- code_search: params {path: string, query: string}\n"
      "- file_search: params {path: string, pattern: string}\n"
      "Once results are provided, continue your response.";

  Future<void> _sendMessage() async {
    final prompt = _messageController.text.trim();
    if (prompt.isEmpty) return;

    final targetSessionId = _activeSessionId;
    if (targetSessionId == null) return;
    if (_sendingSessionIds.contains(targetSessionId)) return;

    final sessionIndex = _sessions.indexWhere((s) => s.id == targetSessionId);
    if (sessionIndex == -1) return;

    final session = _sessions[sessionIndex];
    final provider = providerCatalog.firstWhere((p) => p.id == session.providerId);
    final baseSettings = _settings[session.providerId] ?? ProviderSettings.defaults(provider);
    final settings = baseSettings.copyWith(
      model: session.model.isNotEmpty ? session.model : baseSettings.model,
      maxTokens: session.maxTokens ?? baseSettings.maxTokens,
    );
    final activeModel = session.model.isNotEmpty ? session.model : settings.model;

    if (_deepResearchEnabled && !_agenticEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please turn on Agentic File Access for Research Mode'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    if (provider.requiresKey && settings.apiKey.trim().isEmpty) {
      await _openProviderSheet(provider.id);
      return;
    }

    if (targetSessionId == _activeSessionId) {
      _messageController.clear();
    }

    final userMessage = ChatMessage(
      role: MessageRole.user,
      text: prompt,
      images: List<String>.from(session.attachedImagesBase64),
      files: List<AttachedFile>.from(session.attachedFiles),
    );

    String updatedTitle = session.title;
    if (session.title == 'Welcome Chat' || session.title == 'New Chat') {
      updatedTitle = prompt.length > 25 ? '${prompt.substring(0, 25)}...' : prompt;
    }

    setState(() {
      _sendingSessionIds.add(targetSessionId);
      final updatedMessages = List<ChatMessage>.from(session.messages)..add(userMessage);
      _sessions[sessionIndex] = session.copyWith(
        messages: updatedMessages,
        title: updatedTitle,
        attachedImagesBase64: const [],
        attachedFiles: const [],
      );
    });

    if (targetSessionId == _activeSessionId) {
      _scrollToBottom();
    }

    int toolCallCount = 0;
    bool shouldContinue = true;

    try {
      while (shouldContinue && toolCallCount < 10) {
        final currentSession = _sessions[sessionIndex];
        final assistantMessageIndex = currentSession.messages.length;

        setState(() {
          _sessions[sessionIndex] = currentSession.copyWith(
            messages: [...currentSession.messages, const ChatMessage(role: MessageRole.assistant, text: '')],
          );
        });

        if (targetSessionId == _activeSessionId) {
          _scrollToBottom();
        }

        final List<ChatMessage> historyForApi = [];
        
        String systemPromptText = '';
        if (_agenticEnabled) {
          systemPromptText += "You have access to local Termux file system tools.\n"
              "If you need to use the local file system MCP server, output a single line: [MCP_REQUEST: {\"method\": \"...\", \"params\": {...}}] and stop generating.\n"
              "MCP methods available:\n"
              "- file_read: params {path: string}\n"
              "- file_write: params {path: string, content: string}\n"
              "- file_edit: params {path: string, start_line: int, end_line: int, replacement: string}\n"
              "- file_delete: params {path: string}\n"
              "- dir_list: params {path: string}\n"
              "- dir_create: params {path: string}\n"
              "- code_search: params {path: string, query: string}\n"
              "- file_search: params {path: string, pattern: string}\n"
              "- shell_exec: params {command: string, cwd: string (optional)}\n"
              "Once results are provided, continue your response.\n\n"
              "CRITICAL: Do NOT refuse to create or edit files. You are fully capable of doing this via MCP_REQUEST. Just output the tag.\n"
              "CRITICAL: NEVER use dangerous commands that will harm the device (like rm -rf /).\n";
              
          if (_customMcpUrl.isNotEmpty) {
            systemPromptText += "\nYou also have access to a Remote MCP HTTP Server at $_customMcpUrl.\n"
                "If you need to execute tools on the remote PC instead of Termux, add \"server\": \"remote\" to your parameters.\n";
          }
        }

        if (_searchSettings.enabled) {
          if (systemPromptText.isNotEmpty) systemPromptText += "\n\n";
          systemPromptText += "You ALSO have access to a web search tool.\n"
              "If you need to search the web, output a single line: [SEARCH_REQUEST: your search query] and stop generating.";
        }

        if (_deepResearchEnabled) {
          if (systemPromptText.isNotEmpty) systemPromptText += "\n\n";
          systemPromptText += "DEEP RESEARCH MODE ENABLED: For your first response, you MUST generate a comprehensive research plan using XML tags. Output ONLY the plan inside the tags and nothing else. Follow this exact format:\n"
            "<research_plan>\n"
            "  <phase1>Title of Phase 1: Detailed prompt/instructions for what you should accomplish in this phase</phase1>\n"
            "  <phase2>Title of Phase 2: Detailed prompt/instructions for what you should accomplish in this phase</phase2>\n"
            "  ...\n"
            "</research_plan>\n"
            "Limit the plan to a maximum of 15 phases.";
        }

        if (systemPromptText.isNotEmpty) {
          historyForApi.add(ChatMessage(role: MessageRole.system, text: systemPromptText));
        }

        historyForApi.addAll(_sessions[sessionIndex].messages.take(assistantMessageIndex));

        final stream = _chatClient.sendChatStream(
          provider: provider,
          settings: settings,
          model: activeModel,
          messages: historyForApi,
        );

        var fullText = '';
        var reasoningText = '';
        var isThinking = false;
        final updateStopwatch = Stopwatch()..start();

        await for (final chunk in stream) {
          if (!mounted) return;
          if (chunk.startsWith('[REASONING]')) {
            reasoningText += chunk.substring(11);
          } else {
            var textChunk = chunk;
            
            // Start of <think> or <reasoning> or <thought>
            if (!isThinking && (textChunk.contains('<think>') || textChunk.contains('<reasoning>') || textChunk.contains('<thought>'))) {
              final tag = textChunk.contains('<think>') ? '<think>' : textChunk.contains('<thought>') ? '<thought>' : '<reasoning>';
              final parts = textChunk.split(tag);
              fullText += parts[0];
              isThinking = true;
              textChunk = parts.length > 1 ? parts.sublist(1).join(tag) : '';
            }
            
            // End of </think> or </reasoning> or </thought>
            if (isThinking && (textChunk.contains('</think>') || textChunk.contains('</reasoning>') || textChunk.contains('</thought>'))) {
              final tag = textChunk.contains('</think>') ? '</think>' : textChunk.contains('</thought>') ? '</thought>' : '</reasoning>';
              final parts = textChunk.split(tag);
              reasoningText += parts[0];
              isThinking = false;
              textChunk = parts.length > 1 ? parts.sublist(1).join(tag) : '';
              fullText += textChunk;
              
              // We could potentially start thinking again in the same chunk? Unlikely but possible.
            } else if (isThinking) {
              reasoningText += textChunk;
            } else {
              fullText += textChunk;
            }
          }

          if (updateStopwatch.elapsedMilliseconds > 50) {
            setState(() {
              final msgs = List<ChatMessage>.from(_sessions[sessionIndex].messages);
              if (assistantMessageIndex < msgs.length) {
                msgs[assistantMessageIndex] = ChatMessage(
                  role: MessageRole.assistant,
                  text: fullText,
                  reasoning: reasoningText,
                );
                _sessions[sessionIndex] = _sessions[sessionIndex].copyWith(messages: msgs);
              }
            });
            updateStopwatch.reset();
            if (targetSessionId == _activeSessionId) {
              _scrollToBottom();
            }
          }
        }

        // Final state update after stream completes
        setState(() {
          final msgs = List<ChatMessage>.from(_sessions[sessionIndex].messages);
          if (assistantMessageIndex < msgs.length) {
            msgs[assistantMessageIndex] = ChatMessage(
              role: MessageRole.assistant,
              text: fullText,
              reasoning: reasoningText,
            );
            _sessions[sessionIndex] = _sessions[sessionIndex].copyWith(messages: msgs);
          }
        });
        if (targetSessionId == _activeSessionId) {
          _scrollToBottom();
        }

        final searchRegex = RegExp(r'\[SEARCH_REQUEST:\s*(.*?)\]', dotAll: true);
        final mcpRegex = RegExp(r'\[MCP_REQUEST:\s*(\{[\s\S]*?\})\s*\]');
        
        final searchMatch = searchRegex.firstMatch(fullText);
        final mcpMatch = _findMcpMatch(fullText);

        if (fullText.contains('<research_plan>')) {
          final planStart = fullText.indexOf('<research_plan>');
          final planEnd = fullText.indexOf('</research_plan>', planStart);
          if (planEnd != -1) {
            final planContent = fullText.substring(planStart + 15, planEnd).trim();
            final phaseRegex = RegExp(r'<phase(\d+)>(.*?)</phase\1>', dotAll: true);
            final matches = phaseRegex.allMatches(planContent);
            if (matches.isNotEmpty) {
              final List<Map<String, dynamic>> stepsList = [];
              for (final match in matches) {
                final phaseNum = int.tryParse(match.group(1) ?? '') ?? 0;
                final textContent = match.group(2)?.trim() ?? '';
                
                String title = 'Phase $phaseNum';
                String prompt = textContent;
                final separatorIndex = textContent.indexOf(RegExp(r'[:\-]'));
                if (separatorIndex != -1) {
                  title = textContent.substring(0, separatorIndex).trim();
                  prompt = textContent.substring(separatorIndex + 1).trim();
                }
                stepsList.add({
                  "title": title,
                  "prompt": prompt,
                  "status": "pending",
                  "content": ""
                });
              }
              
              final stateMap = {
                "status": "pending",
                "steps": stepsList
              };
              
              setState(() {
                final msgs = List<ChatMessage>.from(_sessions[sessionIndex].messages);
                msgs[assistantMessageIndex] = ChatMessage(
                  role: MessageRole.assistant,
                  text: fullText + '\n\n[RESEARCH_STATE: ${jsonEncode(stateMap)}]',
                  reasoning: reasoningText,
                );
                _sessions[sessionIndex] = _sessions[sessionIndex].copyWith(messages: msgs);
                _sendingSessionIds.remove(targetSessionId);
              });
              await _saveSessions();
              return;
            }
          }
        }
        
        if (toolCallCount >= 10) {
          shouldContinue = false;
          continue;
        }

        List<String> toolOutputs = [];
        bool executedTools = false;

        if (_searchSettings.enabled && searchMatch != null) {
          final searchMatches = searchRegex.allMatches(fullText);
          for (final match in searchMatches) {
            executedTools = true;
            final query = match.group(1)?.trim() ?? '';
            final searchResultRaw = await _chatClient.searchWeb(
              query,
              _searchSettings.provider,
              [_searchSettings.apiKey, ..._searchSettings.fallbackApiKeys],
              googleCx: _searchSettings.googleCx,
            );
            
            String searchResult = searchResultRaw;
            if (searchResult.length > 4000) {
              searchResult = searchResult.substring(0, 4000) + '\n\n...[truncated due to length]';
            }
            toolOutputs.add("Web Search results for '$query':\n\n$searchResult");
          }
        }

        if (_agenticEnabled && mcpMatch != null) {
          final mcpMatches = mcpRegex.allMatches(fullText);
          for (final match in mcpMatches) {
            executedTools = true;
            String jsonString = match.group(1)?.trim() ?? '';
            jsonString = jsonString.replaceAll(RegExp(r'^```json\s*'), '').replaceAll(RegExp(r'^```\s*'), '').replaceAll(RegExp(r'\s*```$'), '');
            
            String mcpEndpoint = 'http://127.0.0.1:8390/mcp';
            try {
              final parsed = jsonDecode(jsonString) as Map<String, dynamic>;
              final params = parsed['params'] as Map<String, dynamic>? ?? {};
              
              if (params['server'] == 'remote' && _customMcpUrl.isNotEmpty) {
                mcpEndpoint = _customMcpUrl;
                params.remove('server');
              }
              
              params['workspace_dir'] = _agenticWorkspace;
              parsed['params'] = params;
              jsonString = jsonEncode(parsed);
            } catch (_) {}

            String mcpResult = '';
            try {
              final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
              final request = await client.postUrl(Uri.parse(mcpEndpoint));
              request.headers.contentType = ContentType.json;
              
              final bytes = utf8.encode(jsonString);
              request.headers.contentLength = bytes.length;
              request.add(bytes);
              
              final response = await request.close();
              final body = await response.transform(utf8.decoder).join();
              mcpResult = body;
              if (mcpResult.length > 6000) {
                mcpResult = mcpResult.substring(0, 6000) + '\n\n...[truncated due to length]';
              }
            } catch (e) {
              mcpResult = '{"error": "$e"}';
            }
            toolOutputs.add("MCP Result:\n\n$mcpResult");
          }
        }

        if (executedTools) {
          toolCallCount++;
          final resultsMessage = ChatMessage(
            role: MessageRole.system,
            text: toolOutputs.join("\n\n---\n\n"),
          );

          setState(() {
            _sessions[sessionIndex] = _sessions[sessionIndex].copyWith(
              messages: [..._sessions[sessionIndex].messages, resultsMessage],
            );
          });

          if (targetSessionId == _activeSessionId) {
            _scrollToBottom();
          }
          await Future.delayed(const Duration(seconds: 2));
        } else {
          shouldContinue = false;
        }
      }
      await _saveSessions();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        final currentMessages = List<ChatMessage>.from(_sessions[sessionIndex].messages);
        if (currentMessages.isNotEmpty) {
          final lastIdx = currentMessages.length - 1;
          final currentText = currentMessages[lastIdx].text;
          currentMessages[lastIdx] = ChatMessage(
            role: MessageRole.assistant,
            text: currentText.isNotEmpty
                ? '$currentText\n\n[Error: $error]'
                : 'Request failed: $error',
            isError: true,
          );
          _sessions[sessionIndex] = _sessions[sessionIndex].copyWith(messages: currentMessages);
        }
      });
      await _saveSessions();
    } finally {
      if (mounted) {
        setState(() {
          _sendingSessionIds.remove(targetSessionId);
        });
        if (targetSessionId == _activeSessionId) {
          _scrollToBottom();
        }
      }
    }
  }

  Match? _findMcpMatch(String fullText) {
    final mcpStart = fullText.indexOf('[MCP_REQUEST:');
    if (mcpStart == -1) return null;
    
    final jsonStart = fullText.indexOf('{', mcpStart);
    if (jsonStart == -1) return null;
    
    final jsonEnd = _findMatchingBracket(fullText, jsonStart);
    if (jsonEnd == -1) return null;
    
    final fullMatchStr = fullText.substring(mcpStart, fullText.indexOf(']', jsonEnd) + 1);
    final jsonStr = fullText.substring(jsonStart, jsonEnd + 1);
    
    return RegExp(r'\[MCP_REQUEST:\s*(\{[\s\S]*?\})\s*\]').firstMatch('[MCP_REQUEST: $jsonStr]');
  }

  int _findMatchingBracket(String text, int startIndex) {
    int count = 0;
    bool inString = false;
    bool escape = false;
    
    for (int i = startIndex; i < text.length; i++) {
      final c = text[i];
      if (escape) {
        escape = false;
        continue;
      }
      if (c == '\\') {
        escape = true;
        continue;
      }
      if (c == '"') {
        inString = !inString;
        continue;
      }
      if (inString) continue;
      
      if (c == '{' || c == '[') count++;
      else if (c == '}' || c == ']') {
        count--;
        if (count == 0) return i;
      }
    }
    return -1;
  }

  String _getResearchFileName(String title) {
    final slug = title.toLowerCase()
        .replaceAll(RegExp(r'[^\w\s\-]'), '')
        .trim()
        .replaceAll(RegExp(r'[\s\-]+'), '_');
    return 'research_$slug.md';
  }

  void _startResearchLoop(int messageIndex) {
    final activeSession = _sessions.firstWhere((s) => s.id == _activeSessionId);
    final sessionIndex = _sessions.indexOf(activeSession);
    if (sessionIndex == -1) return;
    
    final message = activeSession.messages[messageIndex];
    if (!message.text.contains('[RESEARCH_STATE:')) return;
    
    final stateStr = message.text.substring(message.text.indexOf('[RESEARCH_STATE: ') + 17, message.text.lastIndexOf(']')).trim();
    try {
      final stateMap = jsonDecode(stateStr) as Map<String, dynamic>;
      stateMap['status'] = 'running';
      
      setState(() {
        _sendingSessionIds.add(_sessions[sessionIndex].id);
        final msgs = List<ChatMessage>.from(_sessions[sessionIndex].messages);
        msgs[messageIndex] = ChatMessage(
          role: MessageRole.assistant,
          text: message.text.replaceRange(
            message.text.indexOf('[RESEARCH_STATE:'), 
            message.text.lastIndexOf(']') + 1, 
            '[RESEARCH_STATE: ${jsonEncode(stateMap)}]'
          ),
          reasoning: message.reasoning,
        );
        _sessions[sessionIndex] = _sessions[sessionIndex].copyWith(messages: msgs);
      });

      _runResearchLoop(
        sessionIndex: sessionIndex,
        messageIndex: messageIndex,
        stateMap: stateMap,
        provider: _provider,
        settings: _activeSettings,
        model: _activeModel,
      );
    } catch (e) {
      debugPrint('Error parsing state map on start: $e');
    }
  }

  Future<void> _runResearchLoop({
    required int sessionIndex,
    required int messageIndex,
    required Map<String, dynamic> stateMap,
    required ProviderDefinition provider,
    required ProviderSettings settings,
    required String model,
  }) async {
    final steps = stateMap['steps'] as List;
    final fileName = _getResearchFileName(_sessions[sessionIndex].title);
    
    final systemPrompt = "You are an autonomous research agent.\n"
        "You have access to SEARCH_REQUEST (for web search) and MCP_REQUEST (for local file/command operations).\n"
        "Your output file is $fileName. Use MCP_REQUEST with method 'file_append' to append your phase findings directly to this file.\n"
        "For the current phase, perform thorough research:\n"
        "1. Conduct at least 3 to 5 different SEARCH_REQUEST calls with distinct search queries to gather comprehensive data from diverse sources.\n"
        "2. Analyze the search results and compile your findings.\n"
        "3. Format your report beautifully with clear headings, detailed paragraphs, tables, and Mermaid flowcharts where appropriate.\n"
        "4. You MUST list all source URL links at the end of your phase findings in a 'Sources' section.\n"
        "5. Write/append this structured markdown block to $fileName using the 'file_append' MCP tool.\n\n"
        "CRITICAL: If you need to use SEARCH_REQUEST or MCP_REQUEST, output the tag and stop generating immediately in that turn. Do not generate any text after the tag.\n"
        "When you are completely finished with the current phase and have successfully appended its findings to the file, output a single line: [STEP_COMPLETE]";
    
    // We maintain a single continuous conversation context for the entire research process
    List<ChatMessage> stepMessages = [
      ChatMessage(role: MessageRole.system, text: systemPrompt),
    ];
    
    for (int i = 0; i < steps.length; i++) {
      if (!mounted) return;
      steps[i]['status'] = 'running';
      setState(() {
        final msgs = List<ChatMessage>.from(_sessions[sessionIndex].messages);
        msgs[messageIndex] = ChatMessage(
          role: MessageRole.assistant,
          text: '[RESEARCH_STATE: ${jsonEncode(stateMap)}]',
        );
        _sessions[sessionIndex] = _sessions[sessionIndex].copyWith(messages: msgs);
      });

      final stepPrompt = "Research Phase ${i + 1}: ${steps[i]['title']}\nInstructions: ${steps[i]['prompt']}";
      stepMessages.add(ChatMessage(role: MessageRole.user, text: stepPrompt));

      String stepContent = '';
      int loopCount = 0;
      bool stepDone = false;

      while (!stepDone && loopCount < 15) {
        if (!mounted) return;
        loopCount++;
        
        try {
          String responseText = '';
          String reasoningText = '';
          var isThinking = false;
          
          final stream = _chatClient.sendChatStream(
            provider: provider,
            settings: settings,
            model: model,
            messages: stepMessages,
          );
          
          await for (final chunk in stream) {
            if (chunk.startsWith('[REASONING]')) {
              reasoningText += chunk.substring(11);
            } else {
              var textChunk = chunk;
              
              if (!isThinking && (textChunk.contains('<think>') || textChunk.contains('<reasoning>') || textChunk.contains('<thought>'))) {
                final tag = textChunk.contains('<think>') ? '<think>' : textChunk.contains('<thought>') ? '<thought>' : '<reasoning>';
                final parts = textChunk.split(tag);
                responseText += parts[0];
                isThinking = true;
                textChunk = parts.length > 1 ? parts.sublist(1).join(tag) : '';
              }
              
              if (isThinking && (textChunk.contains('</think>') || textChunk.contains('</reasoning>') || textChunk.contains('</thought>'))) {
                final tag = textChunk.contains('</think>') ? '</think>' : textChunk.contains('</thought>') ? '</thought>' : '</reasoning>';
                final parts = textChunk.split(tag);
                reasoningText += parts[0];
                isThinking = false;
                textChunk = parts.length > 1 ? parts.sublist(1).join(tag) : '';
                responseText += textChunk;
              } else if (isThinking) {
                reasoningText += textChunk;
              } else {
                responseText += textChunk;
              }
            }
          }
          
          stepMessages.add(ChatMessage(role: MessageRole.assistant, text: responseText, reasoning: reasoningText));

          final searchMatch = RegExp(r'\[SEARCH_REQUEST:\s*(.*?)\]', dotAll: true).firstMatch(responseText);
          final mcpMatch = _findMcpMatch(responseText);
          final completeMatch = RegExp(r'\[STEP_COMPLETE\]', dotAll: true).firstMatch(responseText);

          if (completeMatch != null) {
            final contentClean = responseText.replaceAll('[STEP_COMPLETE]', '').trim();
            stepContent = stepContent.isEmpty ? contentClean : '$stepContent\n\n$contentClean';
            stepDone = true;
          } else if (searchMatch != null) {
            final query = searchMatch.group(1)?.trim() ?? '';
            stepContent = stepContent.isEmpty ? '[SEARCH_REQUEST: $query]' : '$stepContent\n\n[SEARCH_REQUEST: $query]';
            steps[i]['content'] = stepContent;
            if (mounted) {
              setState(() {
                final msgs = List<ChatMessage>.from(_sessions[sessionIndex].messages);
                msgs[messageIndex] = ChatMessage(role: MessageRole.assistant, text: '[RESEARCH_STATE: ${jsonEncode(stateMap)}]');
                _sessions[sessionIndex] = _sessions[sessionIndex].copyWith(messages: msgs);
              });
            }
            final searchResultRaw = await _chatClient.searchWeb(
              query,
              _searchSettings.provider,
              [_searchSettings.apiKey, ..._searchSettings.fallbackApiKeys],
              googleCx: _searchSettings.googleCx,
            );
            String searchResult = searchResultRaw;
            if (searchResult.length > 4000) {
              searchResult = searchResult.substring(0, 4000) + '\n\n...[truncated]';
            }
            stepMessages.add(ChatMessage(role: MessageRole.user, text: "Search results:\n$searchResult"));
          } else if (mcpMatch != null) {
            String jsonString = mcpMatch.group(1)?.trim() ?? '';
            jsonString = jsonString.replaceAll(RegExp(r'^```json\s*'), '').replaceAll(RegExp(r'^```\s*'), '').replaceAll(RegExp(r'\s*```$'), '');
            
            stepContent = stepContent.isEmpty ? '[MCP_REQUEST: $jsonString]' : '$stepContent\n\n[MCP_REQUEST: $jsonString]';
            steps[i]['content'] = stepContent;
            if (mounted) {
              setState(() {
                final msgs = List<ChatMessage>.from(_sessions[sessionIndex].messages);
                msgs[messageIndex] = ChatMessage(role: MessageRole.assistant, text: '[RESEARCH_STATE: ${jsonEncode(stateMap)}]');
                _sessions[sessionIndex] = _sessions[sessionIndex].copyWith(messages: msgs);
              });
            }

            String mcpEndpoint = 'http://127.0.0.1:8390/mcp';
            try {
              final parsed = jsonDecode(jsonString) as Map<String, dynamic>;
              final params = parsed['params'] as Map<String, dynamic>? ?? {};
              if (params['server'] == 'remote' && _customMcpUrl.isNotEmpty) {
                mcpEndpoint = _customMcpUrl;
                params.remove('server');
              }
              params['workspace_dir'] = _agenticWorkspace;
              parsed['params'] = params;
              jsonString = jsonEncode(parsed);
            } catch (_) {}

            String mcpResult = '';
            try {
              final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
              final request = await client.postUrl(Uri.parse(mcpEndpoint));
              request.headers.contentType = ContentType.json;
              final bytes = utf8.encode(jsonString);
              request.headers.contentLength = bytes.length;
              request.add(bytes);
              final response = await request.close();
              final body = await response.transform(utf8.decoder).join();
              mcpResult = body;
              if (mcpResult.length > 4000) {
                mcpResult = mcpResult.substring(0, 4000) + '\n\n...[truncated]';
              }
            } catch (e) {
              mcpResult = '{"error": "$e"}';
            }
            stepMessages.add(ChatMessage(role: MessageRole.user, text: "MCP Result:\n$mcpResult"));
          } else {
            stepContent = stepContent.isEmpty ? responseText : '$stepContent\n\n$responseText';
            stepDone = true;
          }
          await Future.delayed(const Duration(seconds: 2));
        } catch (e) {
          stepContent = stepContent.isEmpty ? "Error during step: $e" : "$stepContent\n\nError during step: $e";
          stepDone = true;
        }
      }

      steps[i]['status'] = 'completed';
      steps[i]['content'] = stepContent;
      if (mounted) {
        setState(() {
          final msgs = List<ChatMessage>.from(_sessions[sessionIndex].messages);
          msgs[messageIndex] = ChatMessage(
            role: MessageRole.assistant,
            text: '[RESEARCH_STATE: ${jsonEncode(stateMap)}]',
          );
          _sessions[sessionIndex] = _sessions[sessionIndex].copyWith(messages: msgs);
        });
        await _saveSessions();
      }
    }

    stateMap['status'] = 'completed';
    if (mounted) {
      setState(() {
        final msgs = List<ChatMessage>.from(_sessions[sessionIndex].messages);
        msgs[messageIndex] = ChatMessage(
          role: MessageRole.assistant,
          text: '[RESEARCH_STATE: ${jsonEncode(stateMap)}]',
        );
        _sessions[sessionIndex] = _sessions[sessionIndex].copyWith(messages: msgs);
        _sendingSessionIds.remove(_sessions[sessionIndex].id);
      });
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
          searchSettings: _searchSettings,
          agenticEnabled: _agenticEnabled,
          deepResearchEnabled: _deepResearchEnabled,
          agenticWorkspace: _agenticWorkspace,
          customMcpUrl: _customMcpUrl,
          onSearchSettingsChanged: (nextSearchSettings) async {
            setState(() {
              _searchSettings = nextSearchSettings;
            });
            await _saveSettings();
          },
          onAgenticEnabledChanged: (val) async {
            setState(() {
              _agenticEnabled = val;
            });
            await _saveSettings();
          },
          onDeepResearchEnabledChanged: (val) async {
            setState(() {
              _deepResearchEnabled = val;
            });
            await _saveSettings();
          },
          onAgenticWorkspaceChanged: (val) async {
            setState(() {
              _agenticWorkspace = val;
            });
            await _saveSettings();
          },
          onCustomMcpUrlChanged: (val) async {
            setState(() {
              _customMcpUrl = val;
            });
            await _saveSettings();
          },
          onImageAttached: (base64Content) {
            setState(() {
              final sessionIndex = _sessions.indexWhere((s) => s.id == _activeSessionId);
              if (sessionIndex != -1) {
                final list = List<String>.from(_sessions[sessionIndex].attachedImagesBase64)..add(base64Content);
                _sessions[sessionIndex] = _sessions[sessionIndex].copyWith(attachedImagesBase64: list);
              }
            });
            _saveSessions();
          },
          onFileAttached: (file) {
            setState(() {
              final sessionIndex = _sessions.indexWhere((s) => s.id == _activeSessionId);
              if (sessionIndex != -1) {
                final list = List<AttachedFile>.from(_sessions[sessionIndex].attachedFiles)..add(file);
                _sessions[sessionIndex] = _sessions[sessionIndex].copyWith(attachedFiles: list);
              }
            });
            _saveSessions();
          },
          onProviderChanged: (newProviderId) async {
            final nextProvider = providerCatalog.firstWhere((p) => p.id == newProviderId);
            final nextSettings = _settings[newProviderId] ?? ProviderSettings.defaults(nextProvider);
            final nextModel = nextSettings.model.isNotEmpty ? nextSettings.model : nextProvider.models.first;
            setState(() {
              _selectedProviderId = newProviderId;
              _settings[newProviderId] = nextSettings.copyWith(model: nextModel);
              
              final sessionIndex = _sessions.indexWhere((s) => s.id == _activeSessionId);
              if (sessionIndex != -1) {
                _sessions[sessionIndex] = _sessions[sessionIndex].copyWith(
                  providerId: newProviderId,
                  model: nextModel,
                  maxTokens: nextSettings.maxTokens,
                );
              }
            });
            await _saveSettings();
            await _saveSessions();
          },
          onModelChanged: (newModel) async {
            setState(() {
              final currentProv = _selectedProviderId;
              final currentSettings = _settings[currentProv] ?? ProviderSettings.defaults(_provider);
              _settings[currentProv] = currentSettings.copyWith(model: newModel);
              
              final sessionIndex = _sessions.indexWhere((s) => s.id == _activeSessionId);
              if (sessionIndex != -1) {
                _sessions[sessionIndex] = _sessions[sessionIndex].copyWith(
                  model: newModel,
                );
              }
            });
            await _saveSettings();
            await _saveSessions();
          },
          onMaxTokensChanged: (newMaxTokens) async {
            setState(() {
              final currentProv = _selectedProviderId;
              final currentSettings = _settings[currentProv] ?? ProviderSettings.defaults(_provider);
              _settings[currentProv] = currentSettings.copyWith(maxTokens: newMaxTokens);
              
              final sessionIndex = _sessions.indexWhere((s) => s.id == _activeSessionId);
              if (sessionIndex != -1) {
                _sessions[sessionIndex] = _sessions[sessionIndex].copyWith(
                  maxTokens: newMaxTokens,
                );
              }
            });
            await _saveSettings();
            await _saveSessions();
          },
          onReasoningEnabledChanged: (enabled) async {
            setState(() {
              final currentProv = _selectedProviderId;
              final currentSettings = _settings[currentProv] ?? ProviderSettings.defaults(_provider);
              _settings[currentProv] = currentSettings.copyWith(reasoningEnabled: enabled);
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

  void _removeImage(int index) {
    setState(() {
      final sessionIndex = _sessions.indexWhere((s) => s.id == _activeSessionId);
      if (sessionIndex != -1) {
        final list = List<String>.from(_sessions[sessionIndex].attachedImagesBase64);
        if (index >= 0 && index < list.length) {
          list.removeAt(index);
          _sessions[sessionIndex] = _sessions[sessionIndex].copyWith(attachedImagesBase64: list);
        }
      }
    });
    _saveSessions();
  }

  void _removeFile(int index) {
    setState(() {
      final sessionIndex = _sessions.indexWhere((s) => s.id == _activeSessionId);
      if (sessionIndex != -1) {
        final list = List<AttachedFile>.from(_sessions[sessionIndex].attachedFiles);
        if (index >= 0 && index < list.length) {
          list.removeAt(index);
          _sessions[sessionIndex] = _sessions[sessionIndex].copyWith(attachedFiles: list);
        }
      }
    });
    _saveSessions();
  }

  void _editUserMessage(int index) {
    setState(() {
      final sessionIndex = _sessions.indexWhere((s) => s.id == _activeSessionId);
      if (sessionIndex != -1) {
        final session = _sessions[sessionIndex];
        final messages = List<ChatMessage>.from(session.messages);
        if (index >= 0 && index < messages.length) {
          final targetMessage = messages[index];
          _messageController.text = targetMessage.text;
          // Clear target message and all subsequent messages
          messages.removeRange(index, messages.length);
          _sessions[sessionIndex] = session.copyWith(messages: messages);
        }
      }
    });
    _saveSessions();
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

  ChatSession get _activeSession {
    if (_sessions.isEmpty) {
      _initDefaultSession();
    }
    return _sessions.firstWhere(
      (s) => s.id == _activeSessionId,
      orElse: () => _sessions.first,
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 840;
    final activeSession = _activeSession;
    
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
                isSending: _sendingSessionIds.contains(_activeSessionId),
                onOpenProvider: () => _openProviderSheet(_selectedProviderId),
                onOpenModel: _openModelSheet,
                onSend: _sendMessage,
                onPlusPressed: _openPlusBottomSheet,
                attachedImages: activeSession.attachedImagesBase64,
                onRemoveImage: _removeImage,
                attachedFiles: activeSession.attachedFiles,
                onRemoveFile: _removeFile,
                onEditUserMessage: _editUserMessage,
                agenticWorkspace: _agenticWorkspace,
                deepResearchEnabled: _deepResearchEnabled,
                onStartResearch: _startResearchLoop,
                fileName: _getResearchFileName(activeSession.title),
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
    required this.attachedImages,
    required this.onRemoveImage,
    required this.attachedFiles,
    required this.onRemoveFile,
    required this.onEditUserMessage,
    required this.agenticWorkspace,
    required this.deepResearchEnabled,
    required this.onStartResearch,
    required this.fileName,
    super.key,
  });

  final ProviderDefinition provider;
  final ProviderSettings settings;
  final String model;
  final List<ChatMessage> messages;
  final TextEditingController messageController;
  final ScrollController scrollController;
  final bool isSending;
  final String fileName;
  final VoidCallback onOpenProvider;
  final VoidCallback onOpenModel;
  final VoidCallback onSend;
  final VoidCallback onPlusPressed;
  final List<String> attachedImages;
  final ValueChanged<int> onRemoveImage;
  final List<AttachedFile> attachedFiles;
  final ValueChanged<int> onRemoveFile;
  final ValueChanged<int> onEditUserMessage;
  final String agenticWorkspace;
  final bool deepResearchEnabled;
  final ValueChanged<int> onStartResearch;

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
              itemCount: messages.length,
              itemBuilder: (context, index) {
                AvatarAnimationState state = AvatarAnimationState.idle;
                if (isSending && index == messages.length - 1) {
                  final msg = messages[index];
                  if (msg.text.contains('[MCP_REQUEST:')) {
                    state = AvatarAnimationState.mcp;
                  } else if (msg.text.contains('[SEARCH_REQUEST:')) {
                    state = AvatarAnimationState.searching;
                  } else if ((msg.reasoning?.isNotEmpty ?? false) && msg.text.isEmpty) {
                    state = AvatarAnimationState.reasoning;
                  } else {
                    state = AvatarAnimationState.typing;
                  }
                }
                return MessageBubble(
                  message: messages[index],
                  index: index,
                  providerShortName: provider.shortName,
                  providerName: provider.name,
                  reasoningEnabled: settings.reasoningEnabled,
                  animationState: state,
                  agenticWorkspace: agenticWorkspace,
                  fileName: fileName,
                  onEditUserMessage: () => onEditUserMessage(index),
                  onStartResearch: () => onStartResearch(index),
                );
              },
            ),
          ),
          Composer(
            controller: messageController,
            isSending: isSending,
            onSend: onSend,
            onPlusPressed: onPlusPressed,
            attachedImages: attachedImages,
            onRemoveImage: onRemoveImage,
            attachedFiles: attachedFiles,
            onRemoveFile: onRemoveFile,
            deepResearchEnabled: deepResearchEnabled,
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

class ThoughtBlock extends StatefulWidget {
  const ThoughtBlock({required this.thought, super.key});
  final String thought;

  @override
  State<ThoughtBlock> createState() => _ThoughtBlockState();
}

class _ThoughtBlockState extends State<ThoughtBlock> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F2E8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFDCCBB8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  const Icon(Icons.psychology_outlined, size: 18, color: Color(0xFF7B4E2E)),
                  const SizedBox(width: 8),
                  const Text(
                    'Thought Process',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF6C5946),
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    _expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    size: 18,
                    color: const Color(0xFF6C5946),
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: Text(
                widget.thought,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontStyle: FontStyle.italic,
                  color: Color(0xFF5C4E40),
                  height: 1.4,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class McpToolBlock extends StatefulWidget {
  const McpToolBlock({required this.mcpJson, super.key});
  final String mcpJson;

  @override
  State<McpToolBlock> createState() => _McpToolBlockState();
}

class _McpToolBlockState extends State<McpToolBlock> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    String method = 'Unknown Tool';
    String formattedJson = widget.mcpJson;
    try {
      final decoded = jsonDecode(widget.mcpJson);
      if (decoded['method'] != null) {
        method = decoded['method'].toString();
      }
      formattedJson = const JsonEncoder.withIndent('  ').convert(decoded);
    } catch (_) {}

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F5FA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD0E0F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  const Icon(Icons.build_circle_outlined, size: 18, color: Color(0xFF2B6CB0)),
                  const SizedBox(width: 8),
                  Text(
                    'Agentic Tool Use: $method',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2B6CB0),
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    _expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    size: 18,
                    color: const Color(0xFF2B6CB0),
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: SelectableText(
                formattedJson,
                style: const TextStyle(
                  fontSize: 12.0,
                  fontFamily: 'monospace',
                  color: Color(0xFF4A5568),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class CodeBlockWidget extends StatelessWidget {
  const CodeBlockWidget({
    required this.code,
    required this.language,
    required this.onSave,
    super.key,
  });

  final String code;
  final String language;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 6,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: const BoxDecoration(
              color: Color(0xFF2D2D2D),
              borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                const Icon(Icons.code, size: 16, color: Color(0xFFDCCBB8)),
                const SizedBox(width: 8),
                Text(
                  language.toUpperCase(),
                  style: const TextStyle(
                    color: Color(0xFFDCCBB8),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.1,
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Copy code',
                  icon: const Icon(Icons.copy_all_outlined, size: 18, color: Color(0xFFDCCBB8)),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: code));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Code copied to clipboard')),
                    );
                  },
                ),
                IconButton(
                  tooltip: 'Save file',
                  icon: const Icon(Icons.download_rounded, size: 18, color: Color(0xFFDCCBB8)),
                  onPressed: onSave,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: SelectableText(
              code,
              style: GoogleFonts.jetBrainsMono(
                color: const Color(0xFFE5C07B),
                fontSize: 13,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String getExtension(String lang) {
  switch (lang.toLowerCase()) {
    case 'python': case 'py': return 'py';
    case 'dart': return 'dart';
    case 'javascript': case 'js': return 'js';
    case 'typescript': case 'ts': return 'ts';
    case 'html': return 'html';
    case 'css': return 'css';
    case 'json': return 'json';
    case 'bash': case 'sh': case 'shell': return 'sh';
    case 'rust': case 'rs': return 'rs';
    case 'go': return 'go';
    case 'cpp': case 'c++': return 'cpp';
    case 'c': return 'c';
    case 'java': return 'java';
    case 'kotlin': case 'kt': return 'kt';
    default: return 'txt';
  }
}

Future<void> _saveCodeBlock(BuildContext context, String code, String language) async {
  try {
    final ext = getExtension(language);
    final dir = Directory('/data/data/com.termux/files/home/downloads');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final filename = 'code_${DateTime.now().millisecondsSinceEpoch}.$ext';
    final file = File('${dir.path}/$filename');
    await file.writeAsString(code);
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('File saved: downloads/$filename'),
        backgroundColor: const Color(0xFF36764D),
      ),
    );
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Failed to save file: $e'),
        backgroundColor: const Color(0xFF9B4D39),
      ),
    );
  }
}

class ContentBlock {
  final bool isCode;
  final String content;
  final String language;

  ContentBlock({required this.isCode, required this.content, this.language = ''});
}

List<ContentBlock> parseContentBlocks(String text) {
  final blocks = <ContentBlock>[];
  final parts = text.split('```');
  
  for (var i = 0; i < parts.length; i++) {
    final part = parts[i];
    if (i % 2 == 0) {
      if (part.isNotEmpty) {
        blocks.add(ContentBlock(isCode: false, content: part));
      }
    } else {
      final lines = part.split('\n');
      final language = lines.first.trim();
      final codeContent = lines.skip(1).join('\n');
      blocks.add(ContentBlock(isCode: true, content: codeContent, language: language));
    }
  }
  return blocks;
}

String convertLatexToUnicode(String text) {
  var formatted = text;

  final replacements = {
    r'\alpha': 'α',
    r'\beta': 'β',
    r'\gamma': 'γ',
    r'\delta': 'δ',
    r'\epsilon': 'ε',
    r'\zeta': 'ζ',
    r'\eta': 'η',
    r'\theta': 'θ',
    r'\iota': 'ι',
    r'\kappa': 'κ',
    r'\lambda': 'λ',
    r'\mu': 'μ',
    r'\nu': 'ν',
    r'\xi': 'ξ',
    r'\pi': 'π',
    r'\rho': 'ρ',
    r'\sigma': 'σ',
    r'\tau': 'τ',
    r'\upsilon': 'υ',
    r'\phi': 'φ',
    r'\chi': 'χ',
    r'\psi': 'ψ',
    r'\omega': 'ω',
    r'\Gamma': 'Γ',
    r'\Delta': 'Δ',
    r'\Theta': 'Θ',
    r'\Lambda': 'Λ',
    r'\Xi': 'Ξ',
    r'\Pi': 'Π',
    r'\Sigma': 'Σ',
    r'\Phi': 'Φ',
    r'\Psi': 'Ψ',
    r'\Omega': 'Ω',
    r'\pm': '±',
    r'\times': '×',
    r'\div': '÷',
    r'\cdot': '·',
    r'\le': '≤',
    r'\ge': '≥',
    r'\ne': '≠',
    r'\approx': '≈',
    r'\in': '∈',
    r'\notin': '∉',
    r'\ni': '∋',
    r'\propto': '∝',
    r'\infty': '∞',
    r'\partial': '∂',
    r'\nabla': '∇',
    r'\sum': '∑',
    r'\prod': '∏',
    r'\coprod': '∐',
    r'\int': '∫',
    r'\iint': '∬',
    r'\iiint': '∌',
    r'\oint': '∮',
    r'\therefore': '∴',
    r'\because': '∌',
    r'\forall': '∀',
    r'\exists': '∃',
    r'\empty': '∅',
    r'\emptyset': '∅',
    r'\cap': '∩',
    r'\cup': '∪',
    r'\subset': '⊂',
    r'\supset': '⊃',
    r'\subseteq': '⊆',
    r'\supseteq': '⊇',
    r'\leftrightarrow': '↔',
    r'\Leftarrow': '⇐',
    r'\Rightarrow': '⇒',
    r'\Leftrightarrow': '⇔',
    r'\to': '→',
    r'\rightarrow': '→',
    r'\gets': '←',
    r'\leftarrow': '←',
    r'\uparrow': '↑',
    r'\downarrow': '↓',
    r'\neq': '≠',
    r'\leq': '≤',
    r'\geq': '≥',
  };

  final sqrtRegex = RegExp(r'\\sqrt\s*\{\s*(.*?)\s*\}', dotAll: true);
  formatted = formatted.replaceAllMapped(sqrtRegex, (match) {
    final inside = match.group(1) ?? '';
    return '√($inside)';
  });

  final fracRegex = RegExp(r'\\frac\s*\{\s*(.*?)\s*\}\s*\{\s*(.*?)\s*\}', dotAll: true);
  formatted = formatted.replaceAllMapped(fracRegex, (match) {
    final num = match.group(1) ?? '';
    final den = match.group(2) ?? '';
    return '($num)/($den)';
  });

  formatted = formatted.replaceAll(r'\left(', '(');
  formatted = formatted.replaceAll(r'\right)', ')');
  formatted = formatted.replaceAll(r'\left[', '[');
  formatted = formatted.replaceAll(r'\right]', ']');
  formatted = formatted.replaceAll(r'\left\{', '{');
  formatted = formatted.replaceAll(r'\right\}', '}');
  formatted = formatted.replaceAll(r'\langle', '⟨');
  formatted = formatted.replaceAll(r'\rangle', '⟩');

  replacements.forEach((key, val) {
    formatted = formatted.replaceAll(key, val);
  });

  final superscriptMap = {
    '0': '⁰', '1': '¹', '2': '²', '3': '³', '4': '⁴',
    '5': '⁵', '6': '⁶', '7': '⁷', '8': '⁸', '9': '⁹',
    '+': '⁺', '-': '⁻', '=': '⁼', '(': '⁽', ')': '⁾',
    'n': 'ⁿ', 'i': 'ⁱ', 'x': 'ˣ', 'y': 'ʸ'
  };
  final superRegex = RegExp(r'\^([0-9a-nixy\+\-\=\(\)])');
  formatted = formatted.replaceAllMapped(superRegex, (match) {
    final char = match.group(1) ?? '';
    return superscriptMap[char] ?? '^$char';
  });

  final subscriptMap = {
    '0': '₀', '1': '₁', '2': '₂', '3': '₃', '4': '₄',
    '5': '₅', '6': '₆', '7': '₇', '8': '₈', '9': '₉',
    '+': '₊', '-': '₋', '=': '₌', '(': '₍', ')': '₎',
    'x': 'ₓ', 'y': 'y', 'i': 'ᵢ', 'j': 'ⱼ'
  };
  final subRegex = RegExp(r'_([0-9\+\-\=\(\)xyij])');
  formatted = formatted.replaceAllMapped(subRegex, (match) {
    final char = match.group(1) ?? '';
    return subscriptMap[char] ?? '_$char';
  });

  formatted = formatted.replaceAllMapped(RegExp(r'\\text\s*\{\s*(.*?)\s*\}'), (m) => m.group(1) ?? '');

  return formatted;
}

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    required this.message,
    required this.index,
    required this.providerShortName,
    required this.providerName,
    required this.reasoningEnabled,
    required this.onEditUserMessage,
    required this.agenticWorkspace,
    required this.fileName,
    this.animationState = AvatarAnimationState.idle,
    this.onStartResearch,
    super.key,
  });

  final ChatMessage message;
  final int index;
  final String providerShortName;
  final String providerName;
  final bool reasoningEnabled;
  final String agenticWorkspace;
  final String fileName;
  final AvatarAnimationState animationState;
  final VoidCallback onEditUserMessage;
  final VoidCallback? onStartResearch;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == MessageRole.user;

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
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (isUser) ...[
                  const Icon(Icons.person_outline, size: 16, color: Color(0xFF7B4E2E)),
                  const SizedBox(width: 6),
                  const Text(
                    'You',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: Color(0xFF7B4E2E),
                    ),
                  ),
                ] else ...[
                  ProviderAvatar(label: providerShortName, small: true, animationState: animationState),
                  const SizedBox(width: 8),
                  Text(
                    providerName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: Color(0xFF2D241C),
                    ),
                  ),
                ],
                const Spacer(),
                IconButton(
                  tooltip: 'Copy text',
                  icon: const Icon(Icons.content_copy_rounded, size: 14, color: Color(0xFF6C5946)),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: message.text));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Message copied to clipboard')),
                    );
                  },
                ),
                if (isUser)
                  IconButton(
                    tooltip: 'Edit message',
                    icon: const Icon(Icons.edit_outlined, size: 14, color: Color(0xFF6C5946)),
                    onPressed: onEditUserMessage,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (message.images.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: message.images.map((img) {
                    return Container(
                      width: 140,
                      height: 140,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFDCCBB8)),
                        image: DecorationImage(
                          image: MemoryImage(base64Decode(img)),
                          fit: BoxFit.cover,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            if (message.role == MessageRole.system)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF7F4EF),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE7D8C4)),
                ),
                child: ExpansionTile(
                  title: Text(
                    message.text.split('\n').first,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF7B4E2E),
                    ),
                  ),
                  leading: const Icon(Icons.table_rows_outlined, color: Color(0xFF7B4E2E), size: 18),
                  collapsedBackgroundColor: Colors.transparent,
                  backgroundColor: Colors.transparent,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: MarkdownBody(
                          data: message.text,
                          selectable: true,
                          styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)),
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else if (isUser)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFDF9),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE7D8C4)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (message.files.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: message.files.map((f) => Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF0EBE1),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: const Color(0xFFDCCBB8)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.insert_drive_file, size: 13, color: Color(0xFF7B4E2E)),
                                const SizedBox(width: 5),
                                Text(
                                  f.name,
                                  style: const TextStyle(fontSize: 11.5, color: Color(0xFF4A3424), fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          )).toList(),
                        ),
                      ),
                    SelectableText(
                      message.text,
                      style: const TextStyle(
                        height: 1.45,
                        color: Color(0xFF2D241C),
                        fontSize: 15.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              )
            else ...[
              if (message.reasoning.isNotEmpty && reasoningEnabled)
                ThoughtBlock(thought: message.reasoning),
              if (message.text.startsWith('[RESEARCH_STATE:'))
                Builder(builder: (context) {
                  try {
                    final startIndex = message.text.indexOf('[RESEARCH_STATE:');
                    final jsonStr = message.text.substring(startIndex + 16, message.text.lastIndexOf(']')).trim();
                    final stateMap = jsonDecode(jsonStr) as Map<String, dynamic>;
                    return ResearchPlanWidget(
                      stateMap: stateMap,
                      workspaceDir: agenticWorkspace,
                      fileName: fileName,
                      onStartResearch: onStartResearch,
                    );
                  } catch (_) {
                    return const Text('Error rendering research state', style: TextStyle(color: Colors.red));
                  }
                })
              else if (message.text.startsWith('[SEARCH_REQUEST:'))
                Builder(builder: (context) {
                  final query = message.text
                      .replaceFirst('[SEARCH_REQUEST:', '')
                      .replaceFirst(']', '')
                      .trim();
                  return Container(
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0F5FA),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFD0E0F0)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.search, color: Color(0xFF2B6CB0), size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Tool Use: Searched the web for "$query"',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF2B6CB0),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                })
              else if (message.text.startsWith('[MCP_REQUEST:'))
                Builder(builder: (context) {
                  final jsonStr = message.text
                      .replaceFirst('[MCP_REQUEST:', '')
                      .replaceFirst(RegExp(r'\]$'), '')
                      .trim();
                  return McpToolBlock(mcpJson: jsonStr);
                })
              else
                ...parseContentBlocks(message.text).map((block) {
                  if (block.isCode) {
                    if (block.language.toLowerCase() == 'math') {
                      return Container(
                        width: double.infinity,
                        margin: const EdgeInsets.symmetric(vertical: 8),
                        padding: const EdgeInsets.all(12),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFFCF6),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFE7D8C4)),
                        ),
                        child: SelectableText(
                          convertLatexToUnicode(block.content),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF2D241C),
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      );
                    }
                    if (block.language.toLowerCase() == 'mermaid') {
                      return MermaidDiagramWidget(code: block.content);
                    }
                    return CodeBlockWidget(
                      code: block.content,
                      language: block.language,
                      onSave: () => _saveCodeBlock(context, block.content, block.language),
                    );
                  } else {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6.0),
                      child: MarkdownBody(
                        data: formatMathText(convertLatexToUnicode(block.content)),
                        selectable: true,
                        styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                          p: const TextStyle(
                            height: 1.48,
                            color: Color(0xFF1E1E1E),
                            fontSize: 15.5,
                            fontWeight: FontWeight.w400,
                          ),
                          h1: const TextStyle(color: Color(0xFF2D241C), fontSize: 20, fontWeight: FontWeight.bold),
                          h2: const TextStyle(color: Color(0xFF2D241C), fontSize: 18, fontWeight: FontWeight.bold),
                          h3: const TextStyle(color: Color(0xFF2D241C), fontSize: 16, fontWeight: FontWeight.bold),
                          listBullet: const TextStyle(color: Color(0xFF7B4E2E), fontSize: 15.5),
                          tableBorder: TableBorder.all(color: const Color(0xFFDCCBB8), width: 1),
                          tableBody: const TextStyle(color: Color(0xFF1E1E1E), fontSize: 14),
                          tableHead: const TextStyle(color: Color(0xFF2D241C), fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                      ),
                    );
                  }
                }),
            ],
            const SizedBox(height: 4),
            const Divider(color: Color(0xFFE7D8C4), height: 1),
          ],
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
        margin: const EdgeInsets.symmetric(vertical: 7, horizontal: 14),
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
    required this.attachedImages,
    required this.onRemoveImage,
    required this.attachedFiles,
    required this.onRemoveFile,
    required this.deepResearchEnabled,
    super.key,
  });

  final TextEditingController controller;
  final bool isSending;
  final VoidCallback onSend;
  final VoidCallback onPlusPressed;
  final List<String> attachedImages;
  final ValueChanged<int> onRemoveImage;
  final List<AttachedFile> attachedFiles;
  final ValueChanged<int> onRemoveFile;
  final bool deepResearchEnabled;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (attachedFiles.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: SizedBox(
                height: 36,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: attachedFiles.length,
                  itemBuilder: (context, idx) {
                    final file = attachedFiles[idx];
                    return Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0EBE1),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFFDCCBB8)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.insert_drive_file, size: 14, color: Color(0xFF7B4E2E)),
                          const SizedBox(width: 6),
                          Text(
                            file.name,
                            style: const TextStyle(fontSize: 12, color: Color(0xFF4A3424), fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () => onRemoveFile(idx),
                            child: const Icon(Icons.close, size: 14, color: Color(0xFF7B4E2E)),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          if (attachedImages.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: SizedBox(
                height: 60,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: attachedImages.length,
                  itemBuilder: (context, idx) {
                    return Stack(
                      children: [
                        Container(
                          margin: const EdgeInsets.only(right: 8),
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFDCCBB8)),
                            image: DecorationImage(
                              image: MemoryImage(base64Decode(attachedImages[idx])),
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        Positioned(
                          right: 0,
                          top: 0,
                          child: GestureDetector(
                            onTap: () => onRemoveImage(idx),
                            child: const CircleAvatar(
                              radius: 8,
                              backgroundColor: Colors.black54,
                              child: Icon(Icons.close, size: 10, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          Container(
            constraints: const BoxConstraints(maxWidth: 920),
            padding: const EdgeInsets.fromLTRB(10, 10, 8, 10),
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
                GestureDetector(
                  onTap: onPlusPressed,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 2, right: 8),
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFFFFF8EA),
                      border: Border.all(color: const Color(0xFFD8B98D), width: 1.5),
                    ),
                    child: const Icon(
                      Icons.add,
                      color: Color(0xFF7B4E2E),
                      size: 20,
                    ),
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: controller,
                    minLines: 1,
                    maxLines: 6,
                    textInputAction: TextInputAction.newline,
                    decoration: InputDecoration(
                      hintText: deepResearchEnabled ? 'Deep Research Mode is ON...' : 'Message any provider...',
                      border: InputBorder.none,
                      isDense: true,
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
        ],
      ),
    );
  }
}

bool modelHasVision(String modelName) {
  if (ChatClient.modelsWithVision.contains(modelName)) return true;

  final lower = modelName.toLowerCase();
  if (lower.contains('deepseek-r1') || lower.contains('llama-3.3')) {
    return false; // Specifically disable vision for these large language-only models if they accidentally match
  }
  return lower.contains('vision') ||
      lower.contains('gpt-4o') ||
      lower.contains('gpt-4-turbo') ||
      lower.contains('claude-3') ||
      lower.contains('gemini-1.5') ||
      lower.contains('gemini-2.0') ||
      lower.contains('gemini-2.5') ||
      lower.contains('pixtral') ||
      lower.contains('llava') ||
      lower.contains('qwen-vl') ||
      lower.contains('llama-3.2-11b') ||
      lower.contains('llama-3.2-90b');
}

class MediaAndModelSheet extends StatefulWidget {
  const MediaAndModelSheet({
    required this.provider,
    required this.settings,
    required this.cachedModels,
    required this.searchSettings,
    required this.agenticEnabled,
    required this.deepResearchEnabled,
    required this.agenticWorkspace,
    required this.customMcpUrl,
    required this.onSearchSettingsChanged,
    required this.onAgenticEnabledChanged,
    required this.onDeepResearchEnabledChanged,
    required this.onAgenticWorkspaceChanged,
    required this.onCustomMcpUrlChanged,
    required this.onImageAttached,
    required this.onFileAttached,

    required this.onProviderChanged,
    required this.onModelChanged,
    required this.onMaxTokensChanged,
    required this.onReasoningEnabledChanged,
    required this.onFetchModels,
    required this.onConfigureKey,
    super.key,
  });

  final ProviderDefinition provider;
  final ProviderSettings settings;
  final List<String> cachedModels;
  final SearchSettings searchSettings;
  final bool agenticEnabled;
  final bool deepResearchEnabled;
  final String agenticWorkspace;
  final String customMcpUrl;
  final ValueChanged<SearchSettings> onSearchSettingsChanged;
  final ValueChanged<bool> onAgenticEnabledChanged;
  final ValueChanged<bool> onDeepResearchEnabledChanged;
  final ValueChanged<String> onAgenticWorkspaceChanged;
  final ValueChanged<String> onCustomMcpUrlChanged;
  final ValueChanged<String> onImageAttached;
  final ValueChanged<AttachedFile> onFileAttached;

  final ValueChanged<String> onProviderChanged;
  final ValueChanged<String> onModelChanged;
  final ValueChanged<int> onMaxTokensChanged;
  final ValueChanged<bool> onReasoningEnabledChanged;
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
  late bool _reasoningEnabled;
  late bool _searchEnabled;
  late bool _agenticEnabled;
  late bool _deepResearchEnabled;
  late String _searchProvider;
  late final TextEditingController _searchKeyController;
  late final TextEditingController _searchCxController;
  late final TextEditingController _agenticWorkspaceController;
  late final TextEditingController _customMcpUrlController;

  @override
  void initState() {
    super.initState();
    _maxTokens = widget.settings.maxTokens;
    _selectedProviderId = widget.provider.id;
    _selectedModel = widget.settings.model.isNotEmpty
        ? widget.settings.model
        : widget.provider.models.first;
    _reasoningEnabled = widget.settings.reasoningEnabled;
    _searchEnabled = widget.searchSettings.enabled;
    _agenticEnabled = widget.agenticEnabled;
    _deepResearchEnabled = widget.deepResearchEnabled;
    _searchProvider = widget.searchSettings.provider;
    final initialKeys = [
      widget.searchSettings.apiKey,
      ...widget.searchSettings.fallbackApiKeys
    ].where((k) => k.isNotEmpty).join(', ');
    _searchKeyController = TextEditingController(text: initialKeys);
    _searchCxController = TextEditingController(text: widget.searchSettings.googleCx);
    _agenticWorkspaceController = TextEditingController(text: widget.agenticWorkspace);
    _customMcpUrlController = TextEditingController(text: widget.customMcpUrl);
  }

  @override
  void dispose() {
    _searchKeyController.dispose();
    _searchCxController.dispose();
    _agenticWorkspaceController.dispose();
    _customMcpUrlController.dispose();
    super.dispose();
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

  Future<void> _pickImage() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );
      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        final bytes = await file.readAsBytes();
        final base64String = base64Encode(bytes);
        widget.onImageAttached(base64String);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Image attached successfully')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to pick image: $e')),
        );
      }
    }
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'txt', 'md', 'json', 'py', 'dart', 'js', 'html', 'css', 'yaml', 'yml'],
        allowMultiple: false,
      );
      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        final ext = result.files.single.extension?.toLowerCase();
        String text = '';
        
        if (ext == 'pdf') {
          final PdfDocument document = PdfDocument(inputBytes: await file.readAsBytes());
          text = PdfTextExtractor(document).extractText();
          document.dispose();
        } else {
          text = await file.readAsString();
        }
        
        widget.onFileAttached(AttachedFile(name: result.files.single.name, content: text));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Document attached successfully')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to read document: $e')),
        );
      }
    }
  }

  void _updateSearchSettings() {
    final rawKeyString = _searchKeyController.text.trim();
    final keys = rawKeyString.split(',')
        .map((k) => k.trim())
        .where((k) => k.isNotEmpty)
        .toList();
        
    widget.onSearchSettingsChanged(
      SearchSettings(
        enabled: _searchEnabled,
        provider: _searchProvider,
        apiKey: keys.isNotEmpty ? keys.first : '',
        fallbackApiKeys: keys.length > 1 ? keys.sublist(1) : const [],
        googleCx: _searchCxController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentProvider = providerCatalog.firstWhere((p) => p.id == _selectedProviderId);
    final models = widget.cachedModels.isNotEmpty ? widget.cachedModels : currentProvider.models;
    final visionEnabled = modelHasVision(_selectedModel);

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
      child: SingleChildScrollView(
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
              'Media Attachment',
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
                _buildMediaItem(
                  Icons.image_outlined,
                  'Photos',
                  isEnabled: visionEnabled,
                  onTap: () {
                    if (visionEnabled) {
                      _pickImage();
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Selected model does not support vision (image input).')),
                      );
                    }
                  },
                ),
                _buildMediaItem(
                  Icons.camera_alt_outlined,
                  'Camera',
                  isEnabled: visionEnabled,
                  onTap: () {
                    if (visionEnabled) {
                      _pickImage();
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Selected model does not support vision (image input).')),
                      );
                    }
                  },
                ),
                _buildMediaItem(
                  Icons.insert_drive_file_outlined,
                  'Document',
                  isEnabled: true,
                  onTap: _pickFile,
                ),
                _buildMediaItem(
                  Icons.mic_none_outlined,
                  'Audio',
                  isEnabled: false,
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Audio input is not supported yet.')),
                    );
                  },
                ),
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
            const SizedBox(height: 16),
            const Divider(color: Color(0xFFE7D8C4)),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'CoT Thinking / Reasoning',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2D241C),
                      ),
                    ),
                    Text(
                      'Allow models to think step-by-step',
                      style: TextStyle(
                        fontSize: 11,
                        color: Color(0xFF6C5946),
                      ),
                    ),
                  ],
                ),
                Switch(
                  value: _reasoningEnabled,
                  activeColor: const Color(0xFF7B4E2E),
                  onChanged: (val) {
                    setState(() => _reasoningEnabled = val);
                    widget.onReasoningEnabledChanged(val);
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(color: Color(0xFFE7D8C4)),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Agentic File Access',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2D241C),
                      ),
                    ),
                    Text(
                      'Let models read/write local files',
                      style: TextStyle(
                        fontSize: 11,
                        color: Color(0xFF6C5946),
                      ),
                    ),
                  ],
                ),
                Switch(
                  value: _agenticEnabled,
                  activeColor: const Color(0xFF6A1B9A),
                  onChanged: (val) {
                    setState(() => _agenticEnabled = val);
                    widget.onAgenticEnabledChanged(val);
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Deep Research Mode',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF6C5946)),
                ),
                Switch(
                  value: _deepResearchEnabled,
                  activeColor: const Color(0xFF7B4E2E),
                  onChanged: (val) {
                    setState(() {
                      _deepResearchEnabled = val;
                    });
                    widget.onDeepResearchEnabledChanged(val);
                  },
                ),
              ],
            ),
            if (_agenticEnabled) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _agenticWorkspaceController,
                decoration: const InputDecoration(
                  labelText: 'Workspace Directory Path',
                  labelStyle: TextStyle(color: Color(0xFF6C5946)),
                  border: OutlineInputBorder(),
                  hintText: 'e.g. /data/data/com.termux/files/home',
                ),
                onChanged: widget.onAgenticWorkspaceChanged,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _customMcpUrlController,
                decoration: const InputDecoration(
                  labelText: 'Custom MCP URL (Optional)',
                  labelStyle: TextStyle(color: Color(0xFF6C5946)),
                  border: OutlineInputBorder(),
                  hintText: 'e.g. http://192.168.1.10:8390/mcp',
                ),
                onChanged: widget.onCustomMcpUrlChanged,
              ),
            ],
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Agentic Web Search',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2D241C),
                      ),
                    ),
                    Text(
                      'Let models search the web if needed',
                      style: TextStyle(
                        fontSize: 11,
                        color: Color(0xFF6C5946),
                      ),
                    ),
                  ],
                ),
                Switch(
                  value: _searchEnabled,
                  activeColor: const Color(0xFF7B4E2E),
                  onChanged: (val) {
                    setState(() => _searchEnabled = val);
                    _updateSearchSettings();
                  },
                ),
              ],
            ),
            if (_searchEnabled) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _searchProvider,
                dropdownColor: const Color(0xFFFFFBF2),
                decoration: const InputDecoration(
                  labelText: 'Search API Provider',
                  labelStyle: TextStyle(color: Color(0xFF6C5946)),
                  border: OutlineInputBorder(),
                ),
                items: ['tavily', 'exa', 'firecrawl', 'google'].map((p) {
                  return DropdownMenuItem<String>(
                    value: p,
                    child: Text(p.toUpperCase()),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _searchProvider = val);
                    _updateSearchSettings();
                  }
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _searchKeyController,
                decoration: const InputDecoration(
                  labelText: 'Search API Key(s) (comma-separated for fallbacks)',
                  labelStyle: TextStyle(color: Color(0xFF6C5946)),
                  border: OutlineInputBorder(),
                  hintText: 'key1, key2, key3...',
                ),
                obscureText: true,
                onChanged: (_) => _updateSearchSettings(),
              ),
              if (_searchProvider == 'google') ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _searchCxController,
                  decoration: const InputDecoration(
                    labelText: 'Google Search Engine ID (CX)',
                    labelStyle: TextStyle(color: Color(0xFF6C5946)),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => _updateSearchSettings(),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMediaItem(IconData icon, String label, {required bool isEnabled, required VoidCallback onTap}) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: isEnabled ? 1.0 : 0.4,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 72,
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isEnabled ? Colors.white : const Color(0xFFF8F5F0),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isEnabled ? const Color(0xFFDCCBB8) : Colors.transparent,
              width: 1,
            ),
            boxShadow: isEnabled
                ? [
                    BoxShadow(
                      color: const Color(0xFF7B4E2E).withValues(alpha: 0.08),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    )
                  ]
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 26,
                color: isEnabled ? const Color(0xFF7B4E2E) : const Color(0xFFB0A496),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isEnabled ? const Color(0xFF2D241C) : const Color(0xFFB0A496),
                ),
              ),
            ],
          ),
        ),
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
  final List<TextEditingController> _fallbackControllers = [];
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
    for (final key in widget.settings.fallbackApiKeys) {
      if (key.trim().isNotEmpty) {
        _fallbackControllers.add(TextEditingController(text: key));
      }
    }
    _models = widget.cachedModels;
  }

  @override
  void dispose() {
    _keyController.dispose();
    _baseUrlController.dispose();
    _modelController.dispose();
    _maxTokensController.dispose();
    for (final c in _fallbackControllers) c.dispose();
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
          Row(
            children: [
              const Text('Fallback API Keys', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF3B3027))),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.add_circle, color: Color(0xFF7B4E2E)),
                onPressed: () {
                  setState(() {
                    _fallbackControllers.add(TextEditingController());
                  });
                },
              ),
            ],
          ),
          ..._fallbackControllers.asMap().entries.map((entry) {
            final idx = entry.key;
            final controller = entry.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: controller,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: 'Fallback Key ${idx + 1}',
                        prefixIcon: const Icon(Icons.vpn_key),
                        border: const OutlineInputBorder(),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                    onPressed: () {
                      setState(() {
                        _fallbackControllers[idx].dispose();
                        _fallbackControllers.removeAt(idx);
                      });
                    },
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 4),
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
                        fallbackApiKeys: _fallbackControllers
                            .map((c) => c.text.trim())
                            .where((e) => e.isNotEmpty)
                            .toList(),
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

enum AvatarAnimationState { idle, typing, reasoning, searching, mcp }

class ProviderAvatar extends StatefulWidget {
  const ProviderAvatar({
    required this.label,
    this.small = false,
    this.animationState = AvatarAnimationState.idle,
    super.key,
  });

  final String label;
  final bool small;
  final AvatarAnimationState animationState;

  @override
  State<ProviderAvatar> createState() => _ProviderAvatarState();
}

class _ProviderAvatarState extends State<ProviderAvatar> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    if (widget.animationState != AvatarAnimationState.idle) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant ProviderAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animationState != AvatarAnimationState.idle && oldWidget.animationState == AvatarAnimationState.idle) {
      _controller.repeat(reverse: true);
    } else if (widget.animationState == AvatarAnimationState.idle && oldWidget.animationState != AvatarAnimationState.idle) {
      _controller.stop();
      _controller.animateTo(0);
    } else if (widget.animationState != oldWidget.animationState) {
      // Just ensure it's still running, maybe change duration depending on state
      if (widget.animationState == AvatarAnimationState.searching || widget.animationState == AvatarAnimationState.mcp) {
        _controller.duration = const Duration(milliseconds: 800);
      } else if (widget.animationState == AvatarAnimationState.reasoning) {
        _controller.duration = const Duration(milliseconds: 2000);
      } else {
        _controller.duration = const Duration(milliseconds: 1200);
      }
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.small ? 24.0 : 38.0;
    
    final avatar = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      child: Image.asset('assets/icon_transparent.png', fit: BoxFit.cover, width: size, height: size),
    );

    if (widget.animationState == AvatarAnimationState.idle) return avatar;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        if (widget.animationState == AvatarAnimationState.typing) {
          // Subtle pulse
          return Transform.scale(
            scale: 0.85 + (_controller.value * 0.15),
            child: child,
          );
        } else if (widget.animationState == AvatarAnimationState.reasoning) {
          // Slow breathing/fade
          return Opacity(
            opacity: 0.4 + (_controller.value * 0.6),
            child: Transform.scale(
              scale: 0.9 + (_controller.value * 0.1),
              child: child,
            ),
          );
        } else if (widget.animationState == AvatarAnimationState.searching) {
          // Fast pulse + slight rotation
          return Transform.rotate(
            angle: _controller.value * 0.5 - 0.25,
            child: Transform.scale(
              scale: 0.8 + (_controller.value * 0.3),
              child: child,
            ),
          );
        } else if (widget.animationState == AvatarAnimationState.mcp) {
          // Bounce / aggressive scale for tool execution
          return Transform.translate(
            offset: Offset(0, -5 * _controller.value),
            child: Transform.scale(
              scale: 0.8 + (_controller.value * 0.3),
              child: child,
            ),
          );
        }
        return child!;
      },
      child: avatar,
    );
  }
}

class ChatClient {
  static final Set<String> modelsWithVision = {};

  Future<List<String>> fetchModels(
    ProviderDefinition provider,
    ProviderSettings settings,
  ) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    try {
      final uri = Uri.parse('${_baseUrl(provider, settings)}/models');
      final request = await client.getUrl(uri);
      _setHeaders(request, provider, settings, settings.apiKey, stream: false);
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
              if (item is Map) {
                final id = item['id']?.toString() ?? '';
                final arch = item['architecture'];
                if (arch is Map) {
                  final modality = arch['modality']?.toString().toLowerCase() ?? '';
                  if (modality.contains('image') || modality.contains('vision')) {
                    ChatClient.modelsWithVision.add(id);
                  }
                }
                return id;
              }
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
      final allKeys = [settings.apiKey, ...settings.fallbackApiKeys]
          .map((k) => k.trim())
          .where((k) => k.isNotEmpty)
          .toList();
      if (allKeys.isEmpty) allKeys.add('');

      for (int i = 0; i < allKeys.length; i++) {
        final currentKey = allKeys[i];
        
        try {
          final uri = Uri.parse('${_baseUrl(provider, settings)}/chat/completions');
          final request = await client.postUrl(uri);
          _setHeaders(request, provider, settings, currentKey, stream: false);
          request.headers.contentType = ContentType.json;

          final payload = <String, dynamic>{
            'model': model,
            'messages': messages
                .map((message) {
                  String finalText = message.text;
                  if (message.files.isNotEmpty) {
                    finalText += '\n\n';
                    for (final file in message.files) {
                      finalText += '--- File: ${file.name} ---\n${file.content}\n\n';
                    }
                  }

                  if (message.images.isNotEmpty) {
                    return {
                      'role': message.role.apiName,
                      'content': [
                        {'type': 'text', 'text': finalText},
                        ...message.images.map((img) => {
                              'type': 'image_url',
                              'image_url': {
                                'url': 'data:image/jpeg;base64,$img'
                              }
                            })
                      ]
                    };
                  }
                  return {
                    'role': message.role.apiName,
                    'content': finalText,
                  };
                })
                .toList(),
            'max_tokens': settings.maxTokens,
            'temperature': 1.0,
            'top_p': 0.95,
            'stream': false,
          };

          final payloadBytes = utf8.encode(jsonEncode(payload));
          request.headers.contentLength = payloadBytes.length;
          request.add(payloadBytes);
          final response = await request.close();
          final body = await response.transform(utf8.decoder).join();
          
          if (response.statusCode < 200 || response.statusCode >= 300) {
            throw HttpException('HTTP ${response.statusCode}: $body');
          }
          return _extractAnswer(jsonDecode(body));
        } catch (e) {
          final isRateLimitOrCredits = e.toString().contains('429') || e.toString().contains('402');
          if (!isRateLimitOrCredits || i == allKeys.length - 1) {
            rethrow;
          }
        }
      }
      throw const HttpException('Failed to send request with any provided API key');
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
      final allKeys = [settings.apiKey, ...settings.fallbackApiKeys]
          .map((k) => k.trim())
          .where((k) => k.isNotEmpty)
          .toList();
      if (allKeys.isEmpty) allKeys.add('');

      for (int i = 0; i < allKeys.length; i++) {
        final currentKey = allKeys[i];
        
        HttpClientResponse? response;
        try {
          final uri = Uri.parse('${_baseUrl(provider, settings)}/chat/completions');
          final request = await client.postUrl(uri);
          _setHeaders(request, provider, settings, currentKey, stream: true);
          request.headers.contentType = ContentType.json;

          final payload = <String, dynamic>{
            'model': model,
            'messages': messages
                .map((message) {
                  String finalText = message.text;
                  if (message.files.isNotEmpty) {
                    finalText += '\n\n';
                    for (final file in message.files) {
                      finalText += '--- File: ${file.name} ---\n${file.content}\n\n';
                    }
                  }

                  if (message.images.isNotEmpty) {
                    return {
                      'role': message.role.apiName,
                      'content': [
                        {'type': 'text', 'text': finalText},
                        ...message.images.map((img) => {
                              'type': 'image_url',
                              'image_url': {
                                'url': 'data:image/jpeg;base64,$img'
                              }
                            })
                      ]
                    };
                  }
                  return {
                    'role': message.role.apiName,
                    'content': finalText,
                  };
                })
                .toList(),
            'max_tokens': settings.maxTokens,
            'temperature': 1.0,
            'top_p': 0.95,
            'stream': true,
          };

          final payloadBytes = utf8.encode(jsonEncode(payload));
          request.headers.contentLength = payloadBytes.length;
          request.add(payloadBytes);
          response = await request.close();
          
          if (response.statusCode < 200 || response.statusCode >= 300) {
            final body = await response.transform(utf8.decoder).join();
            throw HttpException('HTTP ${response.statusCode}: $body');
          }
        } catch (e) {
          final isRateLimitOrCredits = e.toString().contains('429') || e.toString().contains('402');
          if (!isRateLimitOrCredits || i == allKeys.length - 1) {
            rethrow;
          }
          continue; // Try next key
        }

        // If we reach here, the response was successful
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
                  if (delta is Map) {
                    if (delta['reasoning_content'] != null) {
                      yield '[REASONING]${delta['reasoning_content']}';
                    } else if (delta['content'] != null) {
                      yield delta['content'].toString();
                    } else if (first['text'] != null) {
                      yield first['text'].toString();
                    }
                  }
                }
              }
            }
          } catch (_) {
          }
        }
      }
      break; // Successfully streamed, do not try next key
    }
    } finally {
      client.close(force: true);
    }
  }

  Future<String> searchWeb(
    String query,
    String provider,
    List<String> apiKeys, {
    String? googleCx,
  }) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final keys = apiKeys.where((k) => k.trim().isNotEmpty).toList();
      if (keys.isEmpty) keys.add('');

      for (int i = 0; i < keys.length; i++) {
        final currentKey = keys[i];
        try {
          if (provider == 'tavily') {
            final uri = Uri.parse('https://api.tavily.com/search');
            final request = await client.postUrl(uri);
            request.headers.contentType = ContentType.json;
            request.write(jsonEncode({
              'api_key': currentKey,
              'query': query,
              'max_results': 4,
            }));
            final response = await request.close();
            final body = await response.transform(utf8.decoder).join();
            if (response.statusCode < 200 || response.statusCode >= 300) {
              throw HttpException('HTTP ${response.statusCode}: $body');
            }
            final decoded = jsonDecode(body);
            if (decoded is Map && decoded['results'] is List) {
              final results = decoded['results'] as List;
              return results.map((r) => '- [${r['title']}](${r['url']}): ${r['content']}').join('\n\n');
            }
          } else if (provider == 'exa') {
            final uri = Uri.parse('https://api.exa.ai/search');
            final request = await client.postUrl(uri);
            request.headers.set('x-api-key', currentKey);
            request.headers.contentType = ContentType.json;
            request.write(jsonEncode({
              'query': query,
              'numResults': 4,
              'text': true,
            }));
            final response = await request.close();
            final body = await response.transform(utf8.decoder).join();
            if (response.statusCode < 200 || response.statusCode >= 300) {
              throw HttpException('HTTP ${response.statusCode}: $body');
            }
            final decoded = jsonDecode(body);
            if (decoded is Map && decoded['results'] is List) {
              final results = decoded['results'] as List;
              return results.map((r) => '- [${r['title']}](${r['url']}): ${r['text'] ?? r['highlights']?.first ?? ''}').join('\n\n');
            }
          } else if (provider == 'firecrawl') {
            final uri = Uri.parse('https://api.firecrawl.dev/v1/search');
            final request = await client.postUrl(uri);
            request.headers.set('Authorization', 'Bearer $currentKey');
            request.headers.contentType = ContentType.json;
            request.write(jsonEncode({
              'query': query,
              'limit': 4,
            }));
            final response = await request.close();
            final body = await response.transform(utf8.decoder).join();
            if (response.statusCode < 200 || response.statusCode >= 300) {
              throw HttpException('HTTP ${response.statusCode}: $body');
            }
            final decoded = jsonDecode(body);
            if (decoded is Map && decoded['data'] is List) {
              final results = decoded['data'] as List;
              return results.map((r) => '- [${r['title'] ?? r['metadata']?['title']}](${r['url'] ?? r['metadata']?['source']}): ${r['markdown'] ?? r['snippet'] ?? ''}').join('\n\n');
            }
          } else if (provider == 'google') {
            final uri = Uri.parse('https://www.googleapis.com/customsearch/v1?key=$currentKey&cx=${googleCx ?? ''}&q=${Uri.encodeComponent(query)}');
            final request = await client.getUrl(uri);
            final response = await request.close();
            final body = await response.transform(utf8.decoder).join();
            if (response.statusCode < 200 || response.statusCode >= 300) {
              throw HttpException('HTTP ${response.statusCode}: $body');
            }
            final decoded = jsonDecode(body);
            if (decoded is Map && decoded['items'] is List) {
              final results = decoded['items'] as List;
              return results.map((r) => '- [${r['title']}](${r['link']}): ${r['snippet']}').join('\n\n');
            }
          }
        } catch (e) {
          if (i < keys.length - 1) {
            debugPrint('Search failed with key index $i: $e. Trying fallback key.');
            continue;
          }
          rethrow;
        }
      }
      return 'No search results found.';
    } catch (e) {
      return 'Web search failed: $e';
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
    ProviderSettings settings,
    String activeApiKey, {
    required bool stream,
  }) {
    request.headers.set('Accept', stream ? 'text/event-stream' : 'application/json');
    if (activeApiKey.isNotEmpty) {
      request.headers.set('Authorization', 'Bearer $activeApiKey');
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
    this.fallbackApiKeys = const [],
    this.reasoningEnabled = true,
  });

  factory ProviderSettings.defaults(ProviderDefinition provider) {
    return ProviderSettings(
      apiKey: '',
      baseUrl: provider.baseUrl,
      model: provider.models.first,
      maxTokens: provider.defaultMaxTokens,
      fallbackApiKeys: const [],
      reasoningEnabled: true,
    );
  }

  factory ProviderSettings.fromJson(Map<String, dynamic> json) {
    return ProviderSettings(
      apiKey: json['apiKey']?.toString() ?? '',
      baseUrl: json['baseUrl']?.toString() ?? '',
      model: json['model']?.toString() ?? '',
      maxTokens: _readInt(json['maxTokens'], 0),
      fallbackApiKeys: (json['fallbackApiKeys'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      reasoningEnabled: json['reasoningEnabled'] as bool? ?? true,
    );
  }

  final String apiKey;
  final String baseUrl;
  final String model;
  final int maxTokens;
  final List<String> fallbackApiKeys;
  final bool reasoningEnabled;

  ProviderSettings copyWith({
    String? apiKey,
    String? baseUrl,
    String? model,
    int? maxTokens,
    List<String>? fallbackApiKeys,
    bool? reasoningEnabled,
  }) {
    return ProviderSettings(
      apiKey: apiKey ?? this.apiKey,
      baseUrl: baseUrl ?? this.baseUrl,
      model: model ?? this.model,
      maxTokens: maxTokens ?? this.maxTokens,
      fallbackApiKeys: fallbackApiKeys ?? this.fallbackApiKeys,
      reasoningEnabled: reasoningEnabled ?? this.reasoningEnabled,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'apiKey': apiKey,
      'baseUrl': baseUrl,
      'model': model,
      'maxTokens': maxTokens,
      'fallbackApiKeys': fallbackApiKeys,
      'reasoningEnabled': reasoningEnabled,
    };
  }

  static int _readInt(dynamic value, int fallback) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }
}

class SearchSettings {
  final bool enabled;
  final String provider; // 'tavily', 'exa', 'firecrawl', 'google'
  final String apiKey;
  final List<String> fallbackApiKeys;
  final String googleCx; // Google Search Engine ID

  const SearchSettings({
    required this.enabled,
    required this.provider,
    required this.apiKey,
    required this.fallbackApiKeys,
    required this.googleCx,
  });

  factory SearchSettings.defaults() {
    return const SearchSettings(
      enabled: false,
      provider: 'tavily',
      apiKey: '',
      fallbackApiKeys: [],
      googleCx: '',
    );
  }

  factory SearchSettings.fromJson(Map<String, dynamic> json) {
    return SearchSettings(
      enabled: json['enabled'] as bool? ?? false,
      provider: json['provider']?.toString() ?? 'tavily',
      apiKey: json['apiKey']?.toString() ?? '',
      fallbackApiKeys: (json['fallbackApiKeys'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      googleCx: json['googleCx']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'provider': provider,
        'apiKey': apiKey,
        'fallbackApiKeys': fallbackApiKeys,
        'googleCx': googleCx,
      };

  SearchSettings copyWith({
    bool? enabled,
    String? provider,
    String? apiKey,
    List<String>? fallbackApiKeys,
    String? googleCx,
  }) {
    return SearchSettings(
      enabled: enabled ?? this.enabled,
      provider: provider ?? this.provider,
      apiKey: apiKey ?? this.apiKey,
      fallbackApiKeys: fallbackApiKeys ?? this.fallbackApiKeys,
      googleCx: googleCx ?? this.googleCx,
    );
  }
}

enum MessageRole {
  system('system'),
  user('user'),
  assistant('assistant');

  const MessageRole(this.apiName);
  final String apiName;
}

class AttachedFile {
  final String name;
  final String content;

  const AttachedFile({required this.name, required this.content});

  Map<String, dynamic> toJson() => {'name': name, 'content': content};
  factory AttachedFile.fromJson(Map<String, dynamic> json) => AttachedFile(
    name: json['name']?.toString() ?? '',
    content: json['content']?.toString() ?? '',
  );
}

class ChatMessage {
  const ChatMessage({
    required this.role,
    required this.text,
    this.isError = false,
    this.reasoning = '',
    this.images = const [],
    this.files = const [],
  });

  final MessageRole role;
  final String text;
  final bool isError;
  final String reasoning;
  final List<String> images;
  final List<AttachedFile> files;
}

class ChatSession {
  final String id;
  final String title;
  final List<ChatMessage> messages;
  final String providerId;
  final String model;
  final int? maxTokens;
  final List<String> attachedImagesBase64;
  final List<AttachedFile> attachedFiles;

  ChatSession({
    required this.id,
    required this.title,
    required this.messages,
    required this.providerId,
    required this.model,
    this.maxTokens,
    this.attachedImagesBase64 = const [],
    this.attachedFiles = const [],
  });

  ChatSession copyWith({
    String? id,
    String? title,
    List<ChatMessage>? messages,
    String? providerId,
    String? model,
    int? maxTokens,
    List<String>? attachedImagesBase64,
    List<AttachedFile>? attachedFiles,
  }) {
    return ChatSession(
      id: id ?? this.id,
      title: title ?? this.title,
      messages: messages ?? this.messages,
      providerId: providerId ?? this.providerId,
      model: model ?? this.model,
      maxTokens: maxTokens ?? this.maxTokens,
      attachedImagesBase64: attachedImagesBase64 ?? this.attachedImagesBase64,
      attachedFiles: attachedFiles ?? this.attachedFiles,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'messages': messages.map((m) => {
          'role': m.role.apiName,
          'text': m.text,
          'isError': m.isError,
          'reasoning': m.reasoning,
          'images': m.images,
          'files': m.files.map((f) => f.toJson()).toList(),
        }).toList(),
        'providerId': providerId,
        'model': model,
        'maxTokens': maxTokens,
        'attachedImagesBase64': attachedImagesBase64,
        'attachedFiles': attachedFiles.map((f) => f.toJson()).toList(),
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
                  reasoning: m['reasoning']?.toString() ?? '',
                  images: (m['images'] as List?)?.map((e) => e.toString()).toList() ?? const [],
                  files: (m['files'] as List?)?.map((e) => AttachedFile.fromJson(Map<String, dynamic>.from(e as Map))).toList() ?? const [],
                ))
            .toList() ??
        [];
    return ChatSession(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      messages: messagesList,
      providerId: json['providerId']?.toString() ?? providerCatalog.first.id,
      model: json['model']?.toString() ?? '',
      maxTokens: json['maxTokens'] as int?,
      attachedImagesBase64: (json['attachedImagesBase64'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      attachedFiles: (json['attachedFiles'] as List?)?.map((e) => AttachedFile.fromJson(Map<String, dynamic>.from(e as Map))).toList() ?? const [],
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

class MermaidDiagramWidget extends StatelessWidget {
  const MermaidDiagramWidget({required this.code, super.key});
  final String code;

  @override
  Widget build(BuildContext context) {
    final String base64Code = base64UrlEncode(utf8.encode(code));
    final String url = 'https://mermaid.ink/img/$base64Code';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFDF9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE7D8C4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.account_tree_outlined, size: 16, color: Color(0xFF7B4E2E)),
              SizedBox(width: 6),
              Text(
                'Mermaid Diagram',
                style: TextStyle(
                  fontSize: 12,
                  color: Color(0xFF7B4E2E),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Center(
            child: InteractiveViewer(
              panEnabled: true,
              boundaryMargin: const EdgeInsets.all(20),
              minScale: 0.5,
              maxScale: 4.0,
              child: Image.network(
                url,
                errorBuilder: (context, error, stack) => Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    'Failed to load diagram.\nError: $error',
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return const Padding(
                    padding: EdgeInsets.all(32.0),
                    child: CircularProgressIndicator(),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ResearchPlanWidget extends StatefulWidget {
  const ResearchPlanWidget({required this.stateMap, required this.workspaceDir, required this.fileName, this.onStartResearch, super.key});
  final Map<String, dynamic> stateMap;
  final String workspaceDir;
  final String fileName;
  final VoidCallback? onStartResearch;

  @override
  State<ResearchPlanWidget> createState() => _ResearchPlanWidgetState();
}

class _ResearchPlanWidgetState extends State<ResearchPlanWidget> {
  final Set<int> _expandedSteps = {};
  late final Stopwatch _stopwatch;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _stopwatch = Stopwatch()..start();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _downloadFile() async {
    final path = '${widget.workspaceDir}/${widget.fileName}';
    final file = File(path);
    if (!await file.exists()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${widget.fileName} not found yet.')));
      }
      return;
    }
    
    final result = await FilePicker.platform.saveFile(
      dialogTitle: 'Save Research File',
      fileName: widget.fileName,
    );
    
    if (result != null) {
      await file.copy(result);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('File saved successfully!')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final steps = widget.stateMap['steps'] as List? ?? [];
    final status = widget.stateMap['status'] as String? ?? 'running';

    return Container(
      margin: const EdgeInsets.only(bottom: 12, top: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F4F8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFC0D3E5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: const BoxDecoration(
              color: Color(0xFFE2ECF5),
              borderRadius: BorderRadius.vertical(top: Radius.circular(11)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.science, size: 18, color: Color(0xFF2C5282)),
                    const SizedBox(width: 8),
                    Text(
                      status == 'completed' 
                          ? 'Deep Research Complete' 
                          : status == 'pending' 
                              ? 'Research Plan Ready' 
                              : 'Deep Research in Progress...',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF2C5282)),
                    ),
                  ],
                ),
                if (status == 'pending' && widget.onStartResearch != null)
                  ElevatedButton.icon(
                    onPressed: widget.onStartResearch,
                    icon: const Icon(Icons.play_arrow, size: 16, color: Colors.white),
                    label: const Text('Start', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2C5282),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      minimumSize: const Size(0, 32),
                    ),
                  ),
                if (status == 'running')
                  Text(
                    '${_stopwatch.elapsed.inMinutes.toString().padLeft(2, '0')}:${(_stopwatch.elapsed.inSeconds % 60).toString().padLeft(2, '0')}',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF2C5282)),
                  ),
                if (status == 'completed')
                  IconButton(
                    icon: const Icon(Icons.download, size: 20, color: Color(0xFF2C5282)),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: _downloadFile,
                  ),
              ],
            ),
          ),
          ...steps.asMap().entries.map((entry) {
            final idx = entry.key;
            final step = entry.value as Map<String, dynamic>;
            final stepStatus = step['status'] as String;
            final isExpanded = _expandedSteps.contains(idx);

            IconData statusIcon = Icons.radio_button_unchecked;
            Color statusColor = Colors.grey;
            if (stepStatus == 'running') {
              statusIcon = Icons.hourglass_bottom;
              statusColor = Colors.blue;
            } else if (stepStatus == 'completed') {
              statusIcon = Icons.check_circle;
              statusColor = Colors.green;
            }

            return Column(
              children: [
                InkWell(
                  onTap: () {
                    setState(() {
                      if (isExpanded) _expandedSteps.remove(idx);
                      else _expandedSteps.add(idx);
                    });
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: Row(
                      children: [
                        Icon(statusIcon, size: 18, color: statusColor),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            step['title'] ?? 'Step ${idx + 1}',
                            style: TextStyle(
                              decoration: stepStatus == 'completed' ? TextDecoration.lineThrough : null,
                              color: stepStatus == 'completed' ? Colors.grey : Colors.black87,
                              fontWeight: stepStatus == 'running' ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ),
                        Icon(isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, size: 18, color: Colors.grey),
                      ],
                    ),
                  ),
                ),
                if (isExpanded)
                  Container(
                    padding: const EdgeInsets.fromLTRB(40, 0, 14, 12),
                    alignment: Alignment.centerLeft,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Prompt: ${step['prompt']}',
                          style: const TextStyle(fontSize: 12.5, color: Colors.black54),
                        ),
                        if (step['content'] != null && step['content'].toString().isNotEmpty)
                          ...step['content'].toString().split('\n\n').where((s) => s.trim().isNotEmpty).map((s) {
                            if (s.startsWith('[MCP_REQUEST:')) {
                              final jsonStr = s.replaceFirst('[MCP_REQUEST:', '').replaceFirst(RegExp(r'\]$'), '').trim();
                              return McpToolBlock(mcpJson: jsonStr);
                            } else if (s.startsWith('[SEARCH_REQUEST:')) {
                              final query = s.replaceFirst('[SEARCH_REQUEST:', '').replaceFirst(']', '').trim();
                              return Container(
                                margin: const EdgeInsets.symmetric(vertical: 8),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF0F5FA),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: const Color(0xFFD0E0F0)),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.search, color: Color(0xFF2B6CB0), size: 16),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Searched the web for "$query"',
                                        style: const TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF2B6CB0),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }
                            return Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: Text(s, style: const TextStyle(fontSize: 12.5, color: Colors.black54)),
                            );
                          }),
                      ],
                    ),
                  ),
                if (idx < steps.length - 1)
                  const Divider(height: 1, indent: 40, color: Color(0xFFE2ECF5)),
              ],
            );
          }).toList(),
        ],
      ),
    );
  }
}
