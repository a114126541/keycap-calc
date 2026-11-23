import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:neumorphic_calculator/utils/extensions/color_extension.dart';
import 'package:neumorphic_calculator/utils/extensions/extensions.dart';
import 'package:neumorphic_calculator/utils/extensions/theme_extension.dart';
import 'package:neumorphic_calculator/utils/hardware_palette.dart';

enum KeyStyle {
  original('Original'),
  flat('Flat'),
  lowProfile('2.5D Keycap'),
  sculpted('3D Keycap'),
  glass('Frosted Glass');

  const KeyStyle(this.label);
  final String label;
}

enum CalculatorButton {
  allClear('AC'),
  openParenthesis('('),
  closeParenthesis(')'),
  percent('%'),
  divide('÷'),
  //
  seven('7'),
  eight('8'),
  nine('9'),
  multiply('x'),
  //
  four('4'),
  five('5'),
  six('6'),
  subtract('-'),
  //
  one('1'),
  two('2'),
  three('3'),
  add('+'),
  //
  zero('0'),
  decimal('.'),
  clear('C'),
  equal('=');

  final String value;
  const CalculatorButton(this.value);

  bool get isNumber => int.tryParse(value) != null;
}

enum Fonts {
  rubik,
  roboto,
  arsenal,
  montserrat,
  merriweather,
  ptSans,
  margarine,
  dancingScript,
  kodeMono,
  cabin,
  pacifico;

  TextTheme get textTheme {
    switch (this) {
      case Fonts.rubik:
        return GoogleFonts.rubikTextTheme();
      case Fonts.roboto:
        return GoogleFonts.robotoTextTheme();
      case Fonts.montserrat:
        return GoogleFonts.montserratTextTheme();
      case Fonts.arsenal:
        return GoogleFonts.arsenalTextTheme();
      case Fonts.merriweather:
        return GoogleFonts.merriweatherTextTheme();
      case Fonts.ptSans:
        return GoogleFonts.ptSansTextTheme();
      case Fonts.margarine:
        return GoogleFonts.margarineTextTheme();
      case Fonts.dancingScript:
        return GoogleFonts.dancingScriptTextTheme();
      case Fonts.kodeMono:
        return GoogleFonts.kodeMonoTextTheme();
      case Fonts.cabin:
        return GoogleFonts.cabinTextTheme();
      case Fonts.pacifico:
        return GoogleFonts.pacificoTextTheme();
    }
  }

  Future<String> license() async {
    switch (this) {
      case Fonts.rubik:
      case Fonts.arsenal:
      case Fonts.montserrat:
      case Fonts.merriweather:
      case Fonts.ptSans:
      case Fonts.margarine:
      case Fonts.dancingScript:
      case Fonts.kodeMono:
      case Fonts.cabin:
      case Fonts.pacifico:
        return await rootBundle.loadString(
            'assets/google_fonts/OFL-${name.toLowerCase().removeSpaces}.txt');

      case Fonts.roboto:
        return await rootBundle.loadString('assets/google_fonts/LICENSE.txt');
    }
  }

  ThemeData setToTheme(ThemeData theme) => theme.withSurfaceText(textTheme);
}

enum ThemeColor {
  sunsetOrange(Color(0xFFFF5E5B)),
  oceanBlue(Color(0xFF0077B6)),
  forestGreen(Color(0xFF2A9D8F)),
  lavenderPurple(Color(0xFF9D4EDD)),
  sunshineYellow(Color(0xFFFFD166)),
  coralPink(Color(0xFFFF6F61)),
  skyBlue(Color(0xFF00B4D8)),
  mintGreen(Color(0xFF3DDC97)),
  royalPurple(Color(0xFF7209B7)),
  goldenYellow(Color(0xFFFFC300)),
  blushRed(Color(0xFFE63946)),
  tealBlue(Color(0xFF008080)),
  peachOrange(Color(0xFFFFA07A)),
  emeraldGreen(Color(0xFF50C878)),
  midnightBlue(Color(0xFF191970)),
  // Stored settings use enum indices, so new presets are appended.
  midnightAmber(Color(0xFFEA9854)),
  ivoryDesk(Color(0xFF616A97), HardwarePalette.ivoryDesk),
  silverOrange(Color(0xFFAD5633), HardwarePalette.silverOrange),
  graphiteTeal(Color(0xFF288879), HardwarePalette.graphiteTeal),
  vintageSilver(Color(0xFF496E6B), HardwarePalette.vintageSilver);

  final Color color;
  final HardwarePalette? hardware;
  const ThemeColor(this.color, [this.hardware]);

  ThemeData getTheme(TextTheme textTheme, {Brightness? brightness}) {
    final theme = color.getTheme(textTheme, brightness: brightness);
    if (hardware case final palette?) return palette.applyTo(theme);
    if (this != midnightAmber || brightness != Brightness.dark) {
      return theme;
    }

    const background = Color(0xFF171614);
    return theme
        .copyWith(
          scaffoldBackgroundColor: background,
          colorScheme: theme.colorScheme.copyWith(
            surface: background,
            surfaceContainer: const Color(0xFF2A2724),
            onSurface: const Color(0xFFF4EFE9),
            onSurfaceVariant: const Color(0xFFC8BDB2),
            primary: const Color(0xFFFFC589),
            onPrimary: const Color(0xFF29180D),
            primaryContainer: const Color(0xFFD8894B),
            onPrimaryContainer: const Color(0xFF22150C),
          ),
          appBarTheme: theme.appBarTheme.copyWith(
            systemOverlayStyle: theme.appBarTheme.systemOverlayStyle?.copyWith(
              systemNavigationBarColor: background,
            ),
          ),
        )
        .withSurfaceText(textTheme);
  }
}
