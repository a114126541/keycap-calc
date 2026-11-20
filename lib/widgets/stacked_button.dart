import 'package:flutter/material.dart';
import 'package:neumorphic_calculator/utils/enum.dart';
import 'package:neumorphic_calculator/widgets/neumorphic_button.dart';

class StackedButton extends StatelessWidget {
  const StackedButton({
    super.key,
    this.width,
    this.height,
    this.duration,
    this.onLongPress,
    this.boxShadow,
    this.backgroundColor,
    this.constraints,
    required this.firstChild,
    required this.secondChild,
    this.onFirstChildPressed,
    this.onSecondChildPressed,
    this.borderRadius = 12.0,
    this.keyStyle = KeyStyle.original,
  }) : _isVertical = false;

  const StackedButton.vertical({
    super.key,
    this.width,
    this.height,
    this.duration,
    this.onLongPress,
    this.boxShadow,
    this.backgroundColor,
    this.constraints,
    required this.firstChild,
    required this.secondChild,
    this.onFirstChildPressed,
    this.onSecondChildPressed,
    this.borderRadius = 12.0,
    this.keyStyle = KeyStyle.original,
  }) : _isVertical = true;

  final bool _isVertical;
  final VoidCallback? onLongPress, onFirstChildPressed, onSecondChildPressed;
  final double? width, height;
  final double borderRadius;
  final Duration? duration;
  final List<BoxShadow>? boxShadow;
  final Color? backgroundColor;
  final BoxConstraints? constraints;
  final Widget firstChild, secondChild;
  final KeyStyle keyStyle;

  @override
  Widget build(BuildContext context) {
    final radius = Radius.circular(borderRadius);
    final firstCorners = _isVertical
        ? BorderRadius.vertical(top: radius)
        : BorderRadius.horizontal(left: radius);
    final secondCorners = _isVertical
        ? BorderRadius.vertical(bottom: radius)
        : BorderRadius.horizontal(right: radius);
    final children = [
      _half(firstChild, onFirstChildPressed, firstCorners),
      _isVertical ? const SizedBox(height: 6) : const SizedBox(width: 6),
      _half(secondChild, onSecondChildPressed, secondCorners),
    ];
    return ConstrainedBox(
      constraints: constraints ??
          const BoxConstraints(
              minHeight: 55, minWidth: 55, maxHeight: 75, maxWidth: 75),
      child: _isVertical
          ? Column(mainAxisSize: MainAxisSize.min, children: children)
          : Row(mainAxisSize: MainAxisSize.min, children: children),
    );
  }

  Widget _half(Widget child, VoidCallback? onPressed, BorderRadius corners) {
    return Expanded(
      child: NeumorphicButton(
        constraints: const BoxConstraints(),
        width: width,
        height: height,
        duration: duration,
        onPressed: onPressed,
        onLongPress: onLongPress,
        backgroundColor: backgroundColor,
        boxShadow: boxShadow,
        keyStyle: keyStyle,
        cornerRadii: corners,
        child: child,
      ),
    );
  }
}
