import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:neumorphic_calculator/cash_tally/l10n/app_localizations.dart';
import 'package:neumorphic_calculator/screens/dashboard_screen/dashboard_controller.dart';

class CalculatorModeButton extends StatelessWidget {
  const CalculatorModeButton({this.cashTallyActive = false, super.key});

  final bool cashTallyActive;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: ValueKey(
          cashTallyActive ? 'switch-to-calculator' : 'switch-to-cash-tally'),
      tooltip: context.tr(cashTallyActive ? 'keycapCalculator' : 'cashTally'),
      onPressed: DashboardController.instance.switchMode,
      icon:
          Icon(cashTallyActive ? LucideIcons.calculator : LucideIcons.banknote),
    );
  }
}
