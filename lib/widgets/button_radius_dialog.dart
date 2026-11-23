import 'package:flutter/material.dart';
import 'package:neumorphic_calculator/cash_tally/l10n/app_localizations.dart';
import 'package:neumorphic_calculator/utils/enum.dart';
import 'package:neumorphic_calculator/widgets/neumorphic_button.dart';

class ButtonRadiusDialog extends StatefulWidget {
  const ButtonRadiusDialog({
    super.key,
    required this.buttonRadius,
    this.keyStyle = KeyStyle.original,
  });

  final double buttonRadius;
  final KeyStyle keyStyle;

  @override
  State<ButtonRadiusDialog> createState() => _ButtonRadiusDialogState();
}

class _ButtonRadiusDialogState extends State<ButtonRadiusDialog> {
  late double buttonRadius;

  @override
  void initState() {
    buttonRadius = widget.buttonRadius;
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // When showing dialog in dark mode the text remians black, this is a workaround
    final titleTextStyle = theme.textTheme.headlineSmall?.copyWith(
      color: isDark ? Colors.white : Colors.black,
    );
    final contentTextStyle = theme.textTheme.bodyMedium?.copyWith(
      color: isDark ? Colors.white : Colors.black,
    );
    return AlertDialog(
      backgroundColor: theme.scaffoldBackgroundColor,
      title: Text(context.tr('keycapButtonRadius'), style: titleTextStyle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(context.tr('keycapRadiusHelp'), style: contentTextStyle),
          const SizedBox(height: 16),
          NeumorphicButton(
            border: Border.all(color: theme.splashColor, width: 0.5),
            borderRadius: buttonRadius,
            keyStyle: widget.keyStyle,
            child: Text(context.tr('keycapDemo'), style: contentTextStyle),
          ),
          const SizedBox(height: 16),
          Slider(
            divisions: 20,
            label: buttonRadius.toString(),
            value: buttonRadius,
            onChanged: (val) {
              setState(() {
                buttonRadius = val;
              });
            },
            max: 45,
            min: 5,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.tr('cancel')),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(12.0),
          child: Text(context.tr('keycapResetDefault')),
        ),
        TextButton(
          onPressed: () => Navigator.of(context)
              .pop(buttonRadius == widget.buttonRadius ? null : buttonRadius),
          child: Text(context.tr('save')),
        ),
      ],
    );
  }
}
