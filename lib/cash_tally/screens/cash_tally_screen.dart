import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:neumorphic_calculator/screens/settings_screen/settings_screen.dart';
import 'package:neumorphic_calculator/utils/extensions/widget_extension.dart';
import 'package:neumorphic_calculator/widgets/calculator_mode_button.dart';
import 'package:neumorphic_calculator/widgets/info_dialog.dart';
import 'package:neumorphic_calculator/widgets/workspace_toolbar.dart';

import '../l10n/app_localizations.dart';
import '../models/count_mode.dart';
import '../models/till_template.dart';
import '../state/app_scope.dart';
import 'count_screen.dart';
import 'history_screen.dart' as cash_history;

class CashTallyScreen extends StatefulWidget {
  const CashTallyScreen({super.key});

  @override
  State<CashTallyScreen> createState() => _CashTallyScreenState();
}

class _CashTallyScreenState extends State<CashTallyScreen> {
  int _draftNumber = 0;

  @override
  void initState() {
    super.initState();
    AppScope.read(context).loadHistory();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final title = Text(context.tr('quickCountTitle'));
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth =
            constraints.maxWidth - MediaQuery.paddingOf(context).horizontal;
        final titleBelow = availableWidth < 560;
        return CountScreen(
          key: ValueKey(_draftNumber),
          initialCurrencyCode: app.selectedCurrencyCode,
          mode: CountMode.quick,
          onSaved: () => setState(() => _draftNumber++),
          toolbarBuilder: (currencyAction) => WorkspaceToolbar(
            title: titleBelow
                ? Row(children: [Expanded(child: title), currencyAction])
                : title,
            titleBelow: titleBelow,
            leading: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _toolbarAction(
                  tooltip: context.tr('settings'),
                  icon: LucideIcons.wrench,
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const SettingsScreen(showAppBar: true),
                    ),
                  ),
                ),
                _toolbarAction(
                  tooltip: context.tr('newProfessionalClose'),
                  icon: Icons.point_of_sale_outlined,
                  onPressed: _openProfessionalCount,
                ),
                _toolbarAction(
                  tooltip: context.tr('cashTallyHistory'),
                  icon: LucideIcons.history,
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const cash_history.HistoryScreen(),
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              if (!titleBelow) currencyAction,
              const CalculatorModeButton(cashTallyActive: true),
              IconButton(
                padding: const EdgeInsets.all(16),
                tooltip: context.tr('keycapAbout'),
                icon: const Icon(LucideIcons.info),
                onPressed: () => const InfoDialog().show(context),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _toolbarAction({
    required String tooltip,
    required IconData icon,
    required VoidCallback onPressed,
  }) =>
      SizedBox.square(
        dimension: kToolbarHeight,
        child: IconButton(
          tooltip: tooltip,
          icon: Icon(icon, size: 21),
          onPressed: onPressed,
        ),
      );

  Future<void> _openProfessionalCount() async {
    final app = AppScope.read(context);
    final templates = app.tillTemplates;
    TillTemplate? template;
    if (templates.isNotEmpty) {
      final choice = await showDialog<({TillTemplate? template})>(
        context: context,
        builder: (context) => SimpleDialog(
          title: Text(context.tr('tillTemplate')),
          children: [
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, (template: null)),
              child: Text(context.tr('withoutTemplate')),
            ),
            for (final item in templates)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, (template: item)),
                child: Text(item.name),
              ),
          ],
        ),
      );
      if (choice == null || !mounted) return;
      template = choice.template;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CountScreen(
          initialCurrencyCode:
              template?.currencyCode ?? app.selectedCurrencyCode,
          mode: CountMode.professional,
          template: template,
        ),
      ),
    );
  }
}
