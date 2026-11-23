import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../core/formatters.dart';
import '../l10n/app_localizations.dart';
import '../models/currency_definition.dart';
import 'cash_panels.dart';

class DenominationRow extends StatelessWidget {
  const DenominationRow({
    required this.currency,
    required this.denomination,
    required this.quantity,
    required this.onChanged,
    required this.onEdit,
    this.step = 1,
    this.enabled = true,
    super.key,
  });

  static const stepperWidth = 142.0;

  final CurrencyDefinition currency;
  final Denomination denomination;
  final int quantity;
  final ValueChanged<int> onChanged;
  final VoidCallback onEdit;
  final int step;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final style =
        theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600);
    final decrease = (quantity - step).clamp(0, quantity);
    return InkWell(
      onTap: enabled ? () => onChanged(quantity + step) : null,
      onLongPress: enabled && quantity > 0 ? () => onChanged(decrease) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(denomination.label, style: style),
                  if (denomination.calculationWeightMilligrams != null)
                    Text(
                      AppFormatters.weight(
                        denomination.calculationWeightMilligrams,
                        localeCode: locale,
                        approximate: denomination.weightIsApproximate,
                        unavailableLabel: context.tr('weightUnavailable'),
                      ),
                      style: theme.textTheme.bodySmall,
                    ),
                ],
              ),
            ),
            SizedBox(
              width: stepperWidth,
              child: Row(
                children: [
                  _stepButton(
                    icon: LucideIcons.minus,
                    tooltip: '−',
                    onPressed: enabled && quantity > 0
                        ? () => onChanged(decrease)
                        : null,
                    background: colors.secondaryContainer,
                    foreground: colors.onSecondaryContainer,
                  ),
                  Expanded(
                    child: TextButton(
                      onPressed: enabled ? onEdit : null,
                      style: TextButton.styleFrom(
                        minimumSize: const Size(0, 48),
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        foregroundColor: colors.onSurface,
                      ),
                      child: CashAmountText(
                        '$quantity',
                        alignment: AlignmentDirectional.center,
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                  ),
                  _stepButton(
                    icon: LucideIcons.plus,
                    tooltip: '+',
                    onPressed:
                        enabled ? () => onChanged(quantity + step) : null,
                    background: colors.primaryContainer,
                    foreground: colors.onPrimaryContainer,
                  ),
                ],
              ),
            ),
            Expanded(
              child: CashAmountText(
                currency.formatMinor(denomination.minorUnits * quantity,
                    localeCode: locale),
                style: style,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stepButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
    required Color background,
    required Color foreground,
  }) =>
      SizedBox.square(
        dimension: 48,
        child: IconButton.filledTonal(
          tooltip: tooltip,
          onPressed: onPressed,
          style: IconButton.styleFrom(
            backgroundColor: background,
            foregroundColor: foreground,
            tapTargetSize: MaterialTapTargetSize.padded,
          ),
          icon: Icon(icon, size: 21),
        ),
      );
}
