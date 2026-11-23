import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:neumorphic_calculator/repo/database.dart';
import 'package:neumorphic_calculator/screens/settings_screen/settings_controller.dart';
import 'package:neumorphic_calculator/utils/const.dart';
import 'package:neumorphic_calculator/widgets/info_dialog.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('exits only after five quick version taps and confirmation',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: AppConst.appName,
      packageName: 'com.ragheb.neumorphic_calculator',
      version: '1.0.3',
      buildNumber: '3',
      buildSignature: '',
    );
    final repository =
        DatabaseRepository(await SharedPreferences.getInstance());
    Get.put(SettingsController(repository));
    addTearDown(Get.reset);

    var exitCalls = 0;
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'SystemNavigator.pop') exitCalls++;
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );

    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(platform: TargetPlatform.android),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => const InfoDialog(),
            ),
            child: const Text('About'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('About'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final version = find.text('${AppConst.appName} 1.0.3');
    final exitTitle = find.text('Exit ${AppConst.appName}');
    Future<void> tapVersion(int times) async {
      for (var tap = 0; tap < times; tap++) {
        await tester.tap(version);
        await tester.pump(const Duration(milliseconds: 200));
      }
    }

    await tapVersion(4);
    expect(exitTitle, findsNothing);
    await tester.pump(const Duration(seconds: 3));
    await tapVersion(4);
    expect(exitTitle, findsNothing);

    await tapVersion(1);
    await tester.pump(const Duration(milliseconds: 300));
    expect(exitTitle, findsOneWidget);
    expect(exitCalls, 0);

    await tester.tap(find.text('Cancel'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(exitTitle, findsNothing);
    expect(exitCalls, 0);

    await tapVersion(4);
    expect(exitTitle, findsNothing);
    await tapVersion(1);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Exit'));
    expect(exitCalls, 1);
  });
}
