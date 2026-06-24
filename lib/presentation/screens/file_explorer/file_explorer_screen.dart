/// TermuxForge — File Explorer Screen
///
/// Tree-based file explorer with folder expand/collapse, file icons,
/// context menu actions, create new file/folder, and search filter.
library;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import 'package:nexon/core/theme/app_colors.dart';
import 'package:nexon/presentation/widgets/forge_app_bar.dart';
import 'package:nexon/presentation/widgets/glass_card.dart';

/// A node in the file tree.
class _FileNode {
  _FileNode({
    required this.name,
    required this.isDirectory,
    this.children = const [],
    this.depth = 0,
  });

  final String name;
  final bool isDirectory;
  final List<_FileNode> children;
  final int depth;
  bool isExpanded = true;
}

/// The file explorer screen.
class FileExplorerScreen extends StatefulWidget {
  const FileExplorerScreen({super.key});

  @override
  State<FileExplorerScreen> createState() => _FileExplorerScreenState();
}

class _FileExplorerScreenState extends State<FileExplorerScreen> {
  final _searchController = TextEditingController();
  String _searchQuery = '';

  // Demo file tree.
  late final List<_FileNode> _rootNodes = [
    _FileNode(
      name: 'lib',
      isDirectory: true,
      children: [
        _FileNode(name: 'main.dart', isDirectory: false, depth: 1),
        _FileNode(name: 'app.dart', isDirectory: false, depth: 1),
        _FileNode(
          name: 'core',
          isDirectory: true,
          depth: 1,
          children: [
            _FileNode(
              name: 'theme',
              isDirectory: true,
              depth: 2,
              children: [
                _FileNode(
                  name: 'app_colors.dart',
                  isDirectory: false,
                  depth: 3,
                ),
                _FileNode(
                  name: 'app_theme.dart',
                  isDirectory: false,
                  depth: 3,
                ),
              ],
            ),
            _FileNode(
              name: 'router',
              isDirectory: true,
              depth: 2,
              children: [
                _FileNode(
                  name: 'app_router.dart',
                  isDirectory: false,
                  depth: 3,
                ),
              ],
            ),
          ],
        ),
        _FileNode(
          name: 'presentation',
          isDirectory: true,
          depth: 1,
          children: [
            _FileNode(
              name: 'screens',
              isDirectory: true,
              depth: 2,
              children: [
                _FileNode(
                  name: 'home_screen.dart',
                  isDirectory: false,
                  depth: 3,
                ),
                _FileNode(
                  name: 'chat_screen.dart',
                  isDirectory: false,
                  depth: 3,
                ),
              ],
            ),
            _FileNode(
              name: 'widgets',
              isDirectory: true,
              depth: 2,
              children: [
                _FileNode(
                  name: 'glass_card.dart',
                  isDirectory: false,
                  depth: 3,
                ),
              ],
            ),
          ],
        ),
      ],
    ),
    _FileNode(name: 'pubspec.yaml', isDirectory: false),
    _FileNode(name: 'README.md', isDirectory: false),
    _FileNode(name: '.gitignore', isDirectory: false),
    _FileNode(
      name: 'test',
      isDirectory: true,
      children: [
        _FileNode(
          name: 'widget_test.dart',
          isDirectory: false,
          depth: 1,
        ),
      ],
    ),
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Returns the icon for a file based on extension.
  IconData _fileIcon(String name) {
    final ext = name.split('.').last.toLowerCase();
    return switch (ext) {
      'dart' => Icons.code_rounded,
      'yaml' || 'yml' => Icons.settings_rounded,
      'md' => Icons.description_rounded,
      'json' => Icons.data_object_rounded,
      'gitignore' => Icons.visibility_off_rounded,
      'png' || 'jpg' || 'svg' => Icons.image_rounded,
      'lock' => Icons.lock_rounded,
      _ => Icons.insert_drive_file_rounded,
    };
  }

  Color _fileIconColor(String name) {
    final ext = name.split('.').last.toLowerCase();
    return switch (ext) {
      'dart' => AppColors.accentBlue,
      'yaml' || 'yml' => AppColors.warning,
      'md' => AppColors.accentPurple,
      'json' => AppColors.accentTeal,
      _ => AppColors.textTertiary,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: ForgeAppBar(
        title: 'Files',
        showBackButton: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.create_new_folder_outlined, size: 20),
            onPressed: () => _showCreateDialog(context, isDirectory: true),
            tooltip: 'New Folder',
          ),
          IconButton(
            icon: const Icon(Icons.note_add_outlined, size: 20),
            onPressed: () => _showCreateDialog(context, isDirectory: false),
            tooltip: 'New File',
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Search bar ──
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _searchQuery = v),
              decoration: InputDecoration(
                hintText: 'Search files...',
                prefixIcon: const Icon(Icons.search_rounded, size: 18),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 16),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),

          // ── Project root ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: GlassCard(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              borderRadius: 10,
              child: Row(
                children: [
                  const Icon(Icons.folder_special_rounded, size: 18,
                      color: AppColors.accentBlue),
                  const SizedBox(width: 8),
                  Text(
                    'termux_forge',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '~/termux_forge',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),

          // ── File tree ──
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              children: _buildTreeList(_rootNodes),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildTreeList(List<_FileNode> nodes) {
    final widgets = <Widget>[];
    for (final node in nodes) {
      if (_searchQuery.isNotEmpty &&
          !node.name.toLowerCase().contains(_searchQuery.toLowerCase()) &&
          !node.isDirectory) {
        continue;
      }
      widgets.add(_buildTreeItem(node));
      if (node.isDirectory && node.isExpanded) {
        widgets.addAll(_buildTreeList(node.children));
      }
    }
    return widgets;
  }

  Widget _buildTreeItem(_FileNode node) {
    return InkWell(
      onTap: () {
        if (node.isDirectory) {
          setState(() => node.isExpanded = !node.isExpanded);
        } else {
          // TODO: Open file in editor.
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Opening ${node.name}')),
          );
        }
      },
      onLongPress: () => _showContextMenu(context, node),
      child: Padding(
        padding: EdgeInsets.only(
          left: 16.0 + node.depth * 20.0,
          right: 12,
          top: 6,
          bottom: 6,
        ),
        child: Row(
          children: [
            if (node.isDirectory)
              Icon(
                node.isExpanded
                    ? Icons.keyboard_arrow_down_rounded
                    : Icons.keyboard_arrow_right_rounded,
                size: 18,
                color: AppColors.textTertiary,
              )
            else
              const SizedBox(width: 18),
            const SizedBox(width: 4),
            Icon(
              node.isDirectory
                  ? (node.isExpanded
                      ? Icons.folder_open_rounded
                      : Icons.folder_rounded)
                  : _fileIcon(node.name),
              size: 18,
              color: node.isDirectory
                  ? AppColors.accentBlue.withValues(alpha: 0.7)
                  : _fileIconColor(node.name),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                node.name,
                style: TextStyle(
                  fontSize: 13,
                  color: node.isDirectory
                      ? AppColors.textPrimary
                      : AppColors.textSecondary,
                  fontWeight:
                      node.isDirectory ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showContextMenu(BuildContext context, _FileNode node) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.open_in_new_rounded),
              title: const Text('Open'),
              onTap: () => Navigator.pop(ctx),
            ),
            ListTile(
              leading: const Icon(Icons.edit_rounded),
              title: const Text('Rename'),
              onTap: () => Navigator.pop(ctx),
            ),
            ListTile(
              leading: const Icon(Icons.auto_awesome_rounded),
              title: const Text('Send to Agent'),
              onTap: () => Navigator.pop(ctx),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded,
                  color: AppColors.error),
              title: const Text('Delete',
                  style: TextStyle(color: AppColors.error)),
              onTap: () => Navigator.pop(ctx),
            ),
          ],
        ),
      ),
    );
  }

  void _showCreateDialog(
    BuildContext context, {
    required bool isDirectory,
  }) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isDirectory ? 'New Folder' : 'New File'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: isDirectory ? 'Folder name' : 'filename.dart',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              // TODO: Create file/folder.
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
}
