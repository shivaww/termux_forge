/// TermuxForge — GoRouter Configuration
///
/// Defines all application routes with nested navigation support
/// for the split-view IDE layout. Uses redirect logic for initial
/// onboarding detection.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:nexon/presentation/screens/agents/agent_observability_screen.dart';
import 'package:nexon/presentation/screens/chat/chat_screen.dart';
import 'package:nexon/presentation/screens/editor/editor_screen.dart';
import 'package:nexon/presentation/screens/file_explorer/file_explorer_screen.dart';
import 'package:nexon/presentation/screens/home/home_screen.dart';
import 'package:nexon/presentation/screens/model_center/model_center_screen.dart';
import 'package:nexon/presentation/screens/onboarding/onboarding_screen.dart';
import 'package:nexon/presentation/screens/settings/settings_screen.dart';
import 'package:nexon/presentation/screens/terminal/terminal_screen.dart';
import 'package:nexon/presentation/screens/todo/todo_dashboard_screen.dart';

/// Global navigator keys for nested navigation.
final rootNavigatorKey = GlobalKey<NavigatorState>();

/// Creates the [GoRouter] instance.
///
/// [isOnboarded] determines whether the user sees the onboarding
/// flow or the main IDE on first launch.
GoRouter createRouter({bool isOnboarded = false}) {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: isOnboarded ? '/' : '/onboarding',
    debugLogDiagnostics: true,
    routes: [
      // ── Onboarding ──
      GoRoute(
        path: '/onboarding',
        name: 'onboarding',
        pageBuilder: (context, state) => _fadeTransition(
          state,
          const OnboardingScreen(),
        ),
      ),

      // ── Main IDE Shell ──
      GoRoute(
        path: '/',
        name: 'home',
        pageBuilder: (context, state) => _fadeTransition(
          state,
          const HomeScreen(),
        ),
      ),

      // ── Chat ──
      GoRoute(
        path: '/chat',
        name: 'chat',
        pageBuilder: (context, state) => _slideTransition(
          state,
          const ChatScreen(),
        ),
      ),

      // ── Editor ──
      GoRoute(
        path: '/editor',
        name: 'editor',
        pageBuilder: (context, state) => _slideTransition(
          state,
          const EditorScreen(),
        ),
      ),

      // ── Terminal ──
      GoRoute(
        path: '/terminal',
        name: 'terminal',
        pageBuilder: (context, state) => _slideTransition(
          state,
          const TerminalScreen(),
        ),
      ),

      // ── File Explorer ──
      GoRoute(
        path: '/files',
        name: 'files',
        pageBuilder: (context, state) => _slideTransition(
          state,
          const FileExplorerScreen(),
        ),
      ),

      // ── Settings ──
      GoRoute(
        path: '/settings',
        name: 'settings',
        pageBuilder: (context, state) => _slideTransition(
          state,
          const SettingsScreen(),
        ),
      ),

      // ── Model Center ──
      GoRoute(
        path: '/models',
        name: 'models',
        pageBuilder: (context, state) => _slideTransition(
          state,
          const ModelCenterScreen(),
        ),
      ),

      // ── Battle Mode ──
      GoRoute(
        path: '/battle',
        name: 'battle',
        pageBuilder: (context, state) => _slideTransition(
          state,
          const _PlaceholderScreen(title: 'Battle Arena'),
        ),
      ),

      // ── Todo Dashboard ──
      GoRoute(
        path: '/todo',
        name: 'todo',
        pageBuilder: (context, state) => _slideTransition(
          state,
          const TodoDashboardScreen(),
        ),
      ),

      // ── Task Board ──
      GoRoute(
        path: '/tasks',
        name: 'tasks',
        pageBuilder: (context, state) => _slideTransition(
          state,
          const _PlaceholderScreen(title: 'Task Board'),
        ),
      ),

      // ── Memory Dashboard ──
      GoRoute(
        path: '/memory',
        name: 'memory',
        pageBuilder: (context, state) => _slideTransition(
          state,
          const _PlaceholderScreen(title: 'Memory Dashboard'),
        ),
      ),

      // ── MCP Panel ──
      GoRoute(
        path: '/mcp',
        name: 'mcp',
        pageBuilder: (context, state) => _slideTransition(
          state,
          const _PlaceholderScreen(title: 'MCP Panel'),
        ),
      ),

      // ── Workflow Dashboard ──
      GoRoute(
        path: '/workflow',
        name: 'workflow',
        pageBuilder: (context, state) => _slideTransition(
          state,
          const _PlaceholderScreen(title: 'Workflow Dashboard'),
        ),
      ),

      // ── Agent Observability ──
      GoRoute(
        path: '/agents',
        name: 'agents',
        pageBuilder: (context, state) => _slideTransition(
          state,
          const AgentObservabilityScreen(),
        ),
      ),

      // ── Artifact Browser ──
      GoRoute(
        path: '/artifacts',
        name: 'artifacts',
        pageBuilder: (context, state) => _slideTransition(
          state,
          const _PlaceholderScreen(title: 'Artifact Browser'),
        ),
      ),

      // ── Knowledge Base ──
      GoRoute(
        path: '/knowledge',
        name: 'knowledge',
        pageBuilder: (context, state) => _slideTransition(
          state,
          const _PlaceholderScreen(title: 'Knowledge Base'),
        ),
      ),

      // ── Cost Dashboard ──
      GoRoute(
        path: '/cost',
        name: 'cost',
        pageBuilder: (context, state) => _slideTransition(
          state,
          const _PlaceholderScreen(title: 'Cost Dashboard'),
        ),
      ),

      // ── Checkpoint Panel ──
      GoRoute(
        path: '/checkpoint',
        name: 'checkpoint',
        pageBuilder: (context, state) => _slideTransition(
          state,
          const _PlaceholderScreen(title: 'Checkpoint Panel'),
        ),
      ),

      // ── Media Panel ──
      GoRoute(
        path: '/media',
        name: 'media',
        pageBuilder: (context, state) => _slideTransition(
          state,
          const _PlaceholderScreen(title: 'Media Panel'),
        ),
      ),

      // ── GitHub Build Panel ──
      GoRoute(
        path: '/build',
        name: 'build',
        pageBuilder: (context, state) => _slideTransition(
          state,
          const _PlaceholderScreen(title: 'GitHub Build Panel'),
        ),
      ),

      // ── Workspace Manager ──
      GoRoute(
        path: '/workspace',
        name: 'workspace',
        pageBuilder: (context, state) => _slideTransition(
          state,
          const _PlaceholderScreen(title: 'Workspace Manager'),
        ),
      ),
    ],
  );
}

// ─────────────────────────────────────────────────
//  Page Transition Helpers
// ─────────────────────────────────────────────────

CustomTransitionPage<void> _fadeTransition(
  GoRouterState state,
  Widget child,
) {
  return CustomTransitionPage(
    key: state.pageKey,
    child: child,
    transitionsBuilder: (_, animation, __, child) => FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
      child: child,
    ),
    transitionDuration: const Duration(milliseconds: 250),
  );
}

CustomTransitionPage<void> _slideTransition(
  GoRouterState state,
  Widget child,
) {
  return CustomTransitionPage(
    key: state.pageKey,
    child: child,
    transitionsBuilder: (_, animation, __, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      return SlideTransition(
        position: Tween(
          begin: const Offset(0.05, 0),
          end: Offset.zero,
        ).animate(curved),
        child: FadeTransition(opacity: curved, child: child),
      );
    },
    transitionDuration: const Duration(milliseconds: 300),
  );
}

// ─────────────────────────────────────────────────
//  Placeholder for routes not yet implemented
// ─────────────────────────────────────────────────

class _PlaceholderScreen extends StatelessWidget {
  const _PlaceholderScreen({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.construction_rounded,
              size: 64,
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Coming soon',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
