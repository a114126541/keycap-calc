import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:neumorphic_calculator/controllers/preference_controller.dart';
import 'package:neumorphic_calculator/main.dart';
import 'package:neumorphic_calculator/repo/database.dart';
import 'package:neumorphic_calculator/screens/calculator_screen/calculator_controller.dart';
import 'package:neumorphic_calculator/utils/const.dart';
import 'package:neumorphic_calculator/utils/enum.dart';
import 'package:neumorphic_calculator/utils/settings_model.dart';
import 'package:neumorphic_calculator/widgets/input_widget.dart';
import 'package:neumorphic_calculator/widgets/neumorphic_button.dart';
import 'package:neumorphic_calculator/widgets/number_pad.dart';
import 'package:neumorphic_calculator/widgets/result_widget.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('restores key style and keeps older preferences compatible', () {
    final settings = SettingsModel.normal().copyWith(
      themeColor: ThemeColor.vintageSilver,
      buttonRadius: 26,
      keyStyle: KeyStyle.lowProfile,
    );
    final saved = settings.toMap();
    expect(SettingsModel.fromMap(saved), settings);

    saved.remove('keyStyle');
    final legacy = SettingsModel.fromMap(saved);
    expect(legacy.keyStyle, KeyStyle.original);
    expect(legacy.themeColor, settings.themeColor);
    expect(legacy.buttonRadius, 26);
  });

  testWidgets(
      'hardware themes provide their own key colors and use the chosen radius',
      (tester) async {
    NeumorphicButton keyFor(CalculatorButton button) =>
        tester.widget<NeumorphicButton>(find.descendant(
          of: find.byKey(ValueKey(button)),
          matching: find.byType(NeumorphicButton),
        ));

    for (final preset in [
      ThemeColor.ivoryDesk,
      ThemeColor.silverOrange,
      ThemeColor.graphiteTeal,
      ThemeColor.vintageSilver,
    ]) {
      final palette = preset.hardware!;
      await tester.pumpWidget(MaterialApp(
        theme: preset.getTheme(const TextTheme()),
        home: const NumberPad(
          borderRadius: 20,
          isLandscape: true,
          keyStyle: KeyStyle.lowProfile,
        ),
      ));
      await tester.pumpAndSettle();

      final digit = keyFor(CalculatorButton.seven);
      expect(digit.backgroundColor, palette.digits.fill);
      expect(digit.borderRadius, 20);
      expect(digit.keyStyle, KeyStyle.lowProfile);
      expect(keyFor(CalculatorButton.allClear).backgroundColor,
          palette.clear.fill);
      expect(keyFor(CalculatorButton.percent).backgroundColor,
          palette.utility.fill);
      expect(
          keyFor(CalculatorButton.add).backgroundColor, palette.operators.fill);
      expect(
          keyFor(CalculatorButton.equal).backgroundColor, palette.equals.fill);
    }
  });

  testWidgets('fills operator keys and dims equals when disabled',
      (tester) async {
    NeumorphicButton keyFor(CalculatorButton button) =>
        tester.widget<NeumorphicButton>(find.descendant(
          of: find.byKey(ValueKey(button)),
          matching: find.byType(NeumorphicButton),
        ));

    for (final (preset, mode) in [
      (ThemeColor.lavenderPurple, Brightness.light),
      (ThemeColor.mintGreen, Brightness.light),
      (ThemeColor.oceanBlue, Brightness.dark),
      (ThemeColor.midnightAmber, Brightness.dark),
    ]) {
      final theme = preset.getTheme(const TextTheme(), brightness: mode);
      final colors = theme.colorScheme;
      for (final equalsEnabled in [true, false]) {
        await tester.pumpWidget(MaterialApp(
          theme: theme,
          home: NumberPad(
            borderRadius: 12,
            isLandscape: mode == Brightness.dark,
            equalsEnabled: equalsEnabled,
          ),
        ));
        await tester.pumpAndSettle();

        expect(keyFor(CalculatorButton.seven).backgroundColor,
            colors.surfaceContainer);
        expect(keyFor(CalculatorButton.add).backgroundColor,
            colors.primaryContainer);
        expect(keyFor(CalculatorButton.clear).backgroundColor,
            colors.surfaceContainer);
        expect(
          keyFor(CalculatorButton.allClear).backgroundColor,
          mode == Brightness.dark
              ? const Color(0xFF55302E)
              : const Color(0xFFFCE7E4),
        );
        final equals = keyFor(CalculatorButton.equal);
        expect(equals.onPressed != null, equalsEnabled);
        if (equalsEnabled) {
          expect(equals.backgroundColor, colors.primary);
        } else {
          expect(equals.backgroundColor, isNot(colors.primary));
        }
      }
    }
  });

  testWidgets('reflows every key while keeping = and both parentheses usable', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final operations = <CalculatorButton>[];
    final numbers = <String>[];

    for (final (size, columns, rows, style) in [
      (const Size(390, 460), 4, 5, KeyStyle.flat),
      (const Size(700, 184), 5, 4, KeyStyle.sculpted),
      (const Size(1088, 440), 5, 4, KeyStyle.glass),
    ]) {
      final isLandscape = columns == 5;
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(
        MaterialApp(
          home: NumberPad(
            isLandscape: isLandscape,
            borderRadius: 12,
            keyStyle: style,
            onNumberPressed: numbers.add,
            onOperationPressed: operations.add,
          ),
        ),
      );

      final centers = [
        for (final button in CalculatorButton.values)
          if (button != CalculatorButton.closeParenthesis)
            tester.getCenter(find.byKey(ValueKey(button))),
      ];
      expect(
        centers.map((point) => point.dx.round()).toSet(),
        hasLength(columns),
      );
      expect(centers.map((point) => point.dy.round()).toSet(), hasLength(rows));
      expect(find.text('='), findsOneWidget);
      await tester.tap(find.text('7'));
      await tester.tap(find.text('('));
      await tester.tap(find.text(')'));
      await tester.tap(find.text('='));
      final backspace = find.byKey(const ValueKey(CalculatorButton.clear));
      await tester.tap(backspace);
      await tester.longPress(backspace);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }

    expect(numbers, ['7', '7', '7']);
    expect(operations, [
      for (var layout = 0; layout < 3; layout++) ...[
        CalculatorButton.openParenthesis,
        CalculatorButton.closeParenthesis,
        CalculatorButton.equal,
        CalculatorButton.clear,
        CalculatorButton.allClear,
      ],
    ]);
  });

  testWidgets('keeps the current calculation when switching orientations',
      (tester) async {
    Get.testMode = true;
    addTearDown(Get.reset);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final allowRuntimeFetching = GoogleFonts.config.allowRuntimeFetching;
    addTearDown(() {
      GoogleFonts.config.allowRuntimeFetching = allowRuntimeFetching;
      Get.testMode = false;
    });
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({
      AppConst.firstRunKey: false,
      AppConst.firstCallKey: false,
    });
    PackageInfo.setMockInitialValues(
      appName: AppConst.appName,
      packageName: 'com.ragheb.neumorphic_calculator',
      version: '1.0.3',
      buildNumber: '3',
      buildSignature: '',
    );
    final repository =
        DatabaseRepository(await SharedPreferences.getInstance());
    Get.put(repository);
    Get.put(PreferencesController(repository));

    await tester.binding.setSurfaceSize(const Size(390, 780));
    await tester.pumpWidget(const NeumorphicCalculatorApp());
    await tester.pumpAndSettle();

    expect(
        tester.widget<NumberPad>(find.byType(NumberPad)).isLandscape, isFalse);
    await tester.tap(find.text('('));
    await tester.pumpAndSettle();
    for (final button in [
      CalculatorButton.seven,
      CalculatorButton.add,
      CalculatorButton.eight,
    ]) {
      await tester.tap(find.byKey(ValueKey(button)));
      await tester.pumpAndSettle();
    }
    final calculator = CalculatorController.instance;
    expect(calculator.exp, '(7+8');

    await tester.tap(find.text(')'));
    await tester.pumpAndSettle();
    expect(tester.widget<InputWidget>(find.byType(InputWidget)).fontScale,
        greaterThan(1.0));
    expect(tester.widget<ResultWidget>(find.byType(ResultWidget)).fontScale,
        greaterThan(1.0));

    await tester.binding.setSurfaceSize(const Size(720, 1280));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(NumberPad)), const Size(680, 700));

    await tester.binding.setSurfaceSize(const Size(700, 280));
    await tester.pumpAndSettle();
    expect(
        tester.widget<NumberPad>(find.byType(NumberPad)).isLandscape, isTrue);
    expect(tester.widget<InputWidget>(find.byType(InputWidget)).fontScale, 1.0);
    expect(
        tester.widget<ResultWidget>(find.byType(ResultWidget)).fontScale, 1.0);
    expect(calculator.exp, '(7+8)');
    expect(calculator.output, '15');
    expect(tester.takeException(), isNull);

    expect(
        tester.widget<NumberPad>(find.byType(NumberPad)).equalsEnabled, isTrue);
    await tester.tap(find.text('='));
    await tester.pumpAndSettle();
    expect(calculator.exp, '15');
    expect(tester.widget<NumberPad>(find.byType(NumberPad)).equalsEnabled,
        isFalse);
    await tester.tap(find.byKey(const ValueKey(CalculatorButton.add)));
    await tester.pumpAndSettle();
    expect(tester.widget<NumberPad>(find.byType(NumberPad)).equalsEnabled,
        isFalse);
    await tester.tap(find.text('2'));
    await tester.pumpAndSettle();
    expect(
        tester.widget<NumberPad>(find.byType(NumberPad)).equalsEnabled, isTrue);

    final backspace = find.byKey(const ValueKey(CalculatorButton.clear));
    await tester.tap(backspace);
    await tester.pumpAndSettle();
    expect(calculator.exp, '15+');
    expect(calculator.output, isEmpty);

    calculator.updateExpression('12345+2', 3);
    await tester.pumpAndSettle();
    expect(calculator.exp, '12,345+2');
    await tester.tap(backspace);
    await tester.pumpAndSettle();
    expect(calculator.exp, '1,345+2');
    expect(calculator.output, '1347');

    await tester.longPress(backspace);
    await tester.pumpAndSettle();
    expect(calculator.exp, isEmpty);
    expect(calculator.output, isEmpty);
    expect(tester.widget<NumberPad>(find.byType(NumberPad)).equalsEnabled,
        isFalse);
    await tester.tap(backspace);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('2'));
    await tester.pumpAndSettle();
    expect(calculator.exp, '2');

    await tester.tap(find.byKey(const ValueKey(CalculatorButton.allClear)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey(CalculatorButton.add)));
    await tester.pumpAndSettle();
    expect(calculator.exp, isEmpty);
    await tester.tap(find.byKey(const ValueKey(CalculatorButton.subtract)));
    await tester.pumpAndSettle();
    expect(calculator.exp, '-');
    expect(tester.widget<NumberPad>(find.byType(NumberPad)).equalsEnabled,
        isFalse);
    for (final button in [
      CalculatorButton.five,
      CalculatorButton.add,
      CalculatorButton.two,
    ]) {
      await tester.tap(find.byKey(ValueKey(button)));
      await tester.pumpAndSettle();
    }
    expect(calculator.exp, '-5+2');
    await tester.tap(find.text('='));
    await tester.pumpAndSettle();
    expect(calculator.exp, '-3');
  });
}
