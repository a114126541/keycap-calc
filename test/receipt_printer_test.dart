import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neumorphic_calculator/cash_tally/data/currency_catalog.dart';
import 'package:neumorphic_calculator/cash_tally/models/cash_receipt.dart';
import 'package:neumorphic_calculator/cash_tally/models/currency_definition.dart';
import 'package:neumorphic_calculator/cash_tally/models/receipt_printer_settings.dart';
import 'package:neumorphic_calculator/cash_tally/services/esc_pos_receipt.dart';
import 'package:neumorphic_calculator/cash_tally/services/receipt_printer.dart';
import 'package:neumorphic_calculator/repo/database.dart';
import 'package:shared_preferences/shared_preferences.dart';

const channel = MethodChannel('keycap_calc/receipt_printer');

const printer = ReceiptPrinterSettings(
  connection: ReceiptConnection.usb,
  address: 'test-port',
  port: 9100,
  paper: ReceiptPaper.narrow,
  encoding: ReceiptEncoding.ascii,
  imageCommand: ReceiptImageCommand.raster,
);

const defaultFinish = [0x1d, 0x50, 0, 203, 0x1b, 0x4a, 240, 0x1d, 0x56, 66, 0];

CashReceipt countedReceipt({bool customLabel = false}) {
  final cny = CurrencyCatalog.byCode('CNY');
  final custom = Denomination(
    minorUnits: 10,
    label: '自訂\n面額',
    kind: DenominationKind.coin,
    customId: 'test-coin',
  );
  return CashReceipt.fromCount(
    title: 'Cash count',
    currency: customLabel
        ? cny.copyWithDenominations([...cny.denominations, custom])
        : cny,
    quantityFor: (item) {
      if (item.isBanknote && item.minorUnits == 10000) return 2;
      if (customLabel && item.id == custom.id) return 3;
      return !customLabel && !item.isBanknote && item.minorUnits == 10 ? 3 : 0;
    },
    header: (
      denomination: 'Denomination',
      quantity: 'Quantity',
      subtotal: 'Subtotal'
    ),
    totalLabel: 'Total',
  );
}

