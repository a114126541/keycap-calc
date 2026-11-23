import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:neumorphic_calculator/repo/database.dart';

import '../data/country_catalog.dart';
import '../data/currency_catalog.dart';
import '../l10n/app_localizations.dart';
import '../models/business_profile.dart';
import '../models/cash_count_session.dart';
import '../models/country_profile.dart';
import '../models/currency_definition.dart';
import '../models/custom_denomination.dart';
import '../models/till_template.dart';
import '../services/backup_service.dart';
import '../services/local_store.dart';
import '../services/receipt_printer.dart';

class AppController extends ChangeNotifier {
  AppController(this._repository, {LocalStore? localStore})
      : _store = localStore ?? LocalStore(),
        _preferences = _readPreferences(_repository),
        receiptPrinter = ReceiptPrinter(_repository);

  static const _settingsKey = 'cash_tally_settings_v1';
  final DatabaseRepository _repository;
  final LocalStore _store;
  final ReceiptPrinter receiptPrinter;
  Map<String, Object?> _preferences;
  List<CashCountSession> _sessions = [];
  Future<void>? _historyLoad;
  Future<void> _writes = Future.value();
  bool _restorePending = false;
  bool _disposed = false;
  bool historyLoading = true;
  bool historyUnavailable = false;

  static Map<String, Object?> _readPreferences(DatabaseRepository repository) {
    final stored = repository.get<String>(_settingsKey);
    if (stored == null) return {};
    try {
      final decoded = jsonDecode(stored);
      return decoded is Map<String, Object?> ? decoded : {};
    } on FormatException {
      return {};
    }
  }

  Locale get locale {
    final tag = _preferences['locale'];
    return AppLocalizations.supportedLocales.firstWhere(
      (locale) => locale.toLanguageTag() == tag,
      orElse: () => const Locale('en'),
    );
  }

  CountryProfile get selectedCountry =>
      CountryCatalog.byId(_preferences['region'] as String?) ??
      CountryCatalog.byId('CN')!;

  String get selectedCurrencyCode {
    final stored = _preferences['currency'] as String?;
    return CurrencyCatalog.containsCode(stored)
        ? stored!
        : selectedCountry.currencyCode;
  }

  List<String> get favoriteCurrencyOrder =>
      (_preferences['favorites'] as List<Object?>? ?? [])
          .whereType<String>()
          .where(CurrencyCatalog.containsCode)
          .toList(growable: false);

  Set<String> get favoriteCurrencyCodes => favoriteCurrencyOrder.toSet();

  List<CurrencyDefinition> get currencies => CurrencyCatalog.displayOrder(
        selectedCurrencyCode,
        favoriteCodes: favoriteCurrencyCodes,
        favoriteOrder: favoriteCurrencyOrder,
      );

  List<CashCountSession> get sessions => List.unmodifiable(_sessions);

  List<TillTemplate> get tillTemplates =>
      _readList('templates', TillTemplate.fromJson);

  BusinessProfile get businessProfile => BusinessProfile.fromJson(
        _preferences['businessProfile'] as Map<String, Object?>? ?? const {},
      );

  List<CustomDenomination> get _customDenominations =>
      _readList('customDenominations', CustomDenomination.fromJson);

  List<T> _readList<T>(
    String key,
    T Function(Map<String, Object?>) fromJson,
  ) =>
      (_preferences[key] as List<Object?>? ?? [])
          .whereType<Map<String, Object?>>()
          .map(fromJson)
          .toList(growable: false);

  Map<String, Object?> get _hiddenDenominations =>
      (_preferences['hiddenDenominations'] as Map<String, Object?>?) ?? {};

  Future<void> setDefaultLocale(Locale locale) =>
      _savePreferences(() => {'locale': locale.toLanguageTag()});

  Future<void> selectCountry(CountryProfile country) => _savePreferences(
        () => {'region': country.id, 'currency': country.currencyCode},
      );

