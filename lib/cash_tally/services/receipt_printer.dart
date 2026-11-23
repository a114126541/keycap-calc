import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../repo/database.dart';
import '../models/cash_receipt.dart';
import '../models/receipt_printer_settings.dart';
import 'esc_pos_receipt.dart';
import 'receipt_rasterizer.dart';

class ReceiptPrinterException implements Exception {
  const ReceiptPrinterException(this.code);

  final String code;
}

class ReceiptPrinter extends ChangeNotifier {
  ReceiptPrinter(this._repository) : _settings = _read(_repository);

  static const _key = 'receipt_printer_v1';
  static const _channel = MethodChannel('keycap_calc/receipt_printer');
  static const defaultPort = 9100;

  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  final DatabaseRepository _repository;
  ReceiptPrinterSettings? _settings;
  bool _busy = false;
  bool _disposed = false;

  ReceiptPrinterSettings? get settings => _settings;
  bool get busy => _busy;

  static ReceiptPrinterSettings? _read(DatabaseRepository repository) {
    final value = repository.get<String>(_key);
    if (value == null) return null;
    try {
      return ReceiptPrinterSettings.fromJson(
        jsonDecode(value) as Map<String, Object?>,
      );
    } on Object {
      return null;
    }
  }

  Future<void> saveSettings(ReceiptPrinterSettings settings) async {
    final saved = await _repository.set<String>(
      _key,
      jsonEncode(settings.toJson()),
    );
    if (!saved) throw const ReceiptPrinterException('save');
    _settings = settings;
    _notify();
  }

  Future<List<ReceiptPrinterDevice>> devices(
      ReceiptConnection connection) async {
    try {
      final items = await _channel.invokeListMethod<Map<Object?, Object?>>(
        'devices',
        {'connection': connection.name},
      );
      return [
        for (final item in items ?? const [])
          ReceiptPrinterDevice(
            address: item['address'] as String,
            name: item['name'] as String,
          ),
      ];
    } on PlatformException catch (error) {
      throw ReceiptPrinterException(error.code);
    } on MissingPluginException {
      throw const ReceiptPrinterException('unavailable');
    }
  }

  Future<void> print(CashReceipt receipt, TextDirection direction) {
    final printer = _settings;
    if (printer == null) {
      return Future.error(const ReceiptPrinterException('unavailable'));
    }
    return _run(() async {
      final text = receipt.textLayout(printer.paper.columns);
      Uint8List? encoded;
      if (text != null && _hasVerifiedGlyphs(text, printer.verifiedGlyphs)) {
        encoded = await _encode(text, printer.encoding);
      }

      final Uint8List payload;
      if (encoded != null) {
        payload = EscPosReceipt.text(encoded, printer);
      } else {
        final image = await ReceiptRasterizer.render(
          receipt,
          printer.paper.dots,
          direction: direction,
        );
        payload = EscPosReceipt.image(image, printer);
      }
      // Both formats are fully prepared before the connection is opened.
      await _send(printer, payload);
    });
  }

  Future<String> printFontTest(ReceiptPrinterSettings printer) =>
      _run(() async {
        final sample = fontTestText(printer);
        final data = await _encode(sample, printer.encoding);
        if (data == null) throw const ReceiptPrinterException('encoding');
        await _send(printer, EscPosReceipt.text(data, printer));
        return sample;
      });

  Future<void> testPaperFeed(ReceiptPrinterSettings printer) =>
      _run(() => _send(printer, EscPosReceipt.finish(printer)));

  static String fontTestText(ReceiptPrinterSettings printer) {
    final lines = ['Keycap Calc'];
    final columns = printer.paper.columns;
    for (var first = 32; first <= 126; first += columns) {
      lines.add(String.fromCharCodes([
        for (var rune = first; rune < first + columns && rune <= 126; rune++)
          rune,
      ]));
    }
    switch (printer.encoding) {
      case ReceiptEncoding.ascii:
        break;
      case ReceiptEncoding.gbk:
        lines.addAll(['点钞小票 面额 数量', '小计 合计']);
      case ReceiptEncoding.big5:
        lines.addAll(['點鈔小票 面額 數量', '小計 合計']);
    }
    return lines.join('\n');
  }

  bool _hasVerifiedGlyphs(String text, String proof) {
    if (proof.isEmpty) return false;
    final supported = proof.runes.toSet();
    return text.runes.every((rune) => rune == 10 || supported.contains(rune));
  }

  Future<Uint8List?> _encode(String text, ReceiptEncoding encoding) async {
    if (encoding == ReceiptEncoding.ascii) {
      try {
        return Uint8List.fromList(ascii.encode(text));
      } on ArgumentError {
        return null;
      }
    }
    return _channel.invokeMethod<Uint8List>(
      'encode',
      {'encoding': encoding.name, 'text': text},
    );
  }

  Future<void> _send(ReceiptPrinterSettings printer, Uint8List payload) async {
    if (printer.connection != ReceiptConnection.network) {
      await _channel.invokeMethod<void>('send', {
        'connection': printer.connection.name,
        'address': printer.address,
        'data': payload,
      });
      return;
    }

    final Socket socket;
    try {
      socket = await Socket.connect(
        printer.address,
        printer.port,
        timeout: const Duration(seconds: 6),
      );
    } on Object {
      throw const ReceiptPrinterException('unavailable');
    }

    try {
      socket.add(payload);
      await socket.flush().timeout(const Duration(seconds: 12));
      await socket.close().timeout(const Duration(seconds: 5));
    } on Object {
      // A failed write may have reached the printer. Do not resend it.
      throw const ReceiptPrinterException('uncertain');
    } finally {
      socket.destroy();
    }
  }

  Future<T> _run<T>(Future<T> Function() work) async {
    if (_busy) throw const ReceiptPrinterException('busy');
    _busy = true;
    _notify();
    try {
      return await work();
    } on PlatformException catch (error) {
      throw ReceiptPrinterException(error.code);
    } on ReceiptPrinterException {
      rethrow;
    } on Object {
      throw const ReceiptPrinterException('prepare');
    } finally {
      _busy = false;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
