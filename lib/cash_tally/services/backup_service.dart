import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../data/country_catalog.dart';
import '../data/currency_catalog.dart';
import '../models/business_profile.dart';
import '../models/cash_count_session.dart';
import '../models/custom_denomination.dart';
import '../models/till_template.dart';

class BackupBundle {
  const BackupBundle({
    required this.sessions,
    required this.templates,
    required this.customDenominations,
    required this.hiddenDenominationIds,
    this.businessProfile,
    this.regionId,
    this.defaultCurrencyCode,
    this.favoriteCurrencyOrder,
  });

  factory BackupBundle.fromJson(Map<String, Object?> json) {
    final rawSessions = json['sessions'] as List<Object?>? ?? const <Object?>[];
    Map<String, Object?> stringMap(Object? source) =>
        (source! as Map<Object?, Object?>).map(
          (key, value) => MapEntry(key! as String, value),
        );

    final sessions = rawSessions
        .map(
          (item) => CashCountSession.fromJson(stringMap(item)),
        )
        .toList(growable: false);
    for (final session in sessions) {
      if (!CurrencyCatalog.containsCode(session.currencyCode)) {
        throw const FormatException('Unknown backup currency');
      }
      final currency =
          session.currencyFor(CurrencyCatalog.byCode(session.currencyCode));
      for (final id in session.quantities.keys) {
        if (currency.denominationById(id) == null) {
          throw const FormatException('Unknown backup denomination');
        }
      }
    }
    final profile = json['businessProfile'];
    final regionId = json['regionId'] as String?;
    final defaultCurrencyCode = json['defaultCurrencyCode'] as String?;
    final favorites =
        (json['favoriteCurrencyOrder'] as List<Object?>?)?.cast<String>();
    final templates = (json['templates'] as List<Object?>? ?? const [])
        .map((item) => TillTemplate.fromJson(stringMap(item)))
        .toList(growable: false);
    final customDenominations =
        (json['customDenominations'] as List<Object?>? ?? const [])
            .map((item) => CustomDenomination.fromJson(stringMap(item)))
            .toList(growable: false);
    if (templates
            .any((item) => !CurrencyCatalog.containsCode(item.currencyCode)) ||
        customDenominations.any(
          (item) => !CurrencyCatalog.containsCode(item.currencyCode),
        )) {
      throw const FormatException('Unknown backup currency');
    }
    return BackupBundle(
      sessions: sessions,
      templates: templates,
      customDenominations: customDenominations,
      hiddenDenominationIds:
          (json['hiddenDenominationIds'] as Map<String, Object?>? ??
                  const <String, Object?>{})
              .map(
        (code, value) => MapEntry(
          code,
          (value as List<Object?>).whereType<String>().toSet(),
        ),
      ),
      businessProfile:
          profile == null ? null : BusinessProfile.fromJson(stringMap(profile)),
      regionId: CountryCatalog.byId(regionId)?.id,
      defaultCurrencyCode: CurrencyCatalog.containsCode(defaultCurrencyCode)
          ? defaultCurrencyCode
          : null,
      favoriteCurrencyOrder:
          favorites?.where(CurrencyCatalog.containsCode).toSet().toList(),
    );
  }

  final List<CashCountSession> sessions;
  final List<TillTemplate> templates;
  final List<CustomDenomination> customDenominations;
  final Map<String, Set<String>> hiddenDenominationIds;
  final BusinessProfile? businessProfile;
  final String? regionId;
  final String? defaultCurrencyCode;
  final List<String>? favoriteCurrencyOrder;

