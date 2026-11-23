import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:get/get.dart';
import 'package:neumorphic_calculator/cash_tally/l10n/app_localizations.dart';
import 'package:neumorphic_calculator/cash_tally/l10n/platform_localizations.dart';
import 'package:neumorphic_calculator/cash_tally/state/app_controller.dart';
import 'package:neumorphic_calculator/cash_tally/state/app_scope.dart';
import 'package:neumorphic_calculator/controllers/preference_controller.dart';
import 'package:neumorphic_calculator/controllers/theme_controller.dart';
import 'package:neumorphic_calculator/repo/database.dart';
import 'package:neumorphic_calculator/screens/dashboard_screen/dashboard_screen.dart';
import 'package:neumorphic_calculator/utils/bindings.dart';
import 'package:neumorphic_calculator/utils/const.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:system_theme/system_theme.dart';
import 'utils/enum.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (defaultTargetPlatform != TargetPlatform.android) {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }
  await SystemTheme.accentColor.load();
  await Get.putAsync<SharedPreferences>(
    () async => await SharedPreferences.getInstance(),
  );
  Get.put(DatabaseRepository(Get.find<SharedPreferences>()));
  Get.put(PreferencesController(Get.find<DatabaseRepository>()));

  // Load all the licenses for the fonts
  LicenseRegistry.addLicense(() async* {
    for (final font in Fonts.values) {
      final license = await font.license();
      yield LicenseEntryWithLineBreaks(['google_fonts'], license);
    }
  });
  LicenseRegistry.addLicense(() async* {
    final calculatorNotice = await rootBundle.loadString('LICENSE');
    yield LicenseEntryWithLineBreaks(
        ['Neumorphic Calculator'], calculatorNotice);
    final notice = await rootBundle.loadString(AppConst.cashTallyLicense);
    yield LicenseEntryWithLineBreaks(['Aardvarkland CashTally'], notice);
    final fonts =
        await rootBundle.loadString('assets/cash_tally/fonts/OFL.txt');
    yield LicenseEntryWithLineBreaks(['Cash tally report fonts'], fonts);
    final cjk = await rootBundle
        .loadString('assets/cash_tally/fonts/NotoSansSC-OFL.txt');
    yield LicenseEntryWithLineBreaks(['Noto Sans SC'], cjk);
  });

  runApp(const NeumorphicCalculatorApp());
}

class NeumorphicCalculatorApp extends StatefulWidget {
  const NeumorphicCalculatorApp({super.key});

  @override
  State<NeumorphicCalculatorApp> createState() =>
      _NeumorphicCalculatorAppState();
}

class _NeumorphicCalculatorAppState extends State<NeumorphicCalculatorApp> {
  late final AppController _cash =
      AppController(Get.find<DatabaseRepository>());

  @override
  void dispose() {
    _cash.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      controller: _cash,
      child: GetBuilder<ThemeController>(
        init: ThemeController(
          Get.find<DatabaseRepository>(),
          Get.find<PreferencesController>(),
        ),
        builder: (ctrl) => ListenableBuilder(
          listenable: _cash,
          builder: (context, _) {
            final locale = _cash.locale;
            // GetMaterialApp gives its cached locale precedence on rebuilds.
            Get.locale = locale;
            return GetMaterialApp(
              initialBinding: InitBindings(),
              debugShowCheckedModeBanner: false,
              title: AppConst.appName,
              themeMode: ctrl.themeMode,
              theme: ctrl.lightTheme,
              darkTheme: ctrl.darkTheme,
              locale: locale,
              supportedLocales: AppLocalizations.supportedLocales,
              localizationsDelegates: const [
                AppLocalizations.delegate,
                AppMaterialFallbackLocalizationsDelegate(),
                AppCupertinoFallbackLocalizationsDelegate(),
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              home: const DashboardScreen(),
            );
          },
        ),
      ),
    );
  }
}