Future<ReceiptPrinter> configuredPrinter(
    ReceiptPrinterSettings settings) async {
  SharedPreferences.setMockInitialValues({});
  final repository = DatabaseRepository(await SharedPreferences.getInstance());
  final controller = ReceiptPrinter(repository);
  addTearDown(controller.dispose);
  await controller.saveSettings(settings);
  return controller;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('verified text is sent once and contains exact denomination subtotals',
      () async {
    final configured =
        printer.withVerifiedGlyphs(ReceiptPrinter.fontTestText(printer));
    final controller = await configuredPrinter(configured);
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(
        channel, (call) async => calls.add(call));

    await controller.print(countedReceipt(), TextDirection.ltr);

    expect(calls.map((call) => call.method), ['send']);
    final payload = calls.single.arguments['data'] as Uint8List;
    expect(payload.take(2), [0x1b, 0x40]);
    expect(payload.sublist(payload.length - defaultFinish.length - 1),
        [0x0a, ...defaultFinish]);
    final lines = latin1.decode(payload).split('\n');
    expect(lines, contains('CNY'));
    expect(
        lines.any((line) => RegExp(r'^100\s+2\s+200$').hasMatch(line)), isTrue);
    expect(lines.any((line) => RegExp(r'^0.10\s+3\s+0.30$').hasMatch(line)),
        isTrue);
    expect(lines.any((line) => RegExp(r'^Total\s+200.30$').hasMatch(line)),
        isTrue);
  });

  testWidgets('unverified glyphs use one raster payload even when a send fails',
      (tester) async {
    await tester.runAsync(() async {
      final configured =
          printer.withVerifiedGlyphs(ReceiptPrinter.fontTestText(printer));
      final controller = await configuredPrinter(configured);
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        throw PlatformException(code: 'uncertain');
      });

      final receipt = countedReceipt(customLabel: true);
      expect(receipt.rows.last.denomination, '自訂 面額 (0.10)');
      await expectLater(
        controller.print(receipt, TextDirection.ltr),
        throwsA(isA<ReceiptPrinterException>()
            .having((error) => error.code, 'code', 'uncertain')),
      );
      expect(calls.map((call) => call.method), ['send']);
      final payload = calls.single.arguments['data'] as Uint8List;
      expect(payload.sublist(0, 8), [0x1b, 0x40, 0x1d, 0x76, 0x30, 0, 48, 0]);
      expect(payload.sublist(payload.length - defaultFinish.length),
          defaultFinish);
      final firstBandHeight = payload[8] + (payload[9] << 8);
      expect(
          payload
              .sublist(10, 10 + 48 * firstBandHeight)
              .any((byte) => byte != 0),
          isTrue);
      expect(controller.busy, isFalse);
    });
  });

  test('graphics commands store and print each band at its original width', () {
    final pixels = Uint8List(2 * 129)..[0] = 0xff;
    final payload = EscPosReceipt.image(
      ReceiptBitmap(width: 9, height: 129, pixels: pixels),
      ReceiptPrinterSettings.fromJson({
        ...printer.toJson(),
        'imageCommand': ReceiptImageCommand.graphics.name,
      }),
    );
    expect(payload.sublist(0, 17), [
      0x1b,
      0x40,
      0x1d,
      0x28,
      0x4c,
      10,
      1,
      0x30,
      0x70,
      0x30,
      1,
      1,
      0x31,
      9,
      0,
      128,
      0
    ]);
    expect(payload.sublist(273, 280), [0x1d, 0x28, 0x4c, 2, 0, 0x30, 0x32]);
    expect(payload.sublist(280, 295),
        [0x1d, 0x28, 0x4c, 12, 0, 0x30, 0x70, 0x30, 1, 1, 0x31, 9, 0, 1, 0]);
    expect(payload.sublist(297),
        [0x1d, 0x28, 0x4c, 2, 0, 0x30, 0x32, ...defaultFinish]);
  });

  test('existing profiles get a default feed and can change or disable cutting',
      () {
    final legacy = printer.toJson()
      ..remove('feed')
      ..remove('cut');
    expect(EscPosReceipt.finish(ReceiptPrinterSettings.fromJson(legacy)),
        defaultFinish);

    final fullCut = ReceiptPrinterSettings.fromJson({
      ...legacy,
      'feed': ReceiptFeed.extraLong.name,
      'cut': ReceiptCut.full.name,
    }).withVerifiedGlyphs('Keycap Calc');
    final restored = ReceiptPrinterSettings.fromJson(fullCut.toJson());
    expect(EscPosReceipt.finish(restored), [
      0x1d,
      0x50,
      0,
      203,
      0x1b,
      0x4a,
      255,
      0x1b,
      0x4a,
      225,
      0x1d,
      0x56,
      65,
      0
    ]);

    final manualCut = ReceiptPrinterSettings.fromJson({
      ...legacy,
      'cut': ReceiptCut.none.name,
    });
    expect(EscPosReceipt.finish(manualCut), defaultFinish.take(7));
  });

  test('font and paper feed tests each send the same finish exactly once',
      () async {
    final controller = await configuredPrinter(printer);
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(
        channel, (call) async => calls.add(call));

    await controller.printFontTest(printer);
    await controller.testPaperFeed(printer);

    expect(calls.map((call) => call.method), ['send', 'send']);
    final fontPayload = calls.first.arguments['data'] as Uint8List;
    expect(latin1.decode(fontPayload), contains('Keycap Calc'));
    expect(fontPayload.sublist(fontPayload.length - defaultFinish.length),
        defaultFinish);
    expect(calls.last.arguments['data'], defaultFinish);
  });
}
