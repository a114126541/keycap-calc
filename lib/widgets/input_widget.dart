import 'package:auto_size_text_field/auto_size_text_field.dart';
import 'package:flutter/material.dart';
import 'package:neumorphic_calculator/utils/extensions/theme_extension.dart';
import 'package:neumorphic_calculator/utils/hardware_palette.dart';

class InputWidget extends StatelessWidget {
  final TextEditingController controller;
  final bool compact;
  final double fontScale;

  const InputWidget(
    this.controller, {
    super.key,
    this.compact = false,
    this.fontScale = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    final lcd = theme.extension<HardwarePalette>() != null;
    final isDark = theme.isDarkMode;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final fontSize = (constraints.maxHeight * 0.76)
              .clamp(12.0, (compact ? 36.0 : 90.0) * fontScale)
              .floorToDouble();
          final standardColor = compact
              ? theme.colorScheme.onSurfaceVariant
              : isDark
                  ? primaryColor
                  : theme.iconTheme.color;
          final inputColor = lcd
              ? HardwarePalette.lcdInk.withValues(alpha: compact ? 0.79 : 1)
              : standardColor;
          return Align(
            alignment: Alignment.bottomRight,
            child: AutoSizeTextField(
              controller: controller,
              autofocus: true,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: fontSize,
                color: inputColor,
                letterSpacing: lcd ? 1 : null,
                fontFeatures: lcd ? const [FontFeature.tabularFigures()] : null,
              ),
              minFontSize: 12,
              maxFontSize: fontSize,
              maxLines: 1,
              cursorColor: lcd ? HardwarePalette.lcdInk : primaryColor,
              cursorWidth: 4,
              showCursor: true,
              readOnly: true,
              decoration: const InputDecoration.collapsed(
                hintText: '',
                border: InputBorder.none,
              ),
            ),
          );
        },
      ),
    );
  }
}
