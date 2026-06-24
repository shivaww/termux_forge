/// TermuxForge — Glassmorphism Card Widget
///
/// A frosted-glass card with configurable blur, opacity, border
/// radius, and optional gradient overlay. Used throughout the app
/// for sidebars, info panels, and elevated surfaces.
library;

import 'dart:ui';

import 'package:flutter/material.dart';

import 'package:nexon/core/theme/app_colors.dart';

/// A premium glassmorphism card widget.
///
/// ```dart
/// GlassCard(
///   child: Text('Hello'),
///   borderRadius: 20,
///   blurAmount: 15,
/// )
/// ```
class GlassCard extends StatelessWidget {
  /// Creates a [GlassCard].
  const GlassCard({
    required this.child,
    super.key,
    this.borderRadius = 16,
    this.blurAmount = 12,
    this.opacity = 0.72,
    this.padding,
    this.margin,
    this.gradient,
    this.borderColor,
    this.width,
    this.height,
    this.onTap,
  });

  /// The widget to display inside the glass card.
  final Widget child;

  /// Corner radius of the card. Defaults to 16.
  final double borderRadius;

  /// Strength of the backdrop blur. Defaults to 12.
  final double blurAmount;

  /// Opacity of the background surface. Defaults to 0.72.
  final double opacity;

  /// Inner padding. Defaults to `EdgeInsets.all(16)`.
  final EdgeInsetsGeometry? padding;

  /// Outer margin.
  final EdgeInsetsGeometry? margin;

  /// Optional gradient overlay on the glass surface.
  final Gradient? gradient;

  /// Border color override. Uses [AppColors.glassBorder] by default.
  final Color? borderColor;

  /// Fixed width.
  final double? width;

  /// Fixed height.
  final double? height;

  /// Tap callback — makes the card tappable.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark
        ? AppColors.backgroundSecondary.withValues(alpha: opacity)
        : Colors.white.withValues(alpha: 0.85);
    final border =
        borderColor ?? (isDark ? AppColors.glassBorder : AppColors.borderSubtleLight);
    final highlightEdge =
        isDark ? AppColors.glassHighlight : Colors.white.withValues(alpha: 0.5);

    Widget card = ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurAmount, sigmaY: blurAmount),
        child: Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: surfaceColor,
            borderRadius: BorderRadius.circular(borderRadius),
            gradient: gradient,
            border: Border.all(color: border, width: 0.8),
            boxShadow: isDark
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
          ),
          // Top highlight edge for 3D effect.
          foregroundDecoration: BoxDecoration(
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border(top: BorderSide(color: highlightEdge, width: 0.5)),
          ),
          padding: padding ?? const EdgeInsets.all(16),
          child: child,
        ),
      ),
    );

    if (margin != null) {
      card = Padding(padding: margin!, child: card);
    }

    if (onTap != null) {
      return InkWell(
        borderRadius: BorderRadius.circular(borderRadius),
        onTap: onTap,
        child: card,
      );
    }

    return card;
  }
}
