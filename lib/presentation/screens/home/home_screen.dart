/// TermuxForge — Home Screen (Main IDE Layout)
///
/// The most important screen: a multi-pane IDE layout with
/// collapsible sidebars, a tabbed center area, a bottom terminal
/// panel, and a floating action button for quick commands.
library;

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import 'package:nexon/core/theme/app_colors.dart';
import 'package:nexon/presentation/layouts/responsive_layout.dart';
import 'package:nexon/presentation/layouts/split_view.dart';
import 'package:nexon/presentation/widgets/agent_avatar.dart';
import 'package:nexon/presentation/widgets/forge_app_bar.dart';
import 'package:nexon/presentation/widgets/glass_card.dart';
import 'package:nexon/presentation/widgets/mode_selector.dart';
import 'package:nexon/presentation/widgets/status_badge.dart';

/// The main IDE home screen.
class HomeScreen extends StatefulWidget {
  /// Creates a [HomeScreen].
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  // Panel visibility.
  bool _showLeftSidebar = true;
  bool _showRightSidebar = false;
  bool _showBottomPanel = true;

  // Center tab.
  int _centerTabIndex = 0; // 0 = Chat, 1 = Editor

  // Current mode.
  String _currentMode = 'code';

  // Current model.
  final String _currentModel = 'Claude 4 Sonnet';

  // Bottom panel height ratio.
  double _bottomRatio = 0.3;

  // Navigation rail index.
  int _navIndex = 0;

  late final AnimationController _fabController;

  @override
  void initState() {
    super.initState();
    _fabController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
  }

  @override
  void dispose() {
    _fabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveLayout(
      phone: (_) => _buildMobileLayout(context),
      tablet: (_) => _buildTabletLayout(context),
      desktop: (_) => _buildDesktopLayout(context),
    );
  }

  // ─────────────────────────────────────────────
  //  Desktop Layout — Full IDE
  // ─────────────────────────────────────────────

