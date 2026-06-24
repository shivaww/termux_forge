/// TermuxForge — Custom App Bar
///
/// A themed app bar that displays the current mode indicator, active
/// model badge, project name, and quick-action buttons. Supports
/// both expanded and compact layouts.
library;

import 'package:flutter/material.dart';

import 'package:nexon/core/theme/app_colors.dart';
import 'package:nexon/presentation/widgets/status_badge.dart';

/// The primary app bar used across all screens.
///
/// ```dart
/// ForgeAppBar(
///   title: 'TermuxForge',
///   currentMode: 'code',
///   currentModel: 'Claude 4 Sonnet',
///   onMenuPressed: () {},
/// )
/// ```
class ForgeAppBar extends StatelessWidget implements PreferredSizeWidget {
  /// Creates a [ForgeAppBar].
  const ForgeAppBar({
    super.key,
    this.title,
    this.currentMode,
    this.currentModel,
    this.projectName,
    this.onMenuPressed,
    this.onModelTap,
    this.onModeTap,
    this.actions,
    this.leading,
    this.showBackButton = false,
    this.bottom,
  });

  /// Title text. Falls back to 'TermuxForge'.
  final String? title;

  /// The active mode key (e.g. `'code'`).
  final String? currentMode;

  /// The active model display name (e.g. `'Claude 4 Sonnet'`).
  final String? currentModel;

  /// The current project name.
  final String? projectName;

  /// Called when the hamburger menu is tapped.
  final VoidCallback? onMenuPressed;

  /// Called when the model badge is tapped.
  final VoidCallback? onModelTap;

  /// Called when the mode badge is tapped.
  final VoidCallback? onModeTap;

  /// Additional trailing action widgets.
  final List<Widget>? actions;

  /// Custom leading widget. Overrides menu icon.
  final Widget? leading;

  /// Whether to show a back arrow instead of the menu icon.
  final bool showBackButton;

  /// Optional bottom widget (e.g. tab bar).
  final PreferredSizeWidget? bottom;

  @override
  Size get preferredSize => Size.fromHeight(
    kToolbarHeight + (bottom?.preferredSize.height ?? 0),
  );

  @override
  Widget build(BuildContext context) {
    final modeColor =
        currentMode != null ? AppColors.modeColor(currentMode!) : null;

    return AppBar(
      leading: leading ??
          (showBackButton
              ? const BackButton()
              : (onMenuPressed != null
                  ? IconButton(
                      icon: const Icon(Icons.menu_rounded),
                      onPressed: onMenuPressed,
                      tooltip: 'Menu',
                    )
                  : null)),
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // App icon / project name.
          Text(
            title ?? projectName ?? 'TermuxForge',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
            ),
          ),

          // Mode badge.
          if (currentMode != null) ...[
            const SizedBox(width: 10),
            InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: onModeTap,
              child: StatusBadge(
                label: currentMode!.toUpperCase(),
                color: modeColor ?? AppColors.accentBlue,
                size: BadgeSize.small,
              ),
            ),
          ],

          // Model badge.
          if (currentModel != null) ...[
            const SizedBox(width: 8),
            InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: onModelTap,
              child: StatusBadge(
                label: currentModel!,
                color: AppColors.accentPurple,
                size: BadgeSize.small,
                icon: Icons.auto_awesome_rounded,
              ),
            ),
          ],
        ],
      ),
      actions: [
        ...?actions,
        // Quick command button.
        IconButton(
          icon: const Icon(Icons.terminal_rounded),
          onPressed: () {},
          tooltip: 'Quick Command',
        ),
        // Settings.
        IconButton(
          icon: const Icon(Icons.settings_outlined),
          onPressed: () {},
          tooltip: 'Settings',
        ),
        const SizedBox(width: 4),
      ],
      bottom: bottom,
    );
  }
}
