/// TermuxForge — Agent Avatar Widget
///
/// Displays a circular avatar for an agent with a type-specific icon,
/// a signature accent color, and an optional online/offline status
/// indicator dot.
library;

import 'package:flutter/material.dart';

import 'package:nexon/core/theme/app_colors.dart';

/// Size variants for [AgentAvatar].
enum AvatarSize { small, medium, large, xlarge }

/// A circular avatar representing an AI agent.
///
/// ```dart
/// AgentAvatar(agentType: 'coder', size: AvatarSize.medium)
/// ```
class AgentAvatar extends StatelessWidget {
  /// Creates an [AgentAvatar].
  const AgentAvatar({
    required this.agentType,
    super.key,
    this.size = AvatarSize.medium,
    this.showStatus = false,
    this.isActive = false,
    this.label,
  });

  /// The type key (e.g. `'coder'`, `'architect'`).
  final String agentType;

  /// Display size variant.
  final AvatarSize size;

  /// Whether to render a status dot.
  final bool showStatus;

  /// If [showStatus] is true, whether the agent is active.
  final bool isActive;

  /// Optional label override (first letter is displayed for `xlarge`).
  final String? label;

  double get _diameter => switch (size) {
    AvatarSize.small => 28,
    AvatarSize.medium => 36,
    AvatarSize.large => 48,
    AvatarSize.xlarge => 64,
  };

  double get _iconSize => switch (size) {
    AvatarSize.small => 14,
    AvatarSize.medium => 18,
    AvatarSize.large => 24,
    AvatarSize.xlarge => 32,
  };

  /// Maps agent type to an icon.
  static IconData agentIcon(String type) {
    return switch (type.toLowerCase()) {
      'orchestrator' => Icons.hub_rounded,
      'coder' => Icons.code_rounded,
      'architect' => Icons.architecture_rounded,
      'debugger' => Icons.bug_report_rounded,
      'reviewer' => Icons.rate_review_rounded,
      'devops' => Icons.rocket_launch_rounded,
      'researcher' => Icons.biotech_rounded,
      'tester' => Icons.science_rounded,
      'documenter' => Icons.description_rounded,
      'security' => Icons.shield_rounded,
      'background' => Icons.auto_awesome_rounded,
      _ => Icons.smart_toy_rounded,
    };
  }

  @override
  Widget build(BuildContext context) {
    final color = AppColors.agentColor(agentType);

    return SizedBox(
      width: _diameter + 4, // accommodate status dot
      height: _diameter + 4,
      child: Stack(
        children: [
          Center(
            child: Container(
              width: _diameter,
              height: _diameter,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    color.withValues(alpha: 0.25),
                    color.withValues(alpha: 0.10),
                  ],
                ),
                border: Border.all(
                  color: color.withValues(alpha: 0.4),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.2),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Center(
                child: Icon(
                  agentIcon(agentType),
                  size: _iconSize,
                  color: color,
                ),
              ),
            ),
          ),
          if (showStatus)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: _diameter * 0.3,
                height: _diameter * 0.3,
                decoration: BoxDecoration(
                  color: isActive ? AppColors.success : AppColors.textTertiary,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.backgroundPrimary,
                    width: 2,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