  Widget _buildDesktopLayout(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // ── Top App Bar ──
          _buildAppBar(context),

          // ── Mode Selector Strip ──
          Container(
            decoration: BoxDecoration(
              color: AppColors.backgroundSecondary,
              border: Border(
                bottom: BorderSide(color: AppColors.borderSubtle),
              ),
            ),
            child: ModeSelector(
              currentMode: _currentMode,
              onModeChanged: (m) => setState(() => _currentMode = m),
            ),
          ),

          // ── Main Content ──
          Expanded(
            child: SplitView(
              direction: Axis.vertical,
              initialRatio: _showBottomPanel ? 0.7 : 1.0,
              minFirstSize: 200,
              minSecondSize: _showBottomPanel ? 120 : 0,
              onRatioChanged: (r) => _bottomRatio = r,
              first: Row(
                children: [
                  // Left sidebar.
                  CollapsiblePanel(
                    isExpanded: _showLeftSidebar,
                    expandedSize: 260,
                    child: _LeftSidebar(
                      currentMode: _currentMode,
                      onFileTap: () =>
                          setState(() => _centerTabIndex = 1),
                    ),
                  ),

                  // Center pane.
                  Expanded(child: _buildCenterPane(context)),

                  // Right sidebar.
                  CollapsiblePanel(
                    isExpanded: _showRightSidebar,
                    expandedSize: 280,
                    child: const _RightSidebar(),
                  ),
                ],
              ),
              second: _showBottomPanel
                  ? const _BottomPanel()
                  : const SizedBox.shrink(),
            ),
          ),
        ],
      ),
      floatingActionButton: _buildFab(context),
    );
  }

  // ─────────────────────────────────────────────
  //  Tablet Layout — Simplified IDE
  // ─────────────────────────────────────────────

  Widget _buildTabletLayout(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          _buildAppBar(context),
          Container(
            decoration: BoxDecoration(
              color: AppColors.backgroundSecondary,
              border: Border(
                bottom: BorderSide(color: AppColors.borderSubtle),
              ),
            ),
            child: ModeSelector(
              currentMode: _currentMode,
              onModeChanged: (m) => setState(() => _currentMode = m),
              compact: true,
            ),
          ),
          Expanded(
            child: Row(
              children: [
                // Navigation rail.
                _buildNavRail(context),
                // Main content.
                Expanded(child: _buildCenterPane(context)),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: _buildFab(context),
    );
  }

  // ─────────────────────────────────────────────
  //  Mobile Layout — Single Pane
  // ─────────────────────────────────────────────

  Widget _buildMobileLayout(BuildContext context) {
    return Scaffold(
      appBar: ForgeAppBar(
        currentMode: _currentMode,
        currentModel: _currentModel,
        onMenuPressed: () => Scaffold.of(context).openDrawer(),
        onModeTap: _showModeSheet,
      ),
      drawer: _buildMobileDrawer(context),
      body: _buildCenterPane(context),
      bottomNavigationBar: _buildBottomNav(context),
      floatingActionButton: _buildFab(context),
    );
  }

  // ─────────────────────────────────────────────
  //  Shared Components
  // ─────────────────────────────────────────────

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return ForgeAppBar(
      currentMode: _currentMode,
      currentModel: _currentModel,
      onMenuPressed: () =>
          setState(() => _showLeftSidebar = !_showLeftSidebar),
      onModeTap: _showModeSheet,
      onModelTap: () => context.push('/models'),
      actions: [
        IconButton(
          icon: Icon(
            _showRightSidebar
                ? Icons.keyboard_double_arrow_right_rounded
                : Icons.keyboard_double_arrow_left_rounded,
            size: 20,
          ),
          onPressed: () =>
              setState(() => _showRightSidebar = !_showRightSidebar),
          tooltip: 'Toggle right panel',
        ),
        IconButton(
          icon: Icon(
            _showBottomPanel
                ? Icons.vertical_align_bottom_rounded
                : Icons.vertical_align_top_rounded,
            size: 20,
          ),
          onPressed: () =>
              setState(() => _showBottomPanel = !_showBottomPanel),
          tooltip: 'Toggle bottom panel',
        ),
      ],
    );
  }

  Widget _buildCenterPane(BuildContext context) {
    return Column(
      children: [
        // Tab bar.
        Container(
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.backgroundSecondary,
            border: Border(
              bottom: BorderSide(color: AppColors.borderSubtle),
            ),
          ),
          child: Row(
            children: [
              _CenterTab(
                label: 'Chat',
                icon: Icons.chat_bubble_outline_rounded,
                isActive: _centerTabIndex == 0,
                onTap: () => setState(() => _centerTabIndex = 0),
              ),
              _CenterTab(
                label: 'Editor',
                icon: Icons.code_rounded,
                isActive: _centerTabIndex == 1,
                onTap: () => setState(() => _centerTabIndex = 1),
              ),
              const Spacer(),
              // Quick action pills.
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: StatusBadge(
                  label: _currentMode.toUpperCase(),
                  color: AppColors.modeColor(_currentMode),
                  size: BadgeSize.small,
                ),
              ),
            ],
          ),
        ),
        // Content.
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: _centerTabIndex == 0
                ? const _InlineChatPane(key: ValueKey('chat'))
                : const _InlineEditorPane(key: ValueKey('editor')),
          ),
        ),
      ],
    );
  }

  Widget _buildNavRail(BuildContext context) {
    return NavigationRail(
      selectedIndex: _navIndex,
      onDestinationSelected: (i) {
        setState(() => _navIndex = i);
        final routes = [
          '/',
          '/chat',
          '/editor',
          '/terminal',
          '/files',
          '/agents',
          '/settings',
        ];
        if (i > 0 && i < routes.length) {
          context.push(routes[i]);
        }
      },
      labelType: NavigationRailLabelType.all,
      destinations: const [
        NavigationRailDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home_rounded),
          label: Text('Home'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.chat_bubble_outline),
          selectedIcon: Icon(Icons.chat_bubble_rounded),
          label: Text('Chat'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.code_outlined),
          selectedIcon: Icon(Icons.code_rounded),
          label: Text('Editor'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.terminal_outlined),
          selectedIcon: Icon(Icons.terminal_rounded),
          label: Text('Terminal'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.folder_outlined),
          selectedIcon: Icon(Icons.folder_rounded),
          label: Text('Files'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.hub_outlined),
          selectedIcon: Icon(Icons.hub_rounded),
          label: Text('Agents'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.settings_outlined),
          selectedIcon: Icon(Icons.settings_rounded),
          label: Text('Settings'),
        ),
      ],
    );
  }

  NavigationBar _buildBottomNav(BuildContext context) {
    return NavigationBar(
      selectedIndex: _navIndex.clamp(0, 4),
      onDestinationSelected: (i) {
        setState(() => _navIndex = i);
        final routes = ['/', '/chat', '/editor', '/terminal', '/settings'];
        if (i < routes.length) context.go(routes[i]);
      },
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home_rounded),
          label: 'Home',
        ),
        NavigationDestination(
          icon: Icon(Icons.chat_bubble_outline),
          selectedIcon: Icon(Icons.chat_bubble_rounded),
          label: 'Chat',
        ),
        NavigationDestination(
          icon: Icon(Icons.code_outlined),
          selectedIcon: Icon(Icons.code_rounded),
          label: 'Editor',
        ),
        NavigationDestination(
          icon: Icon(Icons.terminal_outlined),
          selectedIcon: Icon(Icons.terminal_rounded),
          label: 'Terminal',
        ),
        NavigationDestination(
          icon: Icon(Icons.settings_outlined),
          selectedIcon: Icon(Icons.settings_rounded),
          label: 'Settings',
        ),
      ],
    );
  }

  Widget _buildMobileDrawer(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: AppColors.accentGlow,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.auto_awesome_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'TermuxForge',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(),
            ..._drawerItems(context),
          ],
        ),
      ),
    );
  }

  List<Widget> _drawerItems(BuildContext context) {
    final items = [
      ('Files', Icons.folder_outlined, '/files'),
      ('Models', Icons.auto_awesome_outlined, '/models'),
      ('Todo', Icons.checklist_rounded, '/todo'),
      ('Agents', Icons.hub_outlined, '/agents'),
      ('Memory', Icons.memory_outlined, '/memory'),
      ('MCP', Icons.electrical_services_outlined, '/mcp'),
      ('Cost', Icons.attach_money_rounded, '/cost'),
      ('Workspace', Icons.workspaces_outlined, '/workspace'),
    ];

    return items.map((item) {
      return ListTile(
        leading: Icon(item.$2),
        title: Text(item.$1),
        onTap: () {
          Navigator.pop(context);
          context.push(item.$3);
        },
      );
    }).toList();
  }

  Widget _buildFab(BuildContext context) {
    return FloatingActionButton(
      onPressed: () => _showQuickCommandSheet(context),
      tooltip: 'Quick Command',
      child: const Icon(Icons.auto_awesome_rounded),
    )
        .animate()
        .scale(
          delay: 300.ms,
          duration: 400.ms,
          curve: Curves.easeOutBack,
        );
  }

  void _showModeSheet() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SizedBox(
        height: 420,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Select Mode',
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
            ),
            Expanded(
              child: ModeSelector(
                currentMode: _currentMode,
                scrollDirection: Axis.vertical,
                onModeChanged: (m) {
                  setState(() => _currentMode = m);
                  Navigator.pop(ctx);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showQuickCommandSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(ctx).bottom,
          left: 16,
          right: 16,
          top: 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Ask anything or type a command...',
                prefixIcon: Icon(Icons.auto_awesome_rounded),
                border: OutlineInputBorder(),
              ),
              onSubmitted: (value) {
                Navigator.pop(ctx);
                // TODO: Send to orchestrator.
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────
//  Left Sidebar — File Explorer + Agents
// ─────────────────────────────────────────────────

class _LeftSidebar extends StatefulWidget {
  const _LeftSidebar({required this.currentMode, this.onFileTap});

  final String currentMode;
  final VoidCallback? onFileTap;

  @override
  State<_LeftSidebar> createState() => _LeftSidebarState();
}

class _LeftSidebarState extends State<_LeftSidebar> {
  int _tabIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: AppColors.sidebarGradient,
        border: Border(right: BorderSide(color: AppColors.borderSubtle)),
      ),
      child: Column(
        children: [
          // Tab header.
          Row(
            children: [
              _SidebarTabButton(
                label: 'Files',
                icon: Icons.folder_outlined,
                isActive: _tabIndex == 0,
                onTap: () => setState(() => _tabIndex = 0),
              ),
              _SidebarTabButton(
                label: 'Agents',
                icon: Icons.hub_outlined,
                isActive: _tabIndex == 1,
                onTap: () => setState(() => _tabIndex = 1),
              ),
            ],
          ),
          const Divider(height: 1),
          // Content.
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: _tabIndex == 0
                  ? _FileListPreview(
                      key: const ValueKey('files'),
                      onFileTap: widget.onFileTap,
                    )
                  : const _AgentListPreview(key: ValueKey('agents')),
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarTabButton extends StatelessWidget {
  const _SidebarTabButton({
    required this.label,
    required this.icon,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isActive ? AppColors.accentBlue : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: isActive ? AppColors.accentBlue : AppColors.textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                  color:
                      isActive ? AppColors.accentBlue : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FileListPreview extends StatelessWidget {
  const _FileListPreview({super.key, this.onFileTap});

  final VoidCallback? onFileTap;

  @override
  Widget build(BuildContext context) {
    // Placeholder file tree.
    final files = [
      ('lib/', Icons.folder_rounded, true),
      ('  main.dart', Icons.code_rounded, false),
      ('  app.dart', Icons.code_rounded, false),
      ('  core/', Icons.folder_rounded, true),
      ('    theme/', Icons.folder_rounded, true),
      ('  presentation/', Icons.folder_rounded, true),
      ('    screens/', Icons.folder_rounded, true),
      ('    widgets/', Icons.folder_rounded, true),
      ('pubspec.yaml', Icons.settings_rounded, false),
      ('README.md', Icons.description_rounded, false),
    ];

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: files.length,
      itemBuilder: (_, i) {
        final (name, icon, isDir) = files[i];
        return InkWell(
          onTap: isDir ? null : onFileTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: isDir
                      ? AppColors.accentBlue.withValues(alpha: 0.7)
                      : AppColors.textTertiary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    name.trim(),
                    style: TextStyle(
                      fontSize: 13,
                      color: isDir
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                      fontWeight:
                          isDir ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _AgentListPreview extends StatelessWidget {
  const _AgentListPreview({super.key});

  @override
  Widget build(BuildContext context) {
    final agents = [
      ('Orchestrator', 'orchestrator', true),
      ('Coder', 'coder', true),
      ('Architect', 'architect', false),
      ('Debugger', 'debugger', false),
      ('Reviewer', 'reviewer', false),
      ('DevOps', 'devops', false),
    ];

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: agents.length,
      itemBuilder: (_, i) {
        final (name, type, active) = agents[i];
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          child: ListTile(
            dense: true,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            leading: AgentAvatar(
              agentType: type,
              size: AvatarSize.small,
              showStatus: true,
              isActive: active,
            ),
            title: Text(
              name,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
            subtitle: Text(
              active ? 'Active' : 'Idle',
              style: TextStyle(
                fontSize: 11,
                color: active ? AppColors.success : AppColors.textTertiary,
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────
//  Right Sidebar — Details
// ─────────────────────────────────────────────────

class _RightSidebar extends StatelessWidget {
  const _RightSidebar();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: AppColors.sidebarGradient,
        border: Border(left: BorderSide(color: AppColors.borderSubtle)),
      ),
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Text(
            'Context',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          GlassCard(
            padding: const EdgeInsets.all(12),
            borderRadius: 12,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.memory_rounded, size: 16),
                    const SizedBox(width: 8),
                    Text(
                      'Active Memory',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '12 entries loaded',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          GlassCard(
            padding: const EdgeInsets.all(12),
            borderRadius: 12,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.electrical_services_rounded, size: 16),
                    const SizedBox(width: 8),
                    Text(
                      'MCP Servers',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                StatusBadge(
                  label: '3 connected',
                  color: AppColors.success,
                  pulsing: true,
                  size: BadgeSize.small,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          GlassCard(
            padding: const EdgeInsets.all(12),
            borderRadius: 12,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.attach_money_rounded, size: 16),
                    const SizedBox(width: 8),
                    Text(
                      'Session Cost',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '\$0.0342',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: AppColors.accentBlue,
                    fontWeight: FontWeight.w700,
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

// ─────────────────────────────────────────────────
//  Bottom Panel — Terminal + Output
// ─────────────────────────────────────────────────

class _BottomPanel extends StatefulWidget {
  const _BottomPanel();

  @override
  State<_BottomPanel> createState() => _BottomPanelState();
}

class _BottomPanelState extends State<_BottomPanel>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.backgroundSecondary,
        border: Border(top: BorderSide(color: AppColors.borderSubtle)),
      ),
      child: Column(
        children: [
          TabBar(
            controller: _tabController,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: const [
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.terminal_rounded, size: 14),
                    SizedBox(width: 6),
                    Text('Terminal'),
                  ],
                ),
              ),
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.output_rounded, size: 14),
                    SizedBox(width: 6),
                    Text('Output'),
                  ],
                ),
              ),
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.task_alt_rounded, size: 14),
                    SizedBox(width: 6),
                    Text('Tasks'),
                  ],
                ),
              ),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _TerminalPreview(),
                _OutputPreview(),
                _TasksPreview(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TerminalPreview extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.backgroundPrimary,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              '\$ termux-forge init\n'
              '✓ Project initialized\n'
              '✓ Isar database ready\n'
              '✓ MCP servers connected\n'
              '\$ _',
              style: TextStyle(
                fontFamily: 'JetBrainsMono',
                fontSize: 12,
                color: AppColors.textSecondary,
                height: 1.6,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OutputPreview extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.backgroundPrimary,
      padding: const EdgeInsets.all(12),
      child: Text(
        'No output yet.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}

class _TasksPreview extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.backgroundPrimary,
      padding: const EdgeInsets.all(12),
      child: Text(
        'No active tasks.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}

// ─────────────────────────────────────────────────
//  Center Tab — Inline Chat
// ─────────────────────────────────────────────────

class _CenterTab extends StatelessWidget {
  const _CenterTab({
    required this.label,
    required this.icon,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isActive
              ? AppColors.backgroundTertiary
              : Colors.transparent,
          border: Border(
            bottom: BorderSide(
              color: isActive ? AppColors.accentBlue : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isActive ? AppColors.accentBlue : AppColors.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                color:
                    isActive ? AppColors.textPrimary : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InlineChatPane extends StatelessWidget {
  const _InlineChatPane({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.backgroundPrimary,
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: AppColors.cardGradient,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.glassBorder),
                    ),
                    child: const Icon(
                      Icons.auto_awesome_rounded,
                      size: 48,
                      color: AppColors.accentBlue,
                    ),
                  )
                      .animate()
                      .fadeIn(duration: 400.ms)
                      .scale(begin: const Offset(0.8, 0.8)),
                  const SizedBox(height: 16),
                  Text(
                    'Ready to Forge',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ).animate().fadeIn(delay: 150.ms),
                  const SizedBox(height: 8),
                  Text(
                    'Type a message or use ⌘K for quick commands',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ).animate().fadeIn(delay: 250.ms),
                ],
              ),
            ),
          ),
          // Input bar.
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.backgroundSecondary,
              border: Border(
                top: BorderSide(color: AppColors.borderSubtle),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Message the agent...',
                      prefixIcon:
                          const Icon(Icons.auto_awesome_rounded, size: 18),
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
                IconButton.filled(
                  onPressed: () {},
                  icon: const Icon(Icons.send_rounded, size: 18),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineEditorPane extends StatelessWidget {
  const _InlineEditorPane({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.backgroundPrimary,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.code_rounded,
              size: 48,
              color: AppColors.accentPurple.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'Open a file to start editing',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Select a file from the explorer or use ⌘P',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
