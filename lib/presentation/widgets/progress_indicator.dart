/// TermuxForge — Custom Progress Indicators
///
/// Circular and linear progress widgets with percentage text,
/// gradient tracks, and smooth animations. Used for task progress,
/// todo completion, and cost tracking throughout the app.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:nexon/core/theme/app_colors.dart';

/// A circular progress indicator with centered percentage text.
///
/// ```dart
/// ForgeCircularProgress(
///   progress: 0.75,
///   size: 60,
///   label: '75%',
/// )
/// ```
class ForgeCircularProgress extends StatelessWidget {
  /// Creates a [ForgeCircularProgress].
  const ForgeCircularProgress({
    required this.progress,
    super.key,
    this.size = 56,
    this.strokeWidth = 4,
    this.label,
    this.color,
    this.trackColor,
    this.showPercentage = true,
    this.labelStyle,
  });

  /// Progress value between 0.0 and 1.0.
  final double progress;

  /// Diameter of the circle.
  final double size;

  /// Width of the progress arc.
  final double strokeWidth;

  /// Optional label override (defaults to percentage).
  final String? label;

  /// Progress color. Uses accent blue by default.
  final Color? color;

  /// Background track color.
  final Color? trackColor;

  /// Whether to show the percentage text in the center.
  final bool showPercentage;

  /// Text style override for the center label.
  final TextStyle? labelStyle;

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? AppColors.accentBlue;
    final effectiveTrack = trackColor ?? AppColors.borderSubtle;
    final pct = (progress.clamp(0.0, 1.0) * 100).round();

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Track.
          CustomPaint(
            painter: _ArcPainter(
              progress: 1.0,
              color: effectiveTrack,
              strokeWidth: strokeWidth,
            ),
          ),
          // Progress arc.
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: progress.clamp(0.0, 1.0)),
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOutCubic,
            builder: (_, value, __) => CustomPaint(
              painter: _ArcPainter(
                progress: value,
                color: effectiveColor,
                strokeWidth: strokeWidth,
              ),
            ),
          ),
          // Label.
          if (showPercentage || label != null)
            Center(
              child: Text(
                label ?? '$pct%',
                style: labelStyle ??
                    TextStyle(
                      color: effectiveColor,
                      fontSize: size * 0.22,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ArcPainter extends CustomPainter {
  _ArcPainter({
    required this.progress,
    required this.color,
    required this.strokeWidth,
  });

  final double progress;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: (size.shortestSide - strokeWidth) / 2,
    );
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(_ArcPainter old) =>
      old.progress != progress || old.color != color;
}

/// A linear progress bar with percentage label and optional gradient.
///
/// ```dart
/// ForgeLinearProgress(progress: 0.45, height: 6)
/// ```
class ForgeLinearProgress extends StatelessWidget {
  /// Creates a [ForgeLinearProgress].
  const ForgeLinearProgress({
    required this.progress,
    super.key,
    this.height = 6,
    this.color,
    this.trackColor,
    this.gradient,
    this.showPercentage = false,
    this.label,
    this.borderRadius = 100,
  });

  /// Progress value between 0.0 and 1.0.
  final double progress;

  /// Bar height.
  final double height;

  /// Fill color (overridden by [gradient] if provided).
  final Color? color;

  /// Track color.
  final Color? trackColor;

  /// Optional gradient fill.
  final Gradient? gradient;

  /// Whether to show percentage text beside the bar.
  final bool showPercentage;

  /// Optional label override.
  final String? label;

  /// Corner radius.
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? AppColors.accentBlue;
    final effectiveTrack = trackColor ?? AppColors.borderSubtle;
    final pct = (progress.clamp(0.0, 1.0) * 100).round();

    final bar = TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: progress.clamp(0.0, 1.0)),
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutCubic,
      builder: (_, value, __) => Container(
        height: height,
        decoration: BoxDecoration(
          color: effectiveTrack,
          borderRadius: BorderRadius.circular(borderRadius),
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: value,
            child: Container(
              decoration: BoxDecoration(
                color: gradient == null ? effectiveColor : null,
                gradient: gradient,
                borderRadius: BorderRadius.circular(borderRadius),
                boxShadow: [
                  BoxShadow(
                    color: effectiveColor.withValues(alpha: 0.4),
                    blurRadius: 6,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (!showPercentage && label == null) return bar;

    return Row(
      children: [
        Expanded(child: bar),
        const SizedBox(width: 8),
        Text(
          label ?? '$pct%',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
