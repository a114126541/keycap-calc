enum ReceiptConnection { network, bluetooth, usb }

enum ReceiptPaper {
  narrow(384, 32),
  medium(512, 42),
  wide(576, 48);

  const ReceiptPaper(this.dots, this.columns);

  final int dots;
  final int columns;
}

enum ReceiptEncoding { ascii, gbk, big5 }

enum ReceiptImageCommand { raster, graphics }

enum ReceiptFeed {
  short(15),
  standard(30),
  long(45),
  extraLong(60);

  const ReceiptFeed(this.millimeters);

  final int millimeters;
}

enum ReceiptCut { none, partial, full }

class ReceiptPrinterSettings {
  const ReceiptPrinterSettings({
    required this.connection,
    required this.address,
    required this.port,
    required this.paper,
    required this.encoding,
    required this.imageCommand,
    this.feed = ReceiptFeed.standard,
    this.cut = ReceiptCut.partial,
    this.deviceName = '',
    this.verifiedGlyphs = '',
  });

  factory ReceiptPrinterSettings.fromJson(Map<String, Object?> json) {
    return ReceiptPrinterSettings(
      connection:
          ReceiptConnection.values.byName(json['connection']! as String),
      address: json['address']! as String,
      port: json['port']! as int,
      paper: ReceiptPaper.values.byName(json['paper']! as String),
      encoding: ReceiptEncoding.values.byName(json['encoding']! as String),
      imageCommand:
          ReceiptImageCommand.values.byName(json['imageCommand']! as String),
      feed: ReceiptFeed.values
          .byName(json['feed'] as String? ?? ReceiptFeed.standard.name),
      cut: ReceiptCut.values
          .byName(json['cut'] as String? ?? ReceiptCut.partial.name),
      deviceName: json['deviceName'] as String? ?? '',
      verifiedGlyphs: json['verifiedGlyphs'] as String? ?? '',
    );
  }

  final ReceiptConnection connection;
  final String address;
  final int port;
  final ReceiptPaper paper;
  final ReceiptEncoding encoding;
  final ReceiptImageCommand imageCommand;
  final ReceiptFeed feed;
  final ReceiptCut cut;
  final String deviceName;
  final String verifiedGlyphs;

  String get name => deviceName.isEmpty ? address : deviceName;

  bool hasSameTextProfile(ReceiptPrinterSettings other) =>
      connection == other.connection &&
      address == other.address &&
      port == other.port &&
      paper == other.paper &&
      encoding == other.encoding;

  ReceiptPrinterSettings withVerifiedGlyphs(String glyphs) =>
      ReceiptPrinterSettings(
        connection: connection,
        address: address,
        port: port,
        paper: paper,
        encoding: encoding,
        imageCommand: imageCommand,
        feed: feed,
        cut: cut,
        deviceName: deviceName,
        verifiedGlyphs: glyphs,
      );

  Map<String, Object?> toJson() => {
        'connection': connection.name,
        'address': address,
        'port': port,
        'paper': paper.name,
        'encoding': encoding.name,
        'imageCommand': imageCommand.name,
        'feed': feed.name,
        'cut': cut.name,
        'deviceName': deviceName,
        'verifiedGlyphs': verifiedGlyphs,
      };
}

class ReceiptPrinterDevice {
  const ReceiptPrinterDevice({required this.address, required this.name});

  final String address;
  final String name;
}
