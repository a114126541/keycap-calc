import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:neumorphic_calculator/calculator_icons.dart';
import 'package:neumorphic_calculator/utils/enum.dart';
import 'package:neumorphic_calculator/utils/hardware_palette.dart';
import 'package:neumorphic_calculator/widgets/neumorphic_button.dart';
import 'package:neumorphic_calculator/widgets/stacked_button.dart';

class NumberPad extends StatelessWidget {
  const NumberPad({
    super.key,
    this.onNumberPressed,
    this.onOperationPressed,
    this.equalsEnabled = true,
    this.keyStyle = KeyStyle.original,
    required this.borderRadius,
    required this.isLandscape,
  });

  final void Function(String number)? onNumberPressed;
  final void Function(CalculatorButton button)? onOperationPressed;
  final double borderRadius;
  final bool isLandscape;
  final bool equalsEnabled;
  final KeyStyle keyStyle;

  static const _portraitRows = [
    [
      CalculatorButton.allClear,
      CalculatorButton.openParenthesis,
      CalculatorButton.percent,
      CalculatorButton.divide,
    ],
    [
      CalculatorButton.seven,
      CalculatorButton.eight,
      CalculatorButton.nine,
      CalculatorButton.multiply,
    ],
    [
      CalculatorButton.four,
      CalculatorButton.five,
      CalculatorButton.six,
      CalculatorButton.subtract,
    ],
    [
      CalculatorButton.one,
      CalculatorButton.two,
      CalculatorButton.three,
      CalculatorButton.add,
    ],
    [
      CalculatorButton.zero,
      CalculatorButton.decimal,
      CalculatorButton.clear,
      CalculatorButton.equal,
    ],
  ];

