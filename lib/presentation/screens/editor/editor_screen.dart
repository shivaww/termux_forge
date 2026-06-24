/// TermuxForge — Code Editor Screen
///
/// Tabbed code editor with syntax highlighting, line numbers,
/// search/replace, file path breadcrumb, modified indicator,
/// and "Send to Agent" button.
library;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:re_editor/re_editor.dart';

import 'package:nexon/core/theme/app_colors.dart';
import 'package:nexon/presentation/widgets/forge_app_bar.dart';
import 'package:nexon/presentation/widgets/status_badge.dart';

/// Represents a single editor tab.
class _EditorTab {
  _EditorTab({
    required this.path,
    required this.fileName,
    this.language = 'dart',
    this.content = '',
    this.isModified = false,
  }) : controller = CodeLineEditingController.fromText(content);

  final String path;
  final String fileName;
  final String language;
  final String content;
  bool isModified;
  final CodeLineEditingController controller;
}

/// The code editor screen.
class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  final List<_EditorTab> _tabs = [
    _EditorTab(
      path: 'lib/main.dart',
      fileName: 'main.dart',
      content: '''import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nexon/app.dart';

void main() {
  runApp(
    const ProviderScope(
      child: TermuxForgeApp(),
    ),
  );
}
''',
    ),
    _EditorTab(
      path: 'lib/app.dart',
      fileName: 'app.dart',
      content: '''import 'package:flutter/material.dart';

class TermuxForgeApp extends StatelessWidget {
  const TermuxForgeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'TermuxForge',
      debugShowCheckedModeBanner: false,
    );
  }
}
''',
    ),
  ];

  int _activeTabIndex = 0;
  bool _showSearch = false;
  final _searchController = TextEditingController();
  final _replaceController = TextEditingController();

  _EditorTab get _activeTab => _tabs[_activeTabIndex];

  @override
  void dispose() {
    _searchController.dispose();
    _replaceController.dispose();
    for (final tab in _tabs) {
      tab.controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: ForgeAppBar(
        title: 'Editor',
        showBackButton: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.search_rounded, size: 20),
            onPressed: () => setState(() => _showSearch = !_showSearch),
            tooltip: 'Search',
          ),
          IconButton(
            icon: const Icon(Icons.save_outlined, size: 20),
            onPressed: _saveCurrentFile,
            tooltip: 'Save',
          ),
          // Send to agent.
          TextButton.icon(
            onPressed: _sendToAgent,
            icon: const Icon(Icons.auto_awesome_rounded, size: 16),
            label: const Text('Send to Agent', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Tab bar ──
          _buildTabBar(context),

          // ── Breadcrumb ──
          _buildBreadcrumb(context),

          // ── Search/Replace bar ──
          if (_showSearch) _buildSearchBar(context),

          // ── Code editor ──
          Expanded(child: _buildEditor(context)),

          // ── Status bar ──
          _buildStatusBar(context),
        ],
      ),
    );
  }

  Widget _buildTabBar(BuildContext context) {
    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: AppColors.backgroundSecondary,
        border: Border(bottom: BorderSide(color: AppColors.borderSubtle)),
      ),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _tabs.length,
        itemBuilder: (_, i) {
          final tab = _tabs[i];
          final isActive = i == _activeTabIndex;
          return InkWell(
            onTap: () => setState(() => _activeTabIndex = i),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: isActive
                    ? AppColors.backgroundPrimary
                    : Colors.transparent,
                border: Border(
                  bottom: BorderSide(
                    color:
                        isActive ? AppColors.accentBlue : Colors.transparent,
                    width: 2,
                  ),
                  right: BorderSide(color: AppColors.borderSubtle),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.code_rounded,
                    size: 14,
                    color: isActive
                        ? AppColors.accentBlue
                        : AppColors.textTertiary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    tab.fileName,
                    style: TextStyle(
                      fontSize: 12,
                      color: isActive
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                      fontWeight:
                          isActive ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                  if (tab.isModified) ...[
                    const SizedBox(width: 4),
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: AppColors.accentBlue,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                  const SizedBox(width: 6),
                  InkWell(
                    onTap: () => _closeTab(i),
                    child: const Icon(Icons.close, size: 14),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBreadcrumb(BuildContext context) {
    final parts = _activeTab.path.split('/');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.backgroundSecondary.withValues(alpha: 0.5),
        border: Border(bottom: BorderSide(color: AppColors.borderSubtle)),
      ),
      child: Row(
        children: [
          for (int i = 0; i < parts.length; i++) ...[
            if (i > 0)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 14,
                  color: AppColors.textTertiary,
                ),
              ),
            Text(
              parts[i],
              style: TextStyle(
                fontSize: 12,
                color: i == parts.length - 1
                    ? AppColors.textPrimary
                    : AppColors.textTertiary,
                fontWeight:
                    i == parts.length - 1 ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
          const Spacer(),
          StatusBadge(
            label: _activeTab.language.toUpperCase(),
            color: AppColors.accentPurple,
            size: BadgeSize.small,
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.backgroundSecondary,
        border: Border(bottom: BorderSide(color: AppColors.borderSubtle)),
      ),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 32,
              child: TextField(
                controller: _searchController,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Search...',
                  prefixIcon: const Icon(Icons.search, size: 16),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SizedBox(
              height: 32,
              child: TextField(
                controller: _replaceController,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Replace...',
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.close, size: 16),
            onPressed: () => setState(() => _showSearch = false),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    ).animate().slideY(begin: -1, duration: 200.ms, curve: Curves.easeOut);
  }

  Widget _buildEditor(BuildContext context) {
    return Container(
      color: AppColors.backgroundPrimary,
      child: CodeEditor(
        controller: _activeTab.controller,
        style: CodeEditorStyle(
          fontSize: 14,
          fontFamily: 'JetBrainsMono',
          textColor: AppColors.textPrimary,
          backgroundColor: AppColors.backgroundPrimary,
          cursorColor: AppColors.accentBlue,
          selectionColor: AppColors.accentBlue.withValues(alpha: 0.2),
          fontHeight: 1.6,
        ),
        indicatorBuilder: (context, editingController, chunkController, notifier) {
          return Row(
            children: [
              DefaultCodeLineNumber(
                controller: editingController,
                notifier: notifier,
                textStyle: GoogleFonts.jetBrainsMono(
                  fontSize: 12,
                  color: AppColors.textTertiary,
                ),
              ),
              const SizedBox(width: 8),
            ],
          );
        },
        onChanged: (_) {
          if (!_activeTab.isModified) {
            setState(() => _activeTab.isModified = true);
          }
        },
      ),
    );
  }

  Widget _buildStatusBar(BuildContext context) {
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.backgroundSecondary,
        border: Border(top: BorderSide(color: AppColors.borderSubtle)),
      ),
      child: Row(
        children: [
          Text(
            'Ln 1, Col 1',
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textTertiary,
              fontFamily: 'JetBrainsMono',
            ),
          ),
          const Spacer(),
          Text(
            'UTF-8',
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textTertiary,
            ),
          ),
          const SizedBox(width: 16),
          Text(
            _activeTab.language.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }

  void _closeTab(int index) {
    if (_tabs.length <= 1) return;
    setState(() {
      _tabs[index].controller.dispose();
      _tabs.removeAt(index);
      if (_activeTabIndex >= _tabs.length) {
        _activeTabIndex = _tabs.length - 1;
      }
    });
  }

  void _saveCurrentFile() {
    setState(() => _activeTab.isModified = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Saved ${_activeTab.fileName}')),
    );
  }

  void _sendToAgent() {
    // TODO: Send current file content to selected agent.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Sent to agent for review')),
    );
  }
}
