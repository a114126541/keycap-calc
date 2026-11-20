import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:neumorphic_calculator/utils/hardware_palette.dart';

class ResultWidget extends StatelessWidget {
  final String result;
  final double fontScale;

  const ResultWidget(this.result, {super.key, this.fontScale = 1.0});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;
    final lcd = theme.extension<HardwarePalette>() != null;
    final formatError = result.toLowerCase().contains('error');
    final fontSize = (90 * fontScale).roundToDouble();
    return Align(
      alignment: Alignment.bottomRight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: AutoSizeText(
          result,
          style: TextStyle(
            fontSize: fontSize,
            letterSpacing: lcd ? 1.6 : null,
            fontFeatures: lcd ? const [FontFeature.tabularFigures()] : null,
            color: formatError
                ? (lcd ? const Color(0xFF882D27) : Colors.red)
                : lcd
                    ? HardwarePalette.lcdInk
                    : isDark
                        ? theme.iconTheme.color
                        : primaryColor,
          ),
          minFontSize: 12,
          maxFontSize: fontSize,
          maxLines: 1,
        ),
      ),
    );
  }
}
