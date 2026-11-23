import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../l10n/app_localizations.dart';
import '../models/cash_receipt.dart';
import '../models/currency_definition.dart';
import '../screens/receipt_printer_settings_screen.dart';
import '../services/receipt_printer.dart';
import '../state/app_scope.dart';
import 'cash_panels.dart';

class ReceiptPrintButton extends StatefulWidget {
  const ReceiptPrintButton({
    required this.currency,
    required this.quantityFor,
    super.key,
  });

  final CurrencyDefinition currency;
  final int Function(Denomination) quantityFor;

  @override
  State<ReceiptPrintButton> createState() => _ReceiptPrintButtonState();
}

class _ReceiptPrintButtonState extends State<ReceiptPrintButton> {
  bool _printing = false;

  @override
  Widget build(BuildContext context) {
    final printer = AppScope.of(context).receiptPrinter;
    return ListenableBuilder(
      listenable: printer,
      builder: (context, _) => Tooltip(
        message: context.tr('receiptPrintTooltip'),
        child: OutlinedButton.icon(
          key: const ValueKey('receipt-print'),
          onPressed: _printing || printer.busy ? null : () => _print(printer),
          icon: _printing
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(LucideIcons.printer),
          label: Text(context.tr('receiptPrint')),
        ),
      ),
    );
  }

  Future<void> _print(ReceiptPrinter printer) async {
    if (_printing || printer.busy) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final receipt = CashReceipt.fromCount(
      title: context.tr('receiptPrintTitle'),
      currency: widget.currency,
      quantityFor: widget.quantityFor,
      header: (
        denomination: context.tr('denomination'),
        quantity: context.tr('quantity'),
        subtotal: context.tr('subtotal'),
      ),
      totalLabel: context.tr('total'),
    );
    final direction = Directionality.of(context);
    setState(() => _printing = true);
    try {
      if (printer.settings == null) {
        final configured = await Navigator.of(context).push<bool>(
          MaterialPageRoute(
              builder: (_) => const ReceiptPrinterSettingsScreen()),
        );
        if (!mounted || configured != true) return;
      }
      await printer.print(receipt, direction);
      _message('receiptSent');
    } on ReceiptPrinterException catch (error) {
      _message('receiptError-${error.code}');
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  void _message(String key) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        CashActionBar.feedback(context, context.tr(key)),
      );
    }
  }
}
