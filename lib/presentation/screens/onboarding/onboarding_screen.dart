/// TermuxForge — Onboarding Screen
///
/// A multi-page setup wizard with smooth page transitions:
/// 1. Welcome page with app description
/// 2. API key setup (provider selection)
/// 3. Termux bridge connection test
/// 4. Default model selection
/// 5. First project setup
library;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import 'package:nexon/core/theme/app_colors.dart';
import 'package:nexon/presentation/widgets/glass_card.dart';
import 'package:nexon/presentation/widgets/status_badge.dart';
import 'package:nexon/services/storage/app_storage.dart';

/// The onboarding wizard screen.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pageController = PageController();
  int _currentPage = 0;
  final int _totalPages = 5;

  // State across pages.
  String? _selectedProvider;
  final _apiKeyController = TextEditingController();
  bool _bridgeConnected = false;
  String _selectedModel = 'Claude 4 Sonnet';
  final _projectNameController = TextEditingController();

  @override
  void dispose() {
    _pageController.dispose();
    _apiKeyController.dispose();
    _projectNameController.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_currentPage < _totalPages - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      );
    } else {
      // Complete onboarding and persist.
      AppStorage.saveOnboarded(true);
      context.go('/');
    }
  }

  void _previousPage() {
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.backgroundGradient),
        child: SafeArea(
          child: Column(
            children: [
              // ── Progress bar ──
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Row(
                  children: List.generate(_totalPages, (i) {
                    return Expanded(
                      child: Container(
                        height: 3,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          color: i <= _currentPage
                              ? AppColors.accentBlue
                              : AppColors.borderSubtle,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    );
                  }),
                ),
              ),

              // ── Pages ──
              Expanded(
                child: PageView(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  onPageChanged: (i) => setState(() => _currentPage = i),
                  children: [
                    _WelcomePage(),
                    _ApiKeyPage(
                      selectedProvider: _selectedProvider,
                      apiKeyController: _apiKeyController,
                      onProviderSelected: (p) =>
                          setState(() => _selectedProvider = p),
                    ),
                    _BridgePage(
                      isConnected: _bridgeConnected,
                      onTest: () =>
                          setState(() => _bridgeConnected = true),
                    ),
                    _ModelPage(
                      selectedModel: _selectedModel,
                      onModelSelected: (m) =>
                          setState(() => _selectedModel = m),
                    ),
                    _ProjectPage(
                      controller: _projectNameController,
                    ),
                  ],
                ),
              ),

              // ── Navigation buttons ──
              Padding(
                padding: const EdgeInsets.all(24),
                child: Row(
                  children: [
                    if (_currentPage > 0)
                      OutlinedButton(
                        onPressed: _previousPage,
                        child: const Text('Back'),
                      )
                    else
                      TextButton(
                        onPressed: () {
                          AppStorage.saveOnboarded(true);
                          context.go('/');
                        },
                        child: const Text('Skip'),
                      ),
                    const Spacer(),
                    ElevatedButton(
                      onPressed: _nextPage,
                      child: Text(
                        _currentPage == _totalPages - 1
                            ? 'Get Started'
                            : 'Continue',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────
//  Page 1: Welcome
// ─────────────────────────────────────────────────

class _WelcomePage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Logo.
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              gradient: AppColors.accentGlow,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: AppColors.accentBlue.withValues(alpha: 0.3),
                  blurRadius: 30,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: const Icon(
              Icons.auto_awesome_rounded,
              size: 64,
              color: Colors.white,
            ),
          )
              .animate()
              .fadeIn(duration: 500.ms)
              .scale(begin: const Offset(0.7, 0.7), curve: Curves.easeOutBack),

          const SizedBox(height: 32),

          Text(
            'Welcome to TermuxForge',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ).animate().fadeIn(delay: 200.ms, duration: 400.ms),

          const SizedBox(height: 16),

          Text(
            'A mobile-first agentic IDE powered by AI.\n'
            'Write code, debug, deploy — all from your phone.',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: AppColors.textSecondary,
              height: 1.6,
            ),
            textAlign: TextAlign.center,
          ).animate().fadeIn(delay: 400.ms, duration: 400.ms),

          const SizedBox(height: 40),

          // Feature highlights.
          ...[
            ('Multi-agent AI system', Icons.hub_rounded),
            ('11 specialized modes', Icons.grid_view_rounded),
            ('Deep Termux integration', Icons.terminal_rounded),
            ('MCP server support', Icons.electrical_services_rounded),
          ].indexed.map((entry) {
            final (i, (label, icon)) = entry;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 18, color: AppColors.accentBlue),
                  const SizedBox(width: 10),
                  Text(label, style: const TextStyle(fontSize: 15)),
                ],
              ),
            ).animate().fadeIn(
              delay: Duration(milliseconds: 500 + i * 100),
              duration: 300.ms,
            ).slideX(begin: 0.1, curve: Curves.easeOut);
          }),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────
//  Page 2: API Key
// ─────────────────────────────────────────────────

class _ApiKeyPage extends StatelessWidget {
  const _ApiKeyPage({
    required this.selectedProvider,
    required this.apiKeyController,
    required this.onProviderSelected,
  });

  final String? selectedProvider;
  final TextEditingController apiKeyController;
  final ValueChanged<String> onProviderSelected;

  @override
  Widget build(BuildContext context) {
    final providers = [
      ('Anthropic', Icons.auto_awesome_rounded, AppColors.accentPurple),
      ('OpenAI', Icons.psychology_rounded, AppColors.success),
      ('Google', Icons.diamond_rounded, AppColors.accentBlue),
      ('OpenRouter', Icons.route_rounded, AppColors.accentTeal),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 40),
          Text(
            'Connect an AI Provider',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Choose your primary provider and enter your API key.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 24),
          ...providers.map((p) {
            final (name, icon, color) = p;
            final isSelected = selectedProvider == name;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GlassCard(
                onTap: () => onProviderSelected(name),
                padding: const EdgeInsets.all(14),
                borderRadius: 14,
                borderColor: isSelected
                    ? color.withValues(alpha: 0.4)
                    : null,
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(icon, size: 22, color: color),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      name,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: isSelected
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                    const Spacer(),
                    if (isSelected)
                      Icon(Icons.check_circle_rounded,
                          size: 20, color: color),
                  ],
                ),
              ),
            );
          }),
          if (selectedProvider != null) ...[
            const SizedBox(height: 16),
            TextField(
              controller: apiKeyController,
              obscureText: true,
              decoration: InputDecoration(
                labelText: '$selectedProvider API Key',
                hintText: 'sk-...',
                prefixIcon: const Icon(Icons.key_rounded),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────
//  Page 3: Bridge Test
// ─────────────────────────────────────────────────

class _BridgePage extends StatelessWidget {
  const _BridgePage({required this.isConnected, required this.onTest});

  final bool isConnected;
  final VoidCallback onTest;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isConnected
                ? Icons.check_circle_rounded
                : Icons.terminal_rounded,
            size: 80,
            color: isConnected ? AppColors.success : AppColors.accentBlue,
          ),
          const SizedBox(height: 24),
          Text(
            'Termux Bridge',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isConnected
                ? 'Connection established! TermuxForge can now\n'
                    'execute commands and manage files.'
                : 'Test the connection to Termux to enable\n'
                    'command execution and file management.',
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          if (isConnected)
            StatusBadge(
              label: 'Connected',
              color: AppColors.success,
              pulsing: true,
              size: BadgeSize.large,
            )
          else
            ElevatedButton.icon(
              onPressed: onTest,
              icon: const Icon(Icons.wifi_tethering_rounded),
              label: const Text('Test Connection'),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────
//  Page 4: Model Selection
// ─────────────────────────────────────────────────

class _ModelPage extends StatelessWidget {
  const _ModelPage({
    required this.selectedModel,
    required this.onModelSelected,
  });

  final String selectedModel;
  final ValueChanged<String> onModelSelected;

  @override
  Widget build(BuildContext context) {
    final models = [
      ('Claude 4 Sonnet', 'Anthropic', 'Best balance of speed & quality'),
      ('Claude 4 Opus', 'Anthropic', 'Most capable, higher cost'),
      ('GPT-4.1', 'OpenAI', 'Strong coding, 1M context'),
      ('Gemini 2.5 Pro', 'Google', 'Deep thinking, 1M context'),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 40),
          Text(
            'Choose Default Model',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'You can change this per mode later.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 24),
          ...models.map((m) {
            final (name, provider, desc) = m;
            final isSelected = selectedModel == name;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GlassCard(
                onTap: () => onModelSelected(name),
                padding: const EdgeInsets.all(14),
                borderRadius: 14,
                borderColor: isSelected
                    ? AppColors.accentBlue.withValues(alpha: 0.4)
                    : null,
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: isSelected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '$provider — $desc',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (isSelected)
                      const Icon(Icons.check_circle_rounded,
                          size: 20, color: AppColors.accentBlue),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────
//  Page 5: First Project
// ─────────────────────────────────────────────────

class _ProjectPage extends StatelessWidget {
  const _ProjectPage({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.rocket_launch_rounded,
            size: 64,
            color: AppColors.accentBlue,
          ),
          const SizedBox(height: 24),
          Text(
            'Create Your First Project',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Or open an existing project directory.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 32),
          TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'Project Name',
              hintText: 'my_awesome_app',
              prefixIcon: Icon(Icons.folder_rounded),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.folder_open_rounded),
              label: const Text('Open Existing Project'),
            ),
          ),
        ],
      ),
    );
  }
}
