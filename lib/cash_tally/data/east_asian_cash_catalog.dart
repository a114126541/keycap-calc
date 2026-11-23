import '../models/currency_definition.dart';

final eastAsianCashCurrencies = <CurrencyDefinition>[
  _currency(
    code: 'CNY',
    name: 'Chinese yuan',
    symbol: '¥',
    notes: [10, 50, 100, 500, 1000, 2000, 5000, 10000],
    coins: [10, 50, 100],
  ),
  _currency(
    code: 'HKD',
    name: 'Hong Kong dollar',
    symbol: 'HK\$',
    notes: [1000, 2000, 5000, 10000, 50000, 100000],
    coins: [10, 20, 50, 100, 200, 500, 1000],
  ),
  _currency(
    code: 'MOP',
    name: 'Macanese pataca',
    symbol: 'MOP\$',
    notes: [1000, 2000, 5000, 10000, 50000, 100000],
    coins: [10, 20, 50, 100, 200, 500, 1000],
  ),
  _currency(
    code: 'TWD',
    name: 'New Taiwan dollar',
    symbol: 'NT\$',
    notes: [10000, 20000, 50000, 100000, 200000],
    coins: [50, 100, 500, 1000, 2000, 5000],
  ),
];

CurrencyDefinition _currency({
  required String code,
  required String name,
  required String symbol,
  required List<int> notes,
  required List<int> coins,
}) {
  Denomination denomination(int minorUnits, DenominationKind kind) {
    final value =
        (minorUnits / 100).toStringAsFixed(minorUnits % 100 == 0 ? 0 : 2);
    return Denomination(
      minorUnits: minorUnits,
      label: '$symbol$value',
      kind: kind,
    );
  }

  return CurrencyDefinition(
    code: code,
    name: name,
    symbol: symbol,
    symbolBefore: true,
    denominations: [
      for (final value in coins) denomination(value, DenominationKind.coin),
      for (final value in notes) denomination(value, DenominationKind.banknote),
    ],
  );
}
