import 'package:flutter/material.dart';

typedef KeyColors = ({Color fill, Color ink});

class HardwarePalette extends ThemeExtension<HardwarePalette> {
  const HardwarePalette({
    required this.label,
    required this.housing,
    required this.lcd,
    required this.digits,
    required this.operators,
    required this.utility,
    required this.clear,
    required this.equals,
    this.preferredMode = ThemeMode.light,
  });

  final String label;
  final Color housing;
  final Color lcd;
  final KeyColors digits, operators, utility, clear, equals;
  final ThemeMode preferredMode;

  static const lcdInk = Color(0xFF202923);

  static const ivoryDesk = HardwarePalette(
    label: 'Ivory Desk',
    housing: Color(0xFFE9E3D8),
    lcd: Color(0xFFCAD3B7),
    digits: (fill: Color(0xFF35383D), ink: Color(0xFFF8F6EE)),
    operators: (fill: Color(0xFFF9F4E9), ink: Color(0xFF272A2F)),
    utility: (fill: Color(0xFFBAC2E6), ink: Color(0xFF272B4E)),
    clear: (fill: Color(0xFFD97880), ink: Color(0xFF30191C)),
    equals: (fill: Color(0xFFD4DDF4), ink: Color(0xFF222B48)),
  );

  static const silverOrange = HardwarePalette(
    label: 'Silver Orange',
    housing: Color(0xFFCBCDD0),
    lcd: Color(0xFFDCE2E4),
    digits: (fill: Color(0xFFF7F7F4), ink: Color(0xFF303339)),
    operators: (fill: Color(0xFFDBDFE3), ink: Color(0xFF292F37)),
    utility: (fill: Color(0xFFE9EBED), ink: Color(0xFF343840)),
    clear: (fill: Color(0xFFF1D7D4), ink: Color(0xFF7B3331)),
    equals: (fill: Color(0xFFF08B59), ink: Color(0xFF3B2115)),
  );

  static const graphiteTeal = HardwarePalette(
    label: 'Graphite Teal',
    housing: Color(0xFF242729),
    lcd: Color(0xFFC7D0C7),
    digits: (fill: Color(0xFF383C40), ink: Color(0xFFF6F6F4)),
    operators: (fill: Color(0xFF9FA6AD), ink: Color(0xFF202629)),
    utility: (fill: Color(0xFF606B77), ink: Color(0xFFF5F6F8)),
    clear: (fill: Color(0xFF55C8B8), ink: Color(0xFF163732)),
    equals: (fill: Color(0xFFBEC7CE), ink: Color(0xFF21282D)),
    preferredMode: ThemeMode.dark,
  );

  static const vintageSilver = HardwarePalette(
    label: 'Vintage Silver',
    housing: Color(0xFFD4DAD9),
    lcd: Color(0xFFC1CEBF),
    digits: (fill: Color(0xFF2D3435), ink: Color(0xFFF8F8F2)),
    operators: (fill: Color(0xFF91A9AA), ink: Color(0xFF182526)),
    utility: (fill: Color(0xFF738989), ink: Color(0xFF10191A)),
    clear: (fill: Color(0xFF963F44), ink: Color(0xFFFFF1EE)),
    equals: (fill: Color(0xFFB5C7C3), ink: Color(0xFF1D2928)),
  );

  ThemeData applyTo(ThemeData theme) {
    final dark = theme.brightness == Brightness.dark;
    final matchesHousing = dark == (preferredMode == ThemeMode.dark);
    final surface = matchesHousing
        ? housing
        : Color.lerp(
            dark ? const Color(0xFF25272A) : const Color(0xFFE3E4E3),
            housing,
            0.12,
          )!;
    return theme.copyWith(
      scaffoldBackgroundColor: surface,
      colorScheme: theme.colorScheme.copyWith(surface: surface),
      extensions: [this],
    );
  }

  @override
  HardwarePalette copyWith() => this;

  @override
  HardwarePalette lerp(HardwarePalette? other, double t) =>
      t < 0.5 ? this : other ?? this;
}
