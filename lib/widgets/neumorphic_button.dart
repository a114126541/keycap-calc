import 'package:flutter/material.dart';
import 'package:neumorphic_calculator/utils/enum.dart';
import 'package:neumorphic_calculator/utils/extensions/theme_extension.dart';

class NeumorphicButton extends StatefulWidget {
  const NeumorphicButton({
    super.key,
    this.onPressed,
    this.onLongPress,
    required this.child,
    this.width,
    this.height,
    this.borderRadius,
    this.duration,
    this.boxShadow,
    this.constraints,
    this.border,
    this.semanticLabel,
    this.backgroundColor,
    this.keyStyle = KeyStyle.original,
    this.cornerRadii,
  });

  final void Function()? onPressed;
  final void Function()? onLongPress;
  final double? width, height;
  final Duration? duration;
  final Widget child;
  final double? borderRadius;
  final List<BoxShadow>? boxShadow;
  final BoxConstraints? constraints;
  final BoxBorder? border;
  final String? semanticLabel;
  final Color? backgroundColor;
  final KeyStyle keyStyle;
  final BorderRadius? cornerRadii;

  @override
  State<NeumorphicButton> createState() => _NeumorphicButtonState();
}

class _NeumorphicButtonState extends State<NeumorphicButton> {
  bool _isElevated = true;

  void setElevated(bool value) {
    if (mounted) setState(() => _isElevated = value);
  }

  void _handleTap() {
    widget.onPressed?.call();
    Future.delayed(const Duration(milliseconds: 200), () => setElevated(true));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasTapAction = widget.onPressed != null;
    final depth = switch (widget.keyStyle) {
      KeyStyle.lowProfile => 3.0,
      KeyStyle.sculpted => 6.0,
      _ => 0.0,
    };

    final button = GestureDetector(
      onTapDown: hasTapAction ? (_) => setElevated(false) : null,
      onTapUp: hasTapAction ? (_) => _handleTap() : null,
      onTapCancel: hasTapAction ? () => setElevated(true) : null,
      onLongPress: widget.onLongPress,
      child: AnimatedContainer(
        alignment: Alignment.center,
        duration: widget.duration ?? const Duration(milliseconds: 200),
        height: widget.height,
        width: widget.width,
        constraints: widget.constraints ??
            const BoxConstraints(
                minHeight: 55, maxHeight: 75, minWidth: 55, maxWidth: 75),
        transform: _isElevated
            ? Matrix4.identity()
            : depth > 0
                ? Matrix4.translationValues(0, depth * 0.68, 0)
                : (Matrix4.identity()..scale(0.96)),
        decoration: _decoration(theme, depth),
        child: widget.child,
      ),
    );
    return widget.semanticLabel == null
        ? button
        : Semantics(label: widget.semanticLabel, button: true, child: button);
  }

  BoxDecoration _decoration(ThemeData theme, double depth) {
    final face = widget.backgroundColor ?? theme.scaffoldBackgroundColor;
    final corners = widget.cornerRadii ??
        BorderRadius.circular(widget.borderRadius ?? 18.0);
    if (widget.keyStyle == KeyStyle.original) {
      return BoxDecoration(
        border: widget.border,
        color: face,
        borderRadius: corners,
        boxShadow:
            _isElevated ? widget.boxShadow ?? theme.neumorphicShadows : null,
      );
    }

    final edge = Color.lerp(face, Colors.black, 0.48)!;
    if (widget.keyStyle == KeyStyle.flat) {
      return BoxDecoration(
        color: Color.lerp(face, edge, _isElevated ? 0 : 0.14),
        border:
            widget.border ?? Border.all(color: edge.withValues(alpha: 0.16)),
        borderRadius: corners,
      );
    }

    final glass = widget.keyStyle == KeyStyle.glass;
    final capDepth = _isElevated ? depth : depth * 0.25;
    return BoxDecoration(
      borderRadius: corners,
      border: widget.border ??
          Border.all(
            color: glass
                ? Colors.white.withValues(alpha: 0.58)
                : edge.withValues(alpha: 0.52),
          ),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        stops: const [0, 0.48, 1],
        colors: glass
            ? [
                Color.lerp(face, Colors.white, _isElevated ? 0.30 : 0.16)!
                    .withValues(alpha: 0.85),
                face.withValues(alpha: 0.74),
                Color.lerp(face, edge, 0.22)!.withValues(alpha: 0.82),
              ]
            : [
                Color.lerp(face, Colors.white, 0.15)!,
                face,
                Color.lerp(face, edge, _isElevated ? 0.16 : 0.28)!,
              ],
      ),
      boxShadow: glass
          ? [
              if (_isElevated)
                const BoxShadow(
                  color: Color(0x35000000),
                  offset: Offset(0, 2),
                  blurRadius: 7,
                ),
            ]
          : [
              BoxShadow(
                color: const Color(0x55000000),
                offset: Offset(0, capDepth + 1),
                blurRadius: depth + 1,
              ),
              BoxShadow(color: edge, offset: Offset(0, capDepth)),
            ],
    );
  }
}
