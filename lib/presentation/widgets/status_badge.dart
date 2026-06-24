/// TermuxForge — Status Badge Widget
///
/// A small pill-shaped badge that displays a status label with an
/// optional leading icon. Supports a pulsing dot for "active" states
/// and three size variants.
library;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import 'package:nexon/core/theme/app_colors.dart';

/// Size variants for [StatusBadge].
enum BadgeSize { small, medium, large }

/// A color-coded status badge with optional icon and pulse animation.
///
/// ```dart
/// StatusBadge(
///   label: 'Running',
///   color: AppColors.success,
///   icon: Icons.play_arrow,
///   pulsing: true,
/// )
/// ```
class StatusBadge extends StatelessWidget {
  /// Creates a [StatusBadge].
  const StatusBadge({
    required this.label,
    required this.color,
    super.key,
    this.icon,
    this.pulsing = false,
    this.size = BadgeSize.medium,
    this.onTap,
  });

  /// The status text.
  final String label;

  /// Accent color for the badge.
  final Color color;

  /// Optional leading icon.
  final IconData? icon;

  /// Whether to show a pulsing dot (for active/running states).
  final bool pulsing;

  /// Size variant.
  final BadgeSize size;

  /// Optional tap handler.
  final VoidCallback? onTap;

  double get _fontSize => switch (size) {
    BadgeSize.small => 10,
    BadgeSize.medium => 12,
    BadgeSize.large => 14,
  };

  double get _iconSize => switch (size) {
    BadgeSize.small => 10,
    BadgeSize.medium => 14,
    BadgeSize.large => 16,
  };

  EdgeInsets get _padding => switch (size) {
    BadgeSize.small => const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    BadgeSize.medium => const EdgeInsets.symmetric(
      horizontal: 10,
      vertical: 4,
    ),
    BadgeSize.large => const EdgeInsets.symmetric(
      horizontal: 14,
      vertical: 6,
    ),
  };

  @override
  Widget build(BuildContext context) {
    final bgColor = color.withValues(alpha: 0.15);

    Widget badge = Container(
      padding: _padding,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (pulsing) ...[
            _PulsingDot(color: color, size: _iconSize * 0.6),
            SizedBox(width: _padding.left * 0.5),
          ] else if (icon != null) ...[
            Icon(icon, size: _iconSize, color: color),
            SizedBox(width: _padding.left * 0.5),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: _fontSize,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );

    if (onTap != null) {
      badge = InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: badge,
      );
    }

    return badge;
  }
}

/// A small animated dot that pulses to indicate activity.
class _PulsingDot extends StatelessWidget {
  const _PulsingDot({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 4),
        ],
      ),
    )
        .animate(onPlay: (c) => c.repeat(reverse: true))
        .scaleXY(end: 1.4, duration: 800.ms, curve: Curves.easeInOut)
        .fade(end: 0.5, duration: 800.ms);
  }
}
