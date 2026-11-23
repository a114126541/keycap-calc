import 'dart:math' as math;

import '../core/formatters.dart';
import 'currency_definition.dart';

typedef ReceiptRow = ({String denomination, String quantity, String subtotal});

class CashReceipt {
  CashReceipt.fromCount({
    required this.title,
    required CurrencyDefinition currency,
    required int Function(Denomination) quantityFor,
    required this.header,
    required String totalLabel,
  }) : currencyCode = currency.code {
    final counted = currency.denominations
        .map((denomination) =>
            (unit: denomination, count: quantityFor(denomination)))
        .where((item) => item.count > 0)
        .toList()
      ..sort((a, b) => b.unit.minorUnits.compareTo(a.unit.minorUnits));

    // Amounts share the currency code printed in the heading. Using the
    // number alone avoids mismatched currency symbols in printer fonts.
    String money(int minorUnits) => AppFormatters.moneyInputFromMinor(
          minorUnits,
          fractionDigits: currency.fractionDigits,
        );

    var totalMinorUnits = 0;
    rows = List.unmodifiable(counted.map((item) {
      final subtotal = item.unit.minorUnits * item.count;
      totalMinorUnits += subtotal;
      final faceValue = money(item.unit.minorUnits);
      return (
        denomination: item.unit.customId == null
            ? faceValue
            : '${_cleanLabel(item.unit.label)} ($faceValue)',
        quantity: item.count.toString(),
        subtotal: money(subtotal),
      );
    }));
    total = (label: totalLabel, amount: money(totalMinorUnits));
  }

  final String title;
  final String currencyCode;
  final ReceiptRow header;
  late final List<ReceiptRow> rows;
  late final ({String label, String amount}) total;

  List<ReceiptRow> get table => [header, ...rows];

  // Only tested single-byte ASCII and double-byte CJK glyphs reach this
  // layout. The raster path measures and wraps the actual system font.
  String? textLayout(int columns) {
    final data = table;
    final countWidth = data.map((row) => _cells(row.quantity)).reduce(math.max);
    final amountWidth =
        data.map((row) => _cells(row.subtotal)).reduce(math.max);
    final labelWidth = columns - countWidth - amountWidth - 2;
    if (_cells(title) > columns ||
        _cells(currencyCode) > columns ||
        data.any((row) => _cells(row.denomination) > labelWidth) ||
        _cells(total.label) + _cells(total.amount) + 1 > columns) {
      return null;
    }

    final rule = '-' * columns;
    return [
      title,
      currencyCode,
      rule,
      for (final row in data)
        '${_left(row.denomination, labelWidth)} '
            '${_right(row.quantity, countWidth)} '
            '${_right(row.subtotal, amountWidth)}',
      rule,
      '${_left(total.label, columns - _cells(total.amount))}${total.amount}',
    ].join('\n');
  }

  static String _cleanLabel(String label) =>
      label.replaceAll(RegExp(r'[\x00-\x1f\x7f-\x9f]'), ' ').trim();

  static int _cells(String value) =>
      value.runes.fold(0, (width, rune) => width + (rune < 128 ? 1 : 2));

  static String _left(String value, int width) =>
      '$value${' ' * (width - _cells(value))}';

  static String _right(String value, int width) =>
      '${' ' * (width - _cells(value))}$value';
}
