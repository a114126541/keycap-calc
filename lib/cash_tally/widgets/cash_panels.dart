import 'package:flutter/material.dart';

import '../../utils/hardware_palette.dart';
import '../l10n/app_localizations.dart';
import '../models/currency_definition.dart';

const cashWorkspaceWidth = 1120.0;
const cashSplitWidth = 620.0;

class CashPanel extends StatelessWidget {
  const CashPanel({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Material(
      color: Color.lerp(
        theme.scaffoldBackgroundColor,
        colors.surfaceContainerLowest,
        0.6,
      ),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: child,
    );
  }
}

class CashActionBar extends StatelessWidget {
  const CashActionBar({required this.primary, this.secondary, super.key});

  final Widget primary;
  final Widget? secondary;

  static SnackBar feedback(BuildContext context, String message) {
    final visibleHeight = MediaQuery.sizeOf(context).height -
        MediaQuery.viewInsetsOf(context).bottom;
    return SnackBar(
      behavior: SnackBarBehavior.floating,
      margin: EdgeInsets.fromLTRB(16, 0, 16, visibleHeight >= 200 ? 72 : 8),
      content: Text(message),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final shape =
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(10));
    const minimumSize = Size(0, 48);
    const buttonPadding = EdgeInsets.symmetric(horizontal: 10, vertical: 8);
    final actionsTheme = theme.copyWith(
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: minimumSize,
          padding: buttonPadding,
          shape: shape,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: minimumSize,
          padding: buttonPadding,
          shape: shape,
          side: BorderSide(color: colors.primary),
          backgroundColor: colors.primaryContainer,
          foregroundColor: colors.onPrimaryContainer,
        ),
      ),
    );
    return Material(
      color: colors.surfaceContainerLow,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Divider(height: 1, thickness: 1, color: colors.outlineVariant),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            child: Theme(
              data: actionsTheme,
              child: Row(
                children: [
                  Expanded(child: primary),
                  if (secondary case final button?) ...[
                    const SizedBox(width: 10),
                    Expanded(child: button),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class CashAmountText extends StatelessWidget {
  const CashAmountText(
    this.value, {
    this.style,
    this.alignment = AlignmentDirectional.centerEnd,
    super.key,
  });

  final String value;
  final TextStyle? style;
  final AlignmentDirectional alignment;

  @override
  Widget build(BuildContext context) => FittedBox(
        fit: BoxFit.scaleDown,
        alignment: alignment,
        child: Text(
          value,
          maxLines: 1,
          style: (style ?? const TextStyle()).copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      );
}

class CashAmountHighlight extends StatelessWidget {
  const CashAmountHighlight({
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hardware = theme.extension<HardwarePalette>();
    final colors = theme.colorScheme;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: hardware?.lcd ?? colors.tertiaryContainer,
      ),
      padding: padding,
      child: DefaultTextStyle.merge(
        style: TextStyle(
          color: hardware == null
              ? colors.onTertiaryContainer
              : HardwarePalette.lcdInk,
        ),
        child: child,
      ),
    );
  }
}

class CashSummaryRows extends StatelessWidget {
  const CashSummaryRows({
    required this.currency,
    required this.quantityFor,
    this.spacious = false,
    super.key,
  });

  final CurrencyDefinition currency;
  final int Function(Denomination) quantityFor;
  final bool spacious;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          _row(
              context, currency.banknotes, 'banknotes', 'cashBanknoteQuantity'),
          const Divider(height: 1),
          _row(context, currency.coins, 'coins', 'cashCoinQuantity'),
        ],
      );

  Widget _row(BuildContext context, Iterable<Denomination> denominations,
      String label, String unitLabel) {
    var quantity = 0;
    var amount = 0;
    for (final item in denominations) {
      final count = quantityFor(item);
      quantity += count;
      amount += count * item.minorUnits;
    }
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 4, vertical: spacious ? 13 : 6),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(context.tr(label), style: theme.textTheme.titleMedium),
          ),
          Expanded(
            flex: 3,
            child: Text(
              context.tr(unitLabel, {'count': quantity}),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            flex: 5,
            child: CashAmountText(
              currency.formatMinor(amount,
                  localeCode: locale, fixedFractionDigits: true),
              style: (spacious
                      ? theme.textTheme.titleLarge
                      : theme.textTheme.titleMedium)
                  ?.copyWith(
                      fontWeight: FontWeight.w600,
                      height: spacious ? null : 1.2),
            ),
          ),
        ],
      ),
    );
  }
}
