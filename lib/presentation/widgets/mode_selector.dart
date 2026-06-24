/// TermuxForge — Mode Selector Widget
///
/// A horizontally scrollable or grid-based selector for the 11
/// operational modes. Each mode chip shows an icon, label, and
/// accent color. The active mode is visually emphasized with a
/// glow and filled background.
library;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import 'package:nexon/core/theme/app_colors.dart';

/// Definition of an operational mode.
class ForgeMode {
  const ForgeMode({
    required this.key,
    required this.label,
    required this.icon,
    required this.description,
  });

  final String key;
  final String label;
  final IconData icon;
  final String description;

  Color get color => AppColors.modeColor(key);
}

/// All available modes in TermuxForge.
const List<ForgeMode> allModes = [
  ForgeMode(
    key: 'code',
    label: 'Code',
    icon: Icons.code_rounded,
    description: 'Write and edit code with AI assistance',
  ),
  ForgeMode(
    key: 'architect',
    label: 'Architect',
    icon: Icons.architecture_rounded,
    description: 'Design system architecture and structure',
  ),
  ForgeMode(
    key: 'debug',
    label: 'Debug',
    icon: Icons.bug_report_rounded,
    description: 'Find and fix bugs with deep analysis',
  ),
  ForgeMode(
    key: 'ask',
    label: 'Ask',
    icon: Icons.question_answer_rounded,
    description: 'General Q&A without file modifications',
  ),
  ForgeMode(
    key: 'review',
    label: 'Review',
    icon: Icons.rate_review_rounded,
    description: 'Code review with suggestions',
  ),
  ForgeMode(
    key: 'deploy',
    label: 'Deploy',
    icon: Icons.rocket_launch_rounded,
    description: 'Build, test, and deploy workflows',
  ),
  ForgeMode(
    key: 'research',
    label: 'Research',
    icon: Icons.biotech_rounded,
    description: 'Deep research and analysis',
  ),
  ForgeMode(
    key: 'test',
    label: 'Test',
    icon: Icons.science_rounded,
    description: 'Generate and run tests',
  ),
  ForgeMode(
    key: 'document',
    label: 'Document',
    icon: Icons.description_rounded,
    description: 'Generate documentation',
  ),
  ForgeMode(
    key: 'security',
    label: 'Security',
    icon: Icons.shield_rounded,
    description: 'Security audit and hardening',
  ),
  ForgeMode(
    key: 'battle',
    label: 'Battle',
    icon: Icons.compare_arrows_rounded,
    description: 'Compare models side-by-side',
  ),
];

/// A chip-based mode selector.
///
/// ```dart
/// ModeSelector(
///   currentMode: 'code',
///   onModeChanged: (mode) => setState(() => _mode = mode),
/// )
/// ```
class ModeSelector extends StatelessWidget {
  /// Creates a [ModeSelector].
  const ModeSelector({
    required this.currentMode,
    required this.onModeChanged,
    super.key,
    this.compact = false,
    this.scrollDirection = Axis.horizontal,
  });

  /// Currently active mode key.
  final String currentMode;

  /// Callback when a mode is tapped.
  final ValueChanged<String> onModeChanged;

  /// Whether to use a compact layout (icon-only chips).
  final bool compact;

  /// Scroll direction.
  final Axis scrollDirection;

  @override
  Widget build(BuildContext context) {
    if (scrollDirection == Axis.vertical) {
      return _buildVerticalList(context);
    }

    return SizedBox(
      height: compact ? 40 : 46,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: allModes.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final mode = allModes[i];
          final isActive = mode.key == currentMode;
          return _ModeChip(
            mode: mode,
            isActive: isActive,
            compact: compact,
            onTap: () => onModeChanged(mode.key),
          ).animate(delay: (i * 30).ms).fadeIn(duration: 200.ms).slideX(
            begin: 0.1,
            end: 0,
            duration: 200.ms,
            curve: Curves.easeOut,
          );
        },
      ),
    );
  }

  Widget _buildVerticalList(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      itemCount: allModes.length,
      itemBuilder: (context, i) {
        final mode = allModes[i];
        final isActive = mode.key == currentMode;
        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: _ModeListTile(
            mode: mode,
            isActive: isActive,
            onTap: () => onModeChanged(mode.key),
          ),
        );
      },
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.mode,
    required this.isActive,
    required this.compact,
    required this.onTap,
  });

  final ForgeMode mode;
  final bool isActive;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 10 : 14,
            vertical: 8,
          ),
          decoration: BoxDecoration(
            color: isActive
                ? mode.color.withValues(alpha: 0.18)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isActive
                  ? mode.color.withValues(alpha: 0.4)
                  : AppColors.borderSubtle,
              width: isActive ? 1.5 : 0.8,
            ),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: mode.color.withValues(alpha: 0.2),
                      blurRadius: 8,
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                mode.icon,
                size: 16,
                color: isActive ? mode.color : AppColors.textSecondary,
              ),
              if (!compact) ...[
                const SizedBox(width: 6),
                Text(
                  mode.label,
                  style: TextStyle(
                    color: isActive ? mode.color : AppColors.textSecondary,
                    fontSize: 13,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ModeListTile extends StatelessWidget {
  const _ModeListTile({
    required this.mode,
    required this.isActive,
    required this.onTap,
  });

  final ForgeMode mode;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: ListTile(
        dense: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        selected: isActive,
        selectedTileColor: mode.color.withValues(alpha: 0.12),
        leading: Icon(mode.icon, color: isActive ? mode.color : null, size: 20),
        title: Text(
          mode.label,
          style: TextStyle(
            fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
            color: isActive ? mode.color : null,
            fontSize: 14,
          ),
        ),
        subtitle: Text(
          mode.description,
          style: const TextStyle(fontSize: 11),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        onTap: onTap,
      ),
    );
  }
}
