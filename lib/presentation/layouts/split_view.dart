/// TermuxForge — Resizable Split View Layout
///
/// Provides a two-pane resizable layout with a draggable divider.
/// Supports both horizontal and vertical orientations with minimum
/// size constraints and smooth drag animations.
library;

import 'package:flutter/material.dart';

import 'package:nexon/core/theme/app_colors.dart';

/// A resizable split view with a drag handle between two panes.
///
/// ```dart
/// SplitView(
///   direction: Axis.horizontal,
///   first: FileExplorer(),
///   second: CodeEditor(),
///   initialRatio: 0.25,
/// )
/// ```
class SplitView extends StatefulWidget {
  /// Creates a [SplitView].
  const SplitView({
    required this.first,
    required this.second,
    super.key,
    this.direction = Axis.horizontal,
    this.initialRatio = 0.5,
    this.minFirstSize = 120,
    this.minSecondSize = 120,
    this.dividerThickness = 6,
    this.dividerColor,
    this.onRatioChanged,
  });

  /// The first (left or top) pane.
  final Widget first;

  /// The second (right or bottom) pane.
  final Widget second;

  /// Split direction: horizontal puts panes side-by-side.
  final Axis direction;

  /// Initial size ratio of the first pane (0.0 – 1.0).
  final double initialRatio;

  /// Minimum pixel size for the first pane.
  final double minFirstSize;

  /// Minimum pixel size for the second pane.
  final double minSecondSize;

  /// Divider handle thickness.
  final double dividerThickness;

  /// Custom divider color.
  final Color? dividerColor;

  /// Callback when the ratio changes.
  final ValueChanged<double>? onRatioChanged;

  @override
  State<SplitView> createState() => _SplitViewState();
}

class _SplitViewState extends State<SplitView> {
  late double _ratio;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    _ratio = widget.initialRatio.clamp(0.1, 0.9);
  }

  void _onDragUpdate(DragUpdateDetails details, BoxConstraints constraints) {
    final total = widget.direction == Axis.horizontal
        ? constraints.maxWidth
        : constraints.maxHeight;
    final delta = widget.direction == Axis.horizontal
        ? details.delta.dx
        : details.delta.dy;

    final newRatio = (_ratio + delta / total).clamp(
      widget.minFirstSize / total,
      1.0 - widget.minSecondSize / total,
    );

    setState(() => _ratio = newRatio);
    widget.onRatioChanged?.call(_ratio);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final total = widget.direction == Axis.horizontal
            ? constraints.maxWidth
            : constraints.maxHeight;
        final firstSize = total * _ratio - widget.dividerThickness / 2;
        final secondSize =
            total * (1 - _ratio) - widget.dividerThickness / 2;

        final dividerColor =
            widget.dividerColor ?? AppColors.borderSubtle;

        final children = <Widget>[
          // First pane.
          SizedBox(
            width: widget.direction == Axis.horizontal ? firstSize : null,
            height: widget.direction == Axis.vertical ? firstSize : null,
            child: widget.first,
          ),

          // Divider handle.
          MouseRegion(
            cursor: widget.direction == Axis.horizontal
                ? SystemMouseCursors.resizeColumn
                : SystemMouseCursors.resizeRow,
            child: GestureDetector(
              onPanStart: (_) => setState(() => _isDragging = true),
              onPanEnd: (_) => setState(() => _isDragging = false),
              onPanUpdate: (d) => _onDragUpdate(d, constraints),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: widget.direction == Axis.horizontal
                    ? widget.dividerThickness
                    : null,
                height: widget.direction == Axis.vertical
                    ? widget.dividerThickness
                    : null,
                color: _isDragging
                    ? AppColors.accentBlue.withValues(alpha: 0.4)
                    : dividerColor,
                child: Center(
                  child: Container(
                    width: widget.direction == Axis.horizontal ? 2 : 24,
                    height: widget.direction == Axis.horizontal ? 24 : 2,
                    decoration: BoxDecoration(
                      color: _isDragging
                          ? AppColors.accentBlue
                          : AppColors.borderStrong,
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Second pane.
          SizedBox(
            width: widget.direction == Axis.horizontal ? secondSize : null,
            height: widget.direction == Axis.vertical ? secondSize : null,
            child: widget.second,
          ),
        ];

        if (widget.direction == Axis.horizontal) {
          return Row(children: children);
        }
        return Column(children: children);
      },
    );
  }
}

/// A collapsible panel wrapper that can hide a pane entirely.
///
/// ```dart
/// CollapsiblePanel(
///   isExpanded: _showSidebar,
///   expandedSize: 280,
///   direction: Axis.horizontal,
///   child: Sidebar(),
/// )
/// ```
class CollapsiblePanel extends StatelessWidget {
  /// Creates a [CollapsiblePanel].
  const CollapsiblePanel({
    required this.isExpanded,
    required this.child,
    super.key,
    this.expandedSize = 280,
    this.direction = Axis.horizontal,
    this.duration = const Duration(milliseconds: 250),
    this.curve = Curves.easeOutCubic,
  });

  /// Whether the panel is expanded.
  final bool isExpanded;

  /// Content of the panel.
  final Widget child;

  /// Size when expanded.
  final double expandedSize;

  /// Direction (horizontal = width, vertical = height).
  final Axis direction;

  /// Animation duration.
  final Duration duration;

  /// Animation curve.
  final Curve curve;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: duration,
      curve: curve,
      width: direction == Axis.horizontal ? (isExpanded ? expandedSize : 0) : null,
      height: direction == Axis.vertical ? (isExpanded ? expandedSize : 0) : null,
      child: isExpanded
          ? SizedBox(
              width: direction == Axis.horizontal ? expandedSize : null,
              height: direction == Axis.vertical ? expandedSize : null,
              child: child,
            )
          : const SizedBox.shrink(),
    );
  }
}