  Map<String, Object?> toJson() => <String, Object?>{
        'schemaVersion': 1,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
        'sessions':
            sessions.map((item) => item.toJson()).toList(growable: false),
        'templates':
            templates.map((item) => item.toJson()).toList(growable: false),
        'customDenominations': customDenominations
            .map((item) => item.toJson())
            .toList(growable: false),
        'hiddenDenominationIds': hiddenDenominationIds.map((code, ids) {
          final ordered = ids.toList(growable: false)..sort();
          return MapEntry(code, ordered);
        }),
        if (businessProfile != null)
          'businessProfile': businessProfile!.toJson(),
        if (regionId != null) 'regionId': regionId,
        if (defaultCurrencyCode != null)
          'defaultCurrencyCode': defaultCurrencyCode,
        if (favoriteCurrencyOrder != null)
          'favoriteCurrencyOrder': favoriteCurrencyOrder,
      };
}

class BackupService {
  BackupService();

  static const maxFileBytes = 64 * 1024 * 1024;
  static const _iterations = 210000;
  final _cipher = AesGcm.with256bits();
  final _random = Random.secure();

  Future<Uint8List> encrypt({
    required BackupBundle bundle,
    required String password,
  }) async {
    if (password.length < 8) {
      throw const FormatException('Backup password must have 8 characters.');
    }
    final salt = List<int>.generate(16, (_) => _random.nextInt(256));
    final key = await _deriveKey(password, salt, _iterations);
    final clearText = utf8.encode(jsonEncode(bundle.toJson()));
    final box = await _cipher.encrypt(clearText, secretKey: key);
    final envelope = <String, Object?>{
      'format': 'vycetka-encrypted-backup',
      'version': 1,
      'kdf': <String, Object?>{
        'name': 'PBKDF2-HMAC-SHA256',
        'iterations': _iterations,
        'salt': base64Encode(salt),
      },
      'cipher': <String, Object?>{
        'name': 'AES-256-GCM',
        'nonce': base64Encode(box.nonce),
        'data': base64Encode(box.cipherText),
        'mac': base64Encode(box.mac.bytes),
      },
    };
    final encoded = utf8.encode(jsonEncode(envelope));
    if (encoded.length > maxFileBytes) {
      throw const FormatException('Backup file is too large');
    }
    return Uint8List.fromList(encoded);
  }

  Future<BackupBundle> decrypt({
    required List<int> bytes,
    required String password,
  }) async {
    if (bytes.length > maxFileBytes) {
      throw const FormatException('Backup file is too large');
    }
    final envelope = jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
    if (envelope['format'] != 'vycetka-encrypted-backup' ||
        envelope['version'] != 1) {
      throw const FormatException('Unsupported backup format.');
    }
    final kdf = (envelope['kdf']! as Map<Object?, Object?>).map(
      (key, value) => MapEntry(key! as String, value),
    );
    final cipher = (envelope['cipher']! as Map<Object?, Object?>).map(
      (key, value) => MapEntry(key! as String, value),
    );
    final iterations = (kdf['iterations']! as num).toInt();
    if (iterations < 100000 || iterations > 2000000) {
      throw const FormatException('Invalid backup key parameters.');
    }
    final salt = base64Decode(kdf['salt']! as String);
    if (kdf['name'] != 'PBKDF2-HMAC-SHA256' ||
        cipher['name'] != 'AES-256-GCM' ||
        salt.length != 16) {
      throw const FormatException('Unsupported backup encryption.');
    }
    final key = await _deriveKey(password, salt, iterations);
    final clearText = await _cipher.decrypt(
      SecretBox(
        base64Decode(cipher['data']! as String),
        nonce: base64Decode(cipher['nonce']! as String),
        mac: Mac(base64Decode(cipher['mac']! as String)),
      ),
      secretKey: key,
    );
    final payload = jsonDecode(utf8.decode(clearText)) as Map<String, Object?>;
    if (payload['schemaVersion'] != 1) {
      throw const FormatException('Unsupported backup payload.');
    }
    return BackupBundle.fromJson(payload);
  }

  Future<SecretKey> _deriveKey(
    String password,
    List<int> salt,
    int iterations,
  ) {
    return Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: iterations,
      bits: 256,
    ).deriveKey(secretKey: SecretKey(utf8.encode(password)), nonce: salt);
  }
}
