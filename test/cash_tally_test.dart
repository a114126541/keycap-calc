import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:neumorphic_calculator/cash_tally/core/formatters.dart';
import 'package:neumorphic_calculator/cash_tally/data/country_catalog.dart';
import 'package:neumorphic_calculator/cash_tally/data/currency_catalog.dart';
import 'package:neumorphic_calculator/cash_tally/l10n/app_localizations.dart';
import 'package:neumorphic_calculator/cash_tally/models/business_profile.dart';
import 'package:neumorphic_calculator/cash_tally/models/cash_count_session.dart';
import 'package:neumorphic_calculator/cash_tally/models/count_mode.dart';
import 'package:neumorphic_calculator/cash_tally/models/currency_definition.dart';
import 'package:neumorphic_calculator/cash_tally/models/custom_denomination.dart';
import 'package:neumorphic_calculator/cash_tally/screens/count_screen.dart';
import 'package:neumorphic_calculator/cash_tally/screens/history_screen.dart'
    as cash_history;
import 'package:neumorphic_calculator/cash_tally/services/backup_service.dart';
import 'package:neumorphic_calculator/cash_tally/services/closing_report_service.dart';
import 'package:neumorphic_calculator/cash_tally/services/local_store.dart';
import 'package:neumorphic_calculator/cash_tally/state/app_controller.dart';
import 'package:neumorphic_calculator/cash_tally/state/app_scope.dart';
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

  testWidgets('invalid closing amounts block saving without losing the draft',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 620);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final repository =
        DatabaseRepository(await SharedPreferences.getInstance());
    final (directory, store, app, saved) = (await tester.runAsync(() async {
      final directory =
          await Directory.systemTemp.createTemp('keycap-closing-amounts-');
      final store =
          LocalStore(documentsDirectoryProvider: () async => directory);
      return (
        directory,
        store,
        AppController(repository, localStore: store),
        Completer<void>(),
      );
    }))!;
    addTearDown(() => directory.delete(recursive: true));
    addTearDown(app.dispose);

    await tester.pumpWidget(AppScope(
      controller: app,
      child: MaterialApp(
        localizationsDelegates: const [AppLocalizations.delegate],
        home: CountScreen(initialCurrencyCode: 'CNY', onSaved: saved.complete),
      ),
    ));
    await tester.pumpAndSettle();

    final expected = find.byKey(const ValueKey('cash-expected'));
    final float = find.byKey(const ValueKey('cash-float'));
    final save = find.text('Save');
    final summary = find.byKey(const ValueKey('cash-summary-list'));
    final summaryController = tester.widget<ListView>(summary).controller;
    await tester.scrollUntilVisible(
      expected,
      180,
      scrollable: find.byWidgetPredicate((widget) =>
          widget is Scrollable && widget.controller == summaryController),
    );
    await tester.enterText(expected, '100..20');
    await tester.ensureVisible(float);
    await tester.enterText(float, '1..234');
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(saved.isCompleted, isFalse);
    expect(app.sessions, isEmpty);
    expect(find.text('Enter a valid amount for Expected cash · Float to keep.'),
        findsOneWidget);
    expect(tester.widget<TextField>(expected).controller!.text, '100..20');
    expect(tester.widget<TextField>(float).controller!.text, '1..234');

    await tester.ensureVisible(expected);
    await tester.enterText(expected, '1,234.56');
    await tester.enterText(float, '');
    await tester.runAsync(() async {
      await tester.tap(save);
      await saved.future.timeout(const Duration(seconds: 4));
    });
    await tester.pumpAndSettle();

    final stored = (await tester.runAsync(store.loadSessions))!.single;
    expect(stored.expectedMinorUnits, 123456);
    expect(stored.floatMinorUnits, isNull);
  });

  testWidgets('cash quantity entry and steppers enforce count and total limits',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 620));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({});
    final repository =
        DatabaseRepository(await SharedPreferences.getInstance());
    final app = AppController(repository);
    addTearDown(app.dispose);
    await app.addCustomDenomination(const CustomDenomination(
      id: 'large-note',
      currencyCode: 'CNY',
      minorUnits: AppFormatters.maxMinorUnits,
      label: 'Large note',
      kind: DenominationKind.banknote,
    ));
    await tester.pumpWidget(AppScope(
      controller: app,
      child: const MaterialApp(
        localizationsDelegates: [AppLocalizations.delegate],
        home: CountScreen(initialCurrencyCode: 'CNY', mode: CountMode.quick),
      ),
    ));
    await tester.pumpAndSettle();

    const limitMessage = 'Reduce the quantity to keep the count within range.';
    final hundred = find.byWidgetPredicate((widget) =>
        widget is DenominationRow &&
        widget.denomination.id == 'banknote_10000');
    final large = find.widgetWithText(DenominationRow, 'Large note');
    Finder stepper(Finder row, IconData icon) => find.descendant(
        of: row, matching: find.widgetWithIcon(IconButton, icon));
    int quantity(Finder row) => tester.widget<DenominationRow>(row).quantity;

    await tester.tap(find.descendant(
      of: hundred,
      matching: find.widgetWithText(TextButton, '0'),
    ));
    await tester.pumpAndSettle();
    final quantityField = find.byType(TextFormField);
    final confirm = find.text('Confirm');
    await tester.enterText(quantityField, '1000000000000000');
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(find.text(limitMessage), findsOneWidget);
    expect(quantity(hundred), 0);

    final limit = CashCountSession.maxDenominationQuantity;
    await tester.enterText(quantityField, '$limit');
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(quantity(hundred), limit);
    await tester.tap(stepper(hundred, LucideIcons.plus));
    await tester.pumpAndSettle();
    expect(find.text(limitMessage), findsOneWidget);
    expect(quantity(hundred), limit);

    await tester.tap(stepper(large, LucideIcons.plus));
    await tester.pumpAndSettle();
    expect(quantity(large), 0);
    await tester.tap(find.descendant(
      of: hundred,
      matching: find.widgetWithText(TextButton, '$limit'),
    ));
    await tester.pumpAndSettle();
    await tester.enterText(quantityField, '0');
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    await tester.tap(stepper(large, LucideIcons.plus));
    await tester.pumpAndSettle();
    expect(quantity(large), 1);
    await tester.tap(stepper(hundred, LucideIcons.plus));
    await tester.pumpAndSettle();
    expect(quantity(hundred), 0);
    await tester.tap(stepper(large, LucideIcons.minus));
    await tester.pumpAndSettle();
    await tester.tap(stepper(hundred, LucideIcons.plus));
    await tester.pumpAndSettle();
    expect(quantity(hundred), 1);
    expect(tester.takeException(), isNull);
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
    final hapticRequests = <Object?>[];
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') {
        hapticRequests.add(call.arguments);
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
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
    expect(hapticRequests, contains('HapticFeedbackType.mediumImpact'));

    final about = find.byTooltip('About');
    final aboutBefore = tester.getCenter(about);
    await tester.tap(find.byKey(const ValueKey('switch-to-cash-tally')));
    await tester.pumpAndSettle();
    expect(tester.getCenter(about), aboutBefore);
    expect(find.text('Quick count'), findsOneWidget);

    final currencySwitch = find.byKey(const ValueKey('count-currency-switch'));
    expect(find.text('CNY'), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    expect(tester.getCenter(currencySwitch).dx, greaterThan(180));
    expect(tester.getCenter(currencySwitch).dy,
        lessThan(tester.getCenter(find.text('Quick count')).dy));
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
    final increase = find.descendant(
      of: hundred,
      matching: find.widgetWithIcon(IconButton, LucideIcons.plus),
    );
    await tester.tap(increase);
    await tester.pumpAndSettle();
    expect(hapticRequests, contains('HapticFeedbackType.selectionClick'));

    tester.view.physicalSize = const Size(768, 432);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('cash-tally-two-panes'), skipOffstage: false),
      findsOneWidget,
    );
    expect(tester.widget<DenominationRow>(hundred).quantity, 1);
    expect(tester.getCenter(currencySwitch).dx, greaterThan(384));
    expect(tester.getCenter(currencySwitch).dy,
        closeTo(tester.getCenter(find.text('Quick count')).dy, 2));
    await tester.tap(find.byKey(const ValueKey('switch-to-calculator')));
    await tester.pumpAndSettle();
    expect(CalculatorController.instance.exp, '7+8');

    await tester.tap(find.byKey(const ValueKey('switch-to-cash-tally')));
    await tester.pumpAndSettle();
    expect(tester.widget<DenominationRow>(hundred).quantity, 1);

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('settings-two-panes')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('settings-section-general')));
    await tester.pumpAndSettle();
    final hapticSwitch = find.byType(SwitchListTile);
    expect(tester.widget<SwitchListTile>(hapticSwitch).value, isTrue);
    await tester.tap(hapticSwitch);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(hapticSwitch).value, isFalse);

    final cashCategory = find.byKey(const ValueKey('settings-section-cash'));
    await tester.tap(cashCategory);
    await tester.pumpAndSettle();
    final categoryPosition = tester.getTopLeft(cashCategory);
    final cashDetail = find.byKey(const PageStorageKey('settings-detail-cash'));
    final detailScroll = tester.widget<ListView>(cashDetail).controller!;
    final backup = find.text('Manual backup and restore');
    await tester.ensureVisible(backup);
    await tester.pumpAndSettle();
    expect(detailScroll.offset, greaterThan(0));
    expect(backup.hitTestable(), findsOneWidget);
    expect(tester.getTopLeft(cashCategory), categoryPosition);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    final hapticCount = hapticRequests.length;
    await tester.tap(increase);
    await tester.pumpAndSettle();
    expect(tester.widget<DenominationRow>(hundred).quantity, 2);
    await tester.tap(find.descendant(
      of: hundred,
      matching: find.widgetWithIcon(IconButton, LucideIcons.minus),
    ));
    await tester.pumpAndSettle();
    expect(tester.widget<DenominationRow>(hundred).quantity, 1);
    expect(hapticRequests.length, hapticCount);

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
    expect(find.text('快速點鈔'), findsOneWidget);
    expect(tester.widget<DenominationRow>(hundred).quantity, 1);
    expect(tester.takeException(), isNull);

    tester.view.physicalSize = const Size(1000, 620);
    await tester.pumpAndSettle();
    final noteField = find.byKey(const ValueKey('cash-note'));
    await tester.ensureVisible(noteField);
    await tester.enterText(noteField, 'Closing note');
    expect(tester.testTextInput.isVisible, isTrue);
    await tester.tap(find.byKey(const ValueKey('cash-mode-professional')));
    await tester.pumpAndSettle();
    expect(find.text('專業收銀結算'), findsOneWidget);
    expect(find.byKey(const ValueKey('cash-tally-two-panes')), findsOneWidget);
    expect(tester.testTextInput.isVisible, isFalse);
    expect(find.text('CNY'), findsOneWidget);
    expect(tester.widget<DenominationRow>(hundred).quantity, 1);
    await tester.ensureVisible(find.text('結算詳情'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('結算詳情'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('專業收銀結算說明'));
    await tester.tap(find.byTooltip('專業收銀結算說明'));
    await tester.pumpAndSettle();
    expect(find.text('核對實收與應收，記錄備用金、簽名並匯出報表。'), findsOneWidget);
    await tester.tap(find.text('關閉'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('結算詳情'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('結算詳情'));
    await tester.pumpAndSettle();
    final summaryList = find.byKey(const ValueKey('cash-summary-list'));
    tester.widget<ListView>(summaryList).controller!.jumpTo(0);
    await tester.pumpAndSettle();
    expect(find.text('CNY'), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    expect(tester.getCenter(currencySwitch).dx, greaterThan(500));
    expect(tester.getCenter(currencySwitch).dy,
        closeTo(tester.getCenter(find.text('專業收銀結算')).dy, 2));
    expect(hundred, findsOneWidget);

    expect(tester.getCenter(find.text('合計')).dx, greaterThan(500));
    expect(tester.getCenter(find.text('儲存')).dx, greaterThan(500));
    final cashCheck = find.text('現金核對');
    expect(tester.getCenter(cashCheck).dx, greaterThan(500));
    final summaryController = tester.widget<ListView>(summaryList).controller;
    await tester.scrollUntilVisible(
      noteField,
      160,
      scrollable: find.byWidgetPredicate((widget) =>
          widget is Scrollable && widget.controller == summaryController),
    );
    await tester.pumpAndSettle();
    expect(
        tester.widget<TextField>(noteField).controller!.text, 'Closing note');
    await tester.tap(find.byKey(const ValueKey('cash-mode-quick')));
    await tester.pumpAndSettle();
    expect(find.text('現金核對'), findsNothing);
    expect(
        tester.widget<TextField>(noteField).controller!.text, 'Closing note');
    expect(tester.widget<DenominationRow>(hundred).quantity, 1);

    tester.view.physicalSize = const Size(360, 800);
    await tester.pumpAndSettle();
    expect(find.text('CNY'), findsOneWidget);
    expect(tester.getCenter(currencySwitch).dx, greaterThan(180));
    expect(tester.takeException(), isNull);
  });

  testWidgets('cash history filters keep the matching record open on rotation',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(960, 540);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final repo = DatabaseRepository(await SharedPreferences.getInstance());
    final dir = Directory.systemTemp.createTempSync('keycap-history-ui-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final today = DateUtils.dateOnly(DateTime.now());
    final yesterday = DateUtils.addDaysToDate(today, -1);
    final app = (await tester.runAsync(() async {
      final app = AppController(
        repo,
        localStore: LocalStore(documentsDirectoryProvider: () async => dir),
      );
      await app.saveSession(CashCountSession(
        id: 'hong-kong',
        currencyCode: 'HKD',
        createdAt: yesterday.add(const Duration(hours: 16)),
        documentNumber: 'KC-HK-01',
        note: 'Hong Kong counter',
        mode: CountMode.quick,
      ));
      await app.saveSession(CashCountSession(
        id: 'closing',
        currencyCode: 'CNY',
        createdAt: today.add(const Duration(hours: 17)),
        documentNumber: 'KC-CN-02',
        note: 'Evening shift',
        expectedMinorUnits: 20000,
        quantities: {'banknote_10000': 1},
      ));
      return app;
    }))!;
    addTearDown(app.dispose);
    await tester.pumpWidget(AppScope(
      controller: app,
      child: const MaterialApp(
        localizationsDelegates: [AppLocalizations.delegate],
        home: cash_history.HistoryScreen(),
      ),
    ));
    await tester.pumpAndSettle();

    const tr = AppLocalizations(Locale('en'));
    final twoPanes = find.byKey(const ValueKey('cash-history-two-panes'));
    final china = find.byKey(const ValueKey('cash-record-closing'));
    final hongKong = find.byKey(const ValueKey('cash-record-hong-kong'));
    final search = find.byKey(const ValueKey('cash-history-search'));
    final clear = find.byTooltip(tr.tr('clearFilters'));
    expect(twoPanes, findsOneWidget);
    expect(
        tester.getTopLeft(china).dy, lessThan(tester.getTopLeft(hongKong).dy));
    expect(find.text('Evening shift'), findsOneWidget);

    await tester.enterText(search, 'KC-HK-01');
    await tester.pumpAndSettle();
    expect(china, findsNothing);
    expect(find.text('Hong Kong counter'), findsOneWidget);
    await tester.tap(clear);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('cash-history-currency')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckedPopupMenuItem<String>, 'HKD'));
    await tester.pumpAndSettle();
    expect(hongKong, findsOneWidget);
    expect(china, findsNothing);
    await tester.tap(clear);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('cash-history-differences')));
    await tester.pumpAndSettle();
    expect(china, findsOneWidget);
    expect(hongKong, findsNothing);
    await tester.tap(clear);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('cash-history-date')));
    await tester.pumpAndSettle();
    final picker = find.byType(DateRangePickerDialog);
    expect(picker, findsOneWidget);
    Navigator.of(tester.element(picker))
        .pop(DateTimeRange(start: yesterday, end: yesterday));
    await tester.pumpAndSettle();
    expect(hongKong, findsOneWidget);
    expect(china, findsNothing);
    await tester.tap(clear);
    await tester.pumpAndSettle();

    tester.view.physicalSize = const Size(360, 800);
    await tester.pumpAndSettle();
    expect(twoPanes, findsNothing);
    await tester.tap(hongKong);
    await tester.pumpAndSettle();
    expect(search, findsNothing);
    expect(find.text('Hong Kong counter'), findsOneWidget);
    final report = find.text(tr.tr('openReport'));
    final print = find.byKey(const ValueKey('receipt-print'));
    expect(tester.getCenter(report).dx, lessThan(tester.getCenter(print).dx));
    expect(tester.getCenter(report).dy, closeTo(tester.getCenter(print).dy, 2));
    expect(tester.getCenter(print).dy, greaterThan(730));

    await tester.tap(find.byKey(const ValueKey('cash-record-actions')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(tr.tr('delete')));
    await tester.pumpAndSettle();
    expect(find.text(tr.tr('deleteTitle')), findsOneWidget);
    await tester.tap(find.text(tr.tr('keep')));
    await tester.pumpAndSettle();

    tester.view.physicalSize = const Size(960, 540);
    await tester.pumpAndSettle();
    expect(twoPanes, findsOneWidget);
    expect(find.text('Hong Kong counter'), findsOneWidget);
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