  Future<void> setDefaultCurrency(String code) =>
      _savePreferences(() => {'currency': code});

  Future<void> toggleFavoriteCurrency(String code) => _savePreferences(() {
        final order = [...favoriteCurrencyOrder];
        if (!order.remove(code)) order.add(code);
        return {'favorites': order};
      });

  Future<void> reorderFavoriteCurrencies(int oldIndex, int newIndex) =>
      _savePreferences(() {
        final order = [...favoriteCurrencyOrder];
        final code = order.removeAt(oldIndex);
        order.insert(newIndex > oldIndex ? newIndex - 1 : newIndex, code);
        return {'favorites': order};
      });

  CurrencyDefinition configuredCurrency(String code) {
    final base = CurrencyCatalog.byCode(code);
    return base.copyWithDenominations([
      ...base.denominations,
      for (final item in _customDenominations)
        if (item.currencyCode == code) item.toDenomination(),
    ]);
  }

  CurrencyDefinition countingCurrency(
    String code, {
    Set<String> keepVisible = const {},
  }) {
    final configured = configuredCurrency(code);
    final hidden = _hiddenDenominations[code] as List<Object?>? ?? [];
    return configured.copyWithDenominations([
      for (final item in configured.denominations)
        if (!hidden.contains(item.id) || keepVisible.contains(item.id)) item,
    ]);
  }

  bool isDenominationVisible(String code, String denominationId) =>
      !(_hiddenDenominations[code] as List<Object?>? ?? [])
          .contains(denominationId);

  Future<void> setDenominationVisible(
    String code,
    String denominationId,
    bool visible,
  ) =>
      _savePreferences(() {
        final ids = List<Object?>.of(
          _hiddenDenominations[code] as List<Object?>? ?? [],
        )..remove(denominationId);
        if (!visible) ids.add(denominationId);
        return {
          'hiddenDenominations': {..._hiddenDenominations, code: ids},
        };
      });

  Future<void> addCustomDenomination(CustomDenomination denomination) =>
      _savePreferences(() => {
            'customDenominations': [
              for (final item in _customDenominations) item.toJson(),
              denomination.toJson(),
            ],
          });

  Future<void> saveTillTemplate(TillTemplate template) =>
      _savePreferences(() => {
            'templates': [
              for (final item in tillTemplates)
                if (item.id != template.id) item.toJson(),
              template.toJson(),
            ],
          });

  Future<void> saveBusinessProfile(BusinessProfile profile) =>
      _savePreferences(() => {'businessProfile': profile.toJson()});

  Future<void> deleteTillTemplate(String id) => _savePreferences(() => {
        'templates': [
          for (final item in tillTemplates)
            if (item.id != id) item.toJson(),
        ],
      });

  Future<void> _savePreferences(
    Map<String, Object?> Function() update,
  ) =>
      _serialize(() async {
        if (_restorePending) await _resumeRestore();
        final next = {..._preferences, ...update()};
        await _writePreferences(next);
        _preferences = next;
        _notify();
      });

  Future<void> _writePreferences(Map<String, Object?> preferences) async {
    if (!await _repository.set<String>(_settingsKey, jsonEncode(preferences))) {
      throw StateError('Could not save cash tally settings');
    }
  }

  Future<void> loadHistory() => _historyLoad ??= _loadHistory();

  Future<void> _loadHistory() async {
    try {
      final snapshot = await _store.readRestoreJournal();
      if (snapshot == null) {
        _sessions = await _store.loadSessions();
      } else {
        await _serialize(() async {
          _restorePending = true;
          await _applyRestore(BackupBundle.fromJson(snapshot));
        });
      }
    } on Object {
      historyUnavailable = true;
    }
    historyLoading = false;
    _notify();
  }

  Future<bool> saveSession(CashCountSession session) => _updateHistory(() => [
        session,
        for (final item in _sessions)
          if (item.id != session.id) item,
      ]).then((_) => true);

