import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:neumorphic_calculator/screens/settings_screen/settings_screen.dart';
import 'package:neumorphic_calculator/utils/extensions/widget_extension.dart';
import 'package:neumorphic_calculator/widgets/calculator_mode_button.dart';
import 'package:neumorphic_calculator/widgets/info_dialog.dart';
import 'package:neumorphic_calculator/widgets/workspace_toolbar.dart';

import '../l10n/app_localizations.dart';
import '../models/count_mode.dart';
import '../state/app_scope.dart';
import '../widgets/cash_panels.dart';
import 'count_screen.dart';
import 'history_screen.dart' as cash_history;

class CashTallyScreen extends StatefulWidget {
  const CashTallyScreen({super.key});

  @override
  State<CashTallyScreen> createState() => _CashTallyScreenState();
}

class _CashTallyScreenState extends State<CashTallyScreen> {
  int _draftNumber = 0;
  CountMode _mode = CountMode.quick;

  @override
  void initState() {
    super.initState();
    AppScope.read(context).loadHistory();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width =
            constraints.maxWidth - MediaQuery.paddingOf(context).horizontal;
        final portrait =
            MediaQuery.orientationOf(context) == Orientation.portrait;
        return CountScreen(
          key: ValueKey(_draftNumber),
          initialCurrencyCode: app.selectedCurrencyCode,
          mode: _mode,
          onSaved: () => setState(() => _draftNumber++),
          toolbarBuilder: (currencyAction) => WorkspaceToolbar(
            title: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: _modeSelector(),
              ),
            ),
            titleBelow: portrait || width < cashSplitWidth,
            leading: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _toolbarAction(
                  tooltip: context.tr('settings'),
                  icon: LucideIcons.settings,
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const SettingsScreen(showAppBar: true),
                    ),
                  ),
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
              currencyAction,
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

  Widget _modeSelector() {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Row(
          children: [
            for (final mode in CountMode.values)
              Expanded(
                child: Semantics(
                  selected: _mode == mode,
                  child: TextButton(
                    key: ValueKey('cash-mode-${mode.name}'),
                    onPressed: () {
                      if (mode == _mode) return;
                      FocusManager.instance.primaryFocus?.unfocus();
                      setState(() => _mode = mode);
                    },
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 44),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(9),
                      ),
                      backgroundColor:
                          _mode == mode ? colors.primaryContainer : null,
                      foregroundColor: _mode == mode
                          ? colors.onPrimaryContainer
                          : colors.onSurface,
                    ),
                    child: Text(
                      context.tr(mode == CountMode.quick
                          ? 'quickCount'
                          : 'professionalClose'),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