  static const _landscapeRows = [
    [
      CalculatorButton.seven,
      CalculatorButton.eight,
      CalculatorButton.nine,
      CalculatorButton.clear,
      CalculatorButton.divide,
    ],
    [
      CalculatorButton.four,
      CalculatorButton.five,
      CalculatorButton.six,
      CalculatorButton.allClear,
      CalculatorButton.multiply,
    ],
    [
      CalculatorButton.one,
      CalculatorButton.two,
      CalculatorButton.three,
      CalculatorButton.percent,
      CalculatorButton.subtract,
    ],
    [
      CalculatorButton.openParenthesis,
      CalculatorButton.zero,
      CalculatorButton.decimal,
      CalculatorButton.equal,
      CalculatorButton.add,
    ],
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final hardware = theme.extension<HardwarePalette>();
    final rows = isLandscape ? _landscapeRows : _portraitRows;
    final columnCount = rows.first.length;
    return RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final gap = (constraints.biggest.shortestSide * 0.027)
                .clamp(4.0, 12.0)
                .toDouble();
            final keyWidth =
                (constraints.maxWidth - gap * (columnCount - 1)) / columnCount;
            final keyHeight =
                (constraints.maxHeight - gap * (rows.length - 1)) / rows.length;
            final keySize = math.min(keyWidth, keyHeight);
            final radius = math.min(borderRadius, math.max(0.0, keySize / 2));
            final numberSize = (keySize * 0.49).clamp(14.0, 44.0).toDouble();
            final operationSize = (keySize * 0.42).clamp(14.0, 38.0).toDouble();
            final numberStyle = TextStyle(
              color: colors.onSurface,
              fontSize: numberSize,
              fontWeight: FontWeight.bold,
            );
            final operationStyle = TextStyle(
              color: colors.onSurface,
              fontSize: operationSize,
              fontWeight: FontWeight.w900,
            );
            return Column(
              spacing: gap,
              children: [
                for (final row in rows)
                  Expanded(
                    child: Row(
                      spacing: gap,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final key in row)
                          Expanded(
                            child: _buildKey(
                              key,
                              radius: radius,
                              colors: colors,
                              hardware: hardware,
                              numberStyle: numberStyle,
                              operationStyle: operationStyle,
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildKey(
    CalculatorButton button, {
    required double radius,
    required ColorScheme colors,
    required HardwarePalette? hardware,
    required TextStyle numberStyle,
    required TextStyle operationStyle,
  }) {
    if (button == CalculatorButton.openParenthesis) {
      final style = operationStyle.copyWith(color: hardware?.utility.ink);
      return StackedButton(
        key: ValueKey(button),
        constraints: const BoxConstraints(),
        borderRadius: radius,
        keyStyle: keyStyle,
        backgroundColor: hardware?.utility.fill ?? colors.surfaceContainer,
        firstChild: Text('(', style: style),
        secondChild: Text(')', style: style),
        onFirstChildPressed: () => onOperationPressed?.call(button),
        onSecondChildPressed: () =>
            onOperationPressed?.call(CalculatorButton.closeParenthesis),
      );
    }

    final (icon, label) = switch (button) {
      CalculatorButton.percent => (CalculatorIcons.percentage, 'Percent'),
      CalculatorButton.divide => (CalculatorIcons.divide, 'Divide'),
      CalculatorButton.multiply => (CalculatorIcons.cancel, 'Multiply'),
      CalculatorButton.subtract => (CalculatorIcons.minus, 'Subtract'),
      CalculatorButton.add => (CalculatorIcons.plus, 'Add'),
      CalculatorButton.clear => (Icons.backspace, 'Backspace'),
      _ => (null, button.value),
    };
    final isNumber = button.isNumber;
    void onPressed() {
      if (isNumber) {
        onNumberPressed?.call(button.value);
      } else {
        onOperationPressed?.call(button);
      }
    }

    final isEnabled = button != CalculatorButton.equal || equalsEnabled;
    final VoidCallback? onLongPress =
        button == CalculatorButton.clear && onOperationPressed != null
            ? () => onOperationPressed!(CalculatorButton.allClear)
            : null;
    final (backgroundColor, foregroundColor) = hardware == null
        ? _standardColors(button, colors)
        : _hardwareColors(button, hardware);
    final baseStyle = isNumber || button == CalculatorButton.decimal
        ? numberStyle
        : operationStyle;
    final style = baseStyle.copyWith(color: foregroundColor);
    return Semantics(
      key: ValueKey(button),
      button: true,
      enabled: isEnabled,
      label: label,
      excludeSemantics: true,
      onTap: isEnabled ? onPressed : null,
      onLongPress: onLongPress,
      child: NeumorphicButton(
        constraints: const BoxConstraints(),
        borderRadius: radius,
        keyStyle: keyStyle,
        backgroundColor: backgroundColor,
        onPressed: isEnabled ? onPressed : null,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: icon == null
                ? Text(button.value, style: style)
                : Icon(icon, color: style.color, size: style.fontSize),
          ),
        ),
      ),
    );
  }

  (Color, Color) _standardColors(CalculatorButton button, ColorScheme colors) {
    return switch (button) {
      CalculatorButton.allClear => switch (colors.brightness) {
          Brightness.light => (
              const Color(0xFFFCE7E4),
              const Color(0xFF8F332D)
            ),
          Brightness.dark => (const Color(0xFF55302E), const Color(0xFFFFC3BB)),
        },
      CalculatorButton.equal when equalsEnabled => (
          colors.primary,
          colors.onPrimary,
        ),
      CalculatorButton.equal => (
          Color.alphaBlend(
            colors.primary.withValues(alpha: 0.16),
            colors.surfaceContainer,
          ),
          colors.onSurface.withValues(alpha: 0.38),
        ),
      CalculatorButton.percent ||
      CalculatorButton.divide ||
      CalculatorButton.multiply ||
      CalculatorButton.subtract ||
      CalculatorButton.add =>
        (colors.primaryContainer, colors.onPrimaryContainer),
      _ => (colors.surfaceContainer, colors.onSurface),
    };
  }

  (Color, Color) _hardwareColors(
      CalculatorButton button, HardwarePalette palette) {
    if (button == CalculatorButton.equal && !equalsEnabled) {
      return (
        Color.lerp(palette.digits.fill, palette.equals.fill, 0.20)!,
        Color.lerp(palette.digits.fill, palette.digits.ink, 0.42)!,
      );
    }
    final colors = switch (button) {
      CalculatorButton.allClear => palette.clear,
      CalculatorButton.equal => palette.equals,
      CalculatorButton.divide ||
      CalculatorButton.multiply ||
      CalculatorButton.subtract ||
      CalculatorButton.add =>
        palette.operators,
      CalculatorButton.clear || CalculatorButton.percent => palette.utility,
      _ => palette.digits,
    };
    return (colors.fill, colors.ink);
  }
}