  Future<void> deleteSession(String id) => _updateHistory(() => [
        for (final session in _sessions)
          if (session.id != id) session,
      ]);

  Future<void> _updateHistory(List<CashCountSession> Function() update) =>
      _withHistory(() async {
        final next = update()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        await _store.saveSessions(next);
        _sessions = next;
        _notify();
      });
  Future<BackupBundle> exportBackupData() => _withHistory(() async {
        return BackupBundle(
          sessions: sessions,
          templates: tillTemplates,
          customDenominations: _customDenominations,
          hiddenDenominationIds: _hiddenDenominations.map(
            (code, ids) => MapEntry(
                code, (ids as List<Object?>).whereType<String>().toSet()),
          ),
          businessProfile: businessProfile,
          regionId: selectedCountry.id,
          defaultCurrencyCode: selectedCurrencyCode,
          favoriteCurrencyOrder: favoriteCurrencyOrder,
        );
      });

  Future<void> restoreBackup(BackupBundle backup) => _withHistory(() async {
        final records = {for (final session in _sessions) session.id: session};
        for (final session in backup.sessions) {
          final current = records[session.id];
          if (current == null || session.updatedAt.isAfter(current.updatedAt)) {
            records[session.id] = session;
          }
        }
        final templates = {
          for (final template in [...tillTemplates, ...backup.templates])
            template.id: template,
        };
        final customDenominations = {
          for (final item in [
            ..._customDenominations,
            ...backup.customDenominations
          ])
            item.id: item,
        };
        final snapshot = BackupBundle(
          sessions: records.values.toList()
            ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt)),
          templates: templates.values.toList(),
          customDenominations: customDenominations.values.toList(),
          hiddenDenominationIds: backup.hiddenDenominationIds,
          businessProfile: backup.businessProfile,
          regionId: backup.regionId,
          defaultCurrencyCode: backup.defaultCurrencyCode,
          favoriteCurrencyOrder: backup.favoriteCurrencyOrder,
        );
        await _store.writeRestoreJournal(snapshot.toJson());
        _restorePending = true;
        try {
          await _applyRestore(snapshot);
        } on Object {
          historyUnavailable = true;
          _notify();
          rethrow;
        }
      });

  Future<T> _withHistory<T>(Future<T> Function() run) async {
    await loadHistory();
    return _serialize(() async {
      if (_restorePending) await _resumeRestore();
      if (historyUnavailable) {
        throw StateError('Cash tally history unavailable');
      }
      return run();
    });
  }

  Future<void> _resumeRestore() async {
    final snapshot = await _store.readRestoreJournal();
    if (snapshot == null) return;
    _restorePending = true;
    await _applyRestore(BackupBundle.fromJson(snapshot));
  }

  Future<void> _applyRestore(BackupBundle snapshot) async {
    final next = <String, Object?>{
      ..._preferences,
      'templates': snapshot.templates.map((item) => item.toJson()).toList(),
      'customDenominations':
          snapshot.customDenominations.map((item) => item.toJson()).toList(),
      'hiddenDenominations': snapshot.hiddenDenominationIds.map(
        (code, ids) => MapEntry(code, ids.toList()),
      ),
      if (snapshot.businessProfile case final profile?)
        'businessProfile': profile.toJson(),
      if (snapshot.regionId case final id?) 'region': id,
      if (snapshot.defaultCurrencyCode case final code?) 'currency': code,
      if (snapshot.favoriteCurrencyOrder case final order?) 'favorites': order,
    };
    await _store.saveSessions(snapshot.sessions);
    await _writePreferences(next);
    await _store.clearRestoreJournal();
    _sessions = snapshot.sessions;
    _preferences = next;
    _restorePending = false;
    historyUnavailable = false;
    _notify();
  }

  Future<T> _serialize<T>(Future<T> Function() run) {
    final operation = _writes.then((_) => run());
    _writes = operation.then<void>((_) {}, onError: (Object _) {});
    return operation;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    receiptPrinter.dispose();
    super.dispose();
  }
}
