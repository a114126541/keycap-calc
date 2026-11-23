import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:neumorphic_calculator/cash_tally/data/country_catalog.dart';
import 'package:neumorphic_calculator/cash_tally/data/currency_catalog.dart';
import 'package:neumorphic_calculator/cash_tally/l10n/app_localizations.dart';
import 'package:neumorphic_calculator/cash_tally/models/business_profile.dart';
import 'package:neumorphic_calculator/cash_tally/models/cash_count_session.dart';
import 'package:neumorphic_calculator/cash_tally/models/count_mode.dart';
import 'package:neumorphic_calculator/cash_tally/services/backup_service.dart';
import 'package:neumorphic_calculator/cash_tally/services/closing_report_service.dart';
import 'package:neumorphic_calculator/cash_tally/services/local_store.dart';
import 'package:neumorphic_calculator/cash_tally/state/app_controller.dart';
import 'package:neumorphic_calculator/cash_tally/widgets/denomination_row.dart';
import 'package:neumorphic_calculator/controllers/preference_controller.dart';
import 'package:neumorphic_calculator/main.dart';
import 'package:neumorphic_calculator/repo/database.dart';
import 'package:neumorphic_calculator/screens/calculator_screen/calculator_controller.dart';
import 'package:neumorphic_calculator/utils/const.dart';
import 'package:neumorphic_calculator/utils/enum.dart';
import 'package:neumorphic_calculator/utils/extensions/color_extension.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('supports the four regions and exact cash totals down to the fen', () {
    expect(
      {
        for (final id in ['CN', 'HK', 'MO', 'TW'])
          id: CountryCatalog.byId(id)?.currencyCode
      },
      {'CN': 'CNY', 'HK': 'HKD', 'MO': 'MOP', 'TW': 'TWD'},
    );
    for (final code in ['CNY', 'HKD', 'MOP', 'TWD']) {
      expect(CurrencyCatalog.byCode(code).banknotes, isNotEmpty);
      expect(CurrencyCatalog.byCode(code).coins, isNotEmpty);
    }

    final currency = CurrencyCatalog.byCode('CNY');
    final session = CashCountSession(
      id: 'cash-test',
      currencyCode: currency.code,
      createdAt: DateTime(2026),
      quantities: {'banknote_10000': 2, 'coin_100': 1, 'coin_10': 3},
    );
    expect(session.totalMinorUnits(currency), 20130);
    expect(
        currency.formatMinor(session.totalMinorUnits(currency),
            localeCode: 'zh-Hans'),
        '¥201.30');
  });

  test('settings and concurrent cash saves stay separate from calculator data',
      () async {
    SharedPreferences.setMockInitialValues({AppConst.historyKey: 'calculator'});
    final repository =
        DatabaseRepository(await SharedPreferences.getInstance());
    final directory =
        await Directory.systemTemp.createTemp('keycap-cash-test-');
    addTearDown(() => directory.delete(recursive: true));
    final store = LocalStore(documentsDirectoryProvider: () async => directory);
    final controller = AppController(repository, localStore: store);
    addTearDown(controller.dispose);

    const traditional =
        Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant');
    await controller.setDefaultLocale(traditional);
    await controller.selectCountry(CountryCatalog.byId('MO')!);
    await controller.toggleFavoriteCurrency('HKD');
    await controller.setDenominationVisible('MOP', 'coin_10', false);
    await Future.wait([
      for (final id in ['first', 'second'])
        controller.saveSession(CashCountSession(
          id: id,
          currencyCode: 'MOP',
          mode: CountMode.quick,
          createdAt: DateTime(2026),
          quantities: {'banknote_1000': 1},
        )),
    ]);

    final reloaded = AppController(repository, localStore: store);
    addTearDown(reloaded.dispose);
    await reloaded.loadHistory();
    expect(reloaded.selectedCountry.id, 'MO');
    expect(reloaded.selectedCurrencyCode, 'MOP');
    expect(reloaded.locale, traditional);
    expect(reloaded.favoriteCurrencyOrder, ['HKD']);
    expect(reloaded.isDenominationVisible('MOP', 'coin_10'), isFalse);
    expect(reloaded.sessions.map((session) => session.id),
        containsAll(['first', 'second']));
    expect(repository.get<String>(AppConst.historyKey), 'calculator');
  });

  test('generates a report with Chinese text and fractional cash', () async {
    final currency = CurrencyCatalog.byCode('CNY');
    final session = CashCountSession(
      id: 'report',
      currencyCode: 'CNY',
      mode: CountMode.quick,
      createdAt: DateTime(2026),
      quantities: {'coin_10': 3},
      note: '现金清点紀錄',
    );
    final bytes = await const ClosingReportService().buildPdf(
      session: session,
      currency: currency,
      locale: const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
    );
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
  });

  test('encrypted backup restores cash settings and merges saved counts',
      () async {
    SharedPreferences.setMockInitialValues({AppConst.historyKey: 'calculator'});
    final repository =
        DatabaseRepository(await SharedPreferences.getInstance());
    final directory = await Directory.systemTemp.createTemp('keycap-backup-');
    final store = LocalStore(documentsDirectoryProvider: () async => directory);
    final controller = AppController(repository, localStore: store);
    addTearDown(controller.dispose);
    addTearDown(() => directory.delete(recursive: true));

    const profile = BusinessProfile(businessName: 'Test shop');
    await controller.saveBusinessProfile(profile);
    await controller.selectCountry(CountryCatalog.byId('HK')!);
    await controller.toggleFavoriteCurrency('MOP');
    await controller.setDenominationVisible('CNY', 'banknote_10000', false);
    final record = CashCountSession.create('CNY', profile: profile);
    await controller.saveSession(record);

    final service = BackupService();
    const password = 'backup-test-password';
    final bytes = await service.encrypt(
      bundle: await controller.exportBackupData(),
      password: password,
    );
    await expectLater(
      service.decrypt(bytes: bytes, password: 'incorrect-password'),
      throwsA(anything),
    );
    final backup = await service.decrypt(bytes: bytes, password: password);
    await controller.saveBusinessProfile(const BusinessProfile());
    await controller.selectCountry(CountryCatalog.byId('TW')!);
    await controller.setDenominationVisible('CNY', 'banknote_10000', true);
    await controller.saveSession(record.copyWith(
      updatedAt: record.updatedAt.add(const Duration(seconds: 1)),
      note: 'A newer note',
    ));
    final extra = CashCountSession.create('TWD');
    await controller.saveSession(extra);
    await controller.restoreBackup(backup);

    final reloaded = AppController(repository, localStore: store);
    addTearDown(reloaded.dispose);
    await reloaded.loadHistory();
    expect(reloaded.businessProfile.businessName, profile.businessName);
    expect(reloaded.selectedCountry.id, 'HK');
    expect(reloaded.selectedCurrencyCode, 'HKD');
    expect(reloaded.favoriteCurrencyOrder, ['MOP']);
    expect(reloaded.isDenominationVisible('CNY', 'banknote_10000'), isFalse);
    expect(reloaded.sessions.map((session) => session.id),
        unorderedEquals([record.id, extra.id]));
    expect(reloaded.sessions.firstWhere((item) => item.id == record.id).note,
        'A newer note');
    expect(await store.readRestoreJournal(), isNull);
    expect(repository.get<String>(AppConst.historyKey), 'calculator');
  });

  test('cash text and control colors have readable contrast in every preset',
      () {
    const textTheme = TextTheme(
      bodySmall: TextStyle(color: Colors.black),
      bodyMedium: TextStyle(color: Colors.black),
      titleLarge: TextStyle(color: Colors.black),
    );
    void check(Color foreground, Color background, String name) {
      final luminances = [
        foreground.computeLuminance(),
        background.computeLuminance()
      ]..sort();
      expect((luminances.last + .05) / (luminances.first + .05),
          greaterThanOrEqualTo(4.5),
          reason: name);
    }

    for (final brightness in Brightness.values) {
      final themes = {
        for (final color in ThemeColor.values)
          color.name: color.getTheme(textTheme, brightness: brightness),
        'systemAccent':
            Colors.indigo.getTheme(textTheme, brightness: brightness),
      };
      for (final MapEntry(key: name, value: theme) in themes.entries) {
        final scheme = theme.colorScheme;
        final label = '$name / $brightness';
        check(theme.textTheme.bodyMedium!.color!, theme.scaffoldBackgroundColor,
            label);
        check(theme.textTheme.titleLarge!.color!, scheme.surfaceContainerLow,
            label);
        check(scheme.onSurfaceVariant, theme.scaffoldBackgroundColor, label);
        check(scheme.onPrimary, scheme.primary, label);
        check(scheme.onPrimaryContainer, scheme.primaryContainer, label);
        check(scheme.onSecondaryContainer, scheme.secondaryContainer, label);
        check(scheme.onTertiaryContainer, scheme.tertiaryContainer, label);
        check(scheme.onErrorContainer, scheme.errorContainer, label);
      }
    }
  });

  testWidgets(
      'switching and rotating keep the current expression and cash draft',
      (tester) async {
    Get.testMode = true;
    final previousFontSetting = GoogleFonts.config.allowRuntimeFetching;
    GoogleFonts.config.allowRuntimeFetching = false;
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      Get.reset();
      Get.testMode = false;
      GoogleFonts.config.allowRuntimeFetching = previousFontSetting;
    });
    SharedPreferences.setMockInitialValues({
      AppConst.firstRunKey: false,
      AppConst.firstCallKey: false,
    });
    PackageInfo.setMockInitialValues(
      appName: AppConst.appName,
      packageName: 'com.ragheb.neumorphic_calculator',
      version: '1.0.3',
      buildNumber: '1',
      buildSignature: '',
    );
    final repository =
        DatabaseRepository(await SharedPreferences.getInstance());
    Get.put(repository);
    Get.put(PreferencesController(repository));
    tester.view.physicalSize = const Size(360, 768);
    await tester.pumpWidget(const NeumorphicCalculatorApp());
    await tester.pumpAndSettle();

    for (final button in [
      CalculatorButton.seven,
      CalculatorButton.add,
      CalculatorButton.eight,
    ]) {
      await tester.tap(find.byKey(ValueKey(button)));
      await tester.pumpAndSettle();
    }

    final about = find.byTooltip('About');
    final aboutBefore = tester.getCenter(about);
    await tester.tap(find.byKey(const ValueKey('switch-to-cash-tally')));
    await tester.pumpAndSettle();
    expect(tester.getCenter(about), aboutBefore);
    expect(find.text('New quick count'), findsOneWidget);

    final currencySwitch = find.byKey(const ValueKey('count-currency-switch'));
    expect(find.text('CNY'), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    expect(tester.getCenter(currencySwitch).dx, greaterThan(180));
    expect(tester.getCenter(currencySwitch).dy,
        closeTo(tester.getCenter(find.text('New quick count')).dy, 2));
    await tester.tap(currencySwitch);
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(CheckedPopupMenuItem<String>, 'USD · US dollar'),
    );
    await tester.pumpAndSettle();
    expect(find.text('USD'), findsOneWidget);
    await tester.tap(currencySwitch);
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(CheckedPopupMenuItem<String>, 'CNY · Chinese yuan'),
    );
    await tester.pumpAndSettle();
    expect(find.text('CNY'), findsOneWidget);

    final hundred = find.byWidgetPredicate(
      (widget) =>
          widget is DenominationRow &&
          widget.denomination.minorUnits == 10000 &&
          widget.currency.code == 'CNY',
      skipOffstage: false,
    );
    await tester.ensureVisible(hundred);
    await tester.tap(find.descendant(
      of: hundred,
      matching: find.widgetWithIcon(IconButton, Icons.add),
    ));
    await tester.pumpAndSettle();

    tester.view.physicalSize = const Size(768, 432);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('cash-tally-two-panes'), skipOffstage: false),
      findsOneWidget,
    );
    expect(tester.widget<DenominationRow>(hundred).quantity, 1);
    expect(tester.getCenter(currencySwitch).dx, greaterThan(384));
    expect(tester.getCenter(currencySwitch).dy,
        closeTo(tester.getCenter(find.text('New quick count')).dy, 2));
    await tester.tap(find.byKey(const ValueKey('switch-to-calculator')));
    await tester.pumpAndSettle();
    expect(CalculatorController.instance.exp, '7+8');

    await tester.tap(find.byKey(const ValueKey('switch-to-cash-tally')));
    await tester.pumpAndSettle();
    expect(tester.widget<DenominationRow>(hundred).quantity, 1);

    tester.view.physicalSize = const Size(432, 768);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Default language'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('language-zh-Hant')));
    await tester.pumpAndSettle();
    expect(find.text('點鈔設定'), findsOneWidget);
    await tester.tap(find.text('點鈔設定'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('國家或地區'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('cash-region-HK')));
    await tester.pumpAndSettle();
    expect(find.text('HKD · 港幣'), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('快速新增點鈔'), findsOneWidget);
    expect(tester.widget<DenominationRow>(hundred).quantity, 1);
    expect(tester.takeException(), isNull);

    tester.view.physicalSize = const Size(1000, 620);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('新增專業收銀結算'));
    await tester.pumpAndSettle();
    expect(find.text('專業收銀結算'), findsOneWidget);
    expect(find.byKey(const ValueKey('cash-tally-two-panes')), findsOneWidget);
    await tester.tap(find.byTooltip('專業收銀結算說明'));
    await tester.pumpAndSettle();
    expect(find.text('核對實收與應收，記錄備用金、簽名並匯出報表。'), findsOneWidget);
    await tester.tap(find.text('關閉'));
    await tester.pumpAndSettle();

    expect(find.text('HKD'), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    expect(tester.getCenter(currencySwitch).dx, greaterThan(500));
    expect(tester.getCenter(currencySwitch).dy,
        closeTo(tester.getCenter(find.text('專業收銀結算')).dy, 2));
    await tester.tap(currencySwitch);
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(CheckedPopupMenuItem<String>, 'CNY · 人民幣'),
    );
    await tester.pumpAndSettle();
    expect(find.text('CNY'), findsOneWidget);
    expect(find.text('¥100'), findsOneWidget);

    expect(tester.getCenter(find.text('合計')).dx, lessThan(500));
    expect(tester.getCenter(find.text('儲存')).dx, greaterThan(500));
    final cashCheck = find.text('現金核對');
    final noteField = find.byWidgetPredicate((widget) =>
        widget is TextField && widget.decoration?.labelText == '備註');
    expect(tester.getCenter(cashCheck).dx, greaterThan(500));
    await tester.ensureVisible(noteField);
    await tester.enterText(noteField, 'Closing note');
    expect(tester.testTextInput.isVisible, isTrue);
    await tester.tap(find.text('紙幣').first);
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, isFalse);
    expect(find.text('Closing note'), findsOneWidget);

    tester.view.physicalSize = const Size(360, 800);
    await tester.pumpAndSettle();
    expect(find.text('CNY'), findsOneWidget);
    expect(tester.getCenter(currencySwitch).dx, greaterThan(180));
    expect(tester.takeException(), isNull);
  });

  test('separates simplified and traditional Chinese by script', () {
    const simplified = AppLocalizations(
      Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
    );
    const traditional = AppLocalizations(
      Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
    );
    expect(simplified.tr('cashTallySettings'), '点钞设置');
    expect(traditional.tr('cashTallySettings'), '點鈔設定');
    expect(traditional.tr('currencyMOP'), '澳門元');
  });
}
