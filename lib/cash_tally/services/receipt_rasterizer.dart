import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../models/cash_receipt.dart';
import 'esc_pos_receipt.dart';

class ReceiptRasterizer {
  static Future<ReceiptBitmap> render(
    CashReceipt receipt,
    int width, {
    required ui.TextDirection direction,
  }) async {
    const margin = 12.0;
    final contentWidth = width - margin * 2;
    final countWidth = contentWidth * .21;
    final amountWidth = contentWidth * .34;
    final labelWidth = contentWidth - countWidth - amountWidth - 16;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    var y = margin;

    double draw(
      String value,
      double left,
      double available, {
      ui.TextAlign align = ui.TextAlign.left,
      double size = 20,
      bool bold = false,
    }) {
      // Use the system's font family and fallback chain, independently of the
      // app's selected font or the fonts bundled for PDF exports.
      final painter = TextPainter(
        text: TextSpan(
          text: value,
          style: TextStyle(
            fontFamily: 'sans-serif',
            color: const ui.Color(0xff000000),
            fontSize: size,
            fontWeight: bold ? ui.FontWeight.bold : ui.FontWeight.normal,
          ),
        ),
        textAlign: align,
        textDirection: direction,
      )..layout(minWidth: available, maxWidth: available);
      painter.paint(canvas, ui.Offset(left, y));
      final height = painter.height;
      painter.dispose();
      return height;
    }

    void rule() {
      y += 6;
      canvas.drawLine(
        ui.Offset(margin, y),
        ui.Offset(width - margin, y),
        ui.Paint()
          ..color = const ui.Color(0xff000000)
          ..strokeWidth = 1,
      );
      y += 8;
    }

    y += draw(receipt.title, margin, contentWidth,
        align: ui.TextAlign.center, size: 26, bold: true);
    y += draw(receipt.currencyCode, margin, contentWidth,
        align: ui.TextAlign.center);
    rule();
    final rows = receipt.table;
    for (var index = 0; index < rows.length; index++) {
      final row = rows[index];
      final bold = index == 0;
      final label = draw(row.denomination, margin, labelWidth, bold: bold);
      final count = draw(row.quantity, margin + labelWidth + 8, countWidth,
          align: ui.TextAlign.right, bold: bold);
      final amount = draw(
          row.subtotal, width - margin - amountWidth, amountWidth,
          align: ui.TextAlign.right, bold: bold);
      y += math.max(label, math.max(count, amount)) + 5;
      if (bold) rule();
    }
    rule();
    final total = draw(receipt.total.label, margin, contentWidth * .45,
        size: 24, bold: true);
    final amount = draw(
        receipt.total.amount, margin + contentWidth * .45, contentWidth * .55,
        align: ui.TextAlign.right, size: 24, bold: true);
    y += math.max(total, amount) + margin;

    final picture = recorder.endRecording();
    final height = y.ceil();
    final rowBytes = (width + 7) ~/ 8;
    final pixels = Uint8List(rowBytes * height);
    try {
      for (var top = 0; top < height; top += 128) {
        final bandHeight = math.min(128, height - top);
        final bandRecorder = ui.PictureRecorder();
        ui.Canvas(bandRecorder)
          ..drawColor(const ui.Color(0xffffffff), ui.BlendMode.src)
          ..translate(0, -top.toDouble())
          ..drawPicture(picture);
        final band = bandRecorder.endRecording();
        try {
          final image = await band.toImage(width, bandHeight);
          try {
            final rgba =
                await image.toByteData(format: ui.ImageByteFormat.rawRgba);
            if (rgba == null) throw StateError('Receipt image has no pixels');
            for (var row = 0; row < bandHeight; row++) {
              for (var x = 0; x < width; x++) {
                final offset = (row * width + x) * 4;
                final luminance = rgba.getUint8(offset) * 3 +
                    rgba.getUint8(offset + 1) * 6 +
                    rgba.getUint8(offset + 2);
                if (luminance < 1600) {
                  pixels[(top + row) * rowBytes + x ~/ 8] |= 0x80 >> (x % 8);
                }
              }
            }
          } finally {
            image.dispose();
          }
        } finally {
          band.dispose();
        }
      }
    } finally {
      picture.dispose();
    }
    return ReceiptBitmap(width: width, height: height, pixels: pixels);
  }
}
