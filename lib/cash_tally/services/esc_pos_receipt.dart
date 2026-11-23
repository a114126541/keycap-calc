import 'dart:math' as math;
import 'dart:typed_data';

import '../models/receipt_printer_settings.dart';

class ReceiptBitmap {
  const ReceiptBitmap({
    required this.width,
    required this.height,
    required this.pixels,
  });

  final int width;
  final int height;

  // Rows of packed pixels, with the leftmost dot in the high bit.
  final Uint8List pixels;
}

class EscPosReceipt {
  static const _initialize = [0x1b, 0x40];

  static Uint8List text(Uint8List data, ReceiptPrinterSettings printer) =>
      Uint8List.fromList([
        ..._initialize,
        0x1b, 0x4d, 0, // Font A.
        0x1b, 0x52, 0, // ASCII punctuation.
        0x1b, 0x74, 0,
        0x1c, printer.encoding == ReceiptEncoding.ascii ? 0x2e : 0x26,
        ...data,
        if (printer.encoding != ReceiptEncoding.ascii) ...[0x1c, 0x2e],
        0x0a,
        ...finish(printer),
      ]);

  static Uint8List image(ReceiptBitmap image, ReceiptPrinterSettings printer) {
    final rowBytes = (image.width + 7) ~/ 8;
    if (image.width <= 0 ||
        image.height <= 0 ||
        image.pixels.length != rowBytes * image.height) {
      throw ArgumentError('Invalid receipt bitmap');
    }

    final bytes = BytesBuilder(copy: false)..add(_initialize);
    for (var top = 0; top < image.height; top += 128) {
      final height = math.min(128, image.height - top);
      final band = Uint8List.sublistView(
        image.pixels,
        top * rowBytes,
        (top + height) * rowBytes,
      );
      switch (printer.imageCommand) {
        case ReceiptImageCommand.raster:
          bytes
            ..add([0x1d, 0x76, 0x30, 0, ..._word(rowBytes), ..._word(height)])
            ..add(band);
        case ReceiptImageCommand.graphics:
          bytes
            ..add([
              0x1d,
              0x28,
              0x4c,
              ..._word(band.length + 10),
              0x30,
              0x70,
              0x30,
              1,
              1,
              0x31,
              ..._word(image.width),
              ..._word(height),
            ])
            ..add(band)
            ..add([0x1d, 0x28, 0x4c, 2, 0, 0x30, 0x32]);
      }
    }
    bytes.add(finish(printer));
    return bytes.takeBytes();
  }

  static Uint8List finish(ReceiptPrinterSettings printer) {
    const maxFeedSteps = 255;
    const stepsPerMillimeter = 8;
    final feedSteps = printer.feed.millimeters * stepsPerMillimeter;
    return Uint8List.fromList([
      0x1d, 0x50, 0, 203, // GS P: use 203 vertical motion units per inch.
      for (var remaining = feedSteps;
          remaining > 0;
          remaining -= maxFeedSteps) ...[
        0x1b,
        0x4a,
        math.min(remaining, maxFeedSteps)
      ], // ESC J.
      // GS V: feed to the cutter and cut once, starting at the left margin.
      if (printer.cut != ReceiptCut.none) ...[
        0x1d,
        0x56,
        printer.cut == ReceiptCut.full ? 65 : 66,
        0
      ],
    ]);
  }

  static List<int> _word(int value) => [value & 0xff, value >> 8];
}
