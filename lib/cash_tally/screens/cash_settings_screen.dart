import 'package:flutter/material.dart';

import '../data/country_catalog.dart';
import '../l10n/app_localizations.dart';
import '../models/country_profile.dart';
import '../models/currency_definition.dart';
import '../state/app_scope.dart';
import 'backup_screen.dart';
import 'business_profile_screen.dart';
import 'denomination_settings_screen.dart';
import 'till_templates_screen.dart';

String appLanguageLabel(Locale locale) =>
    _languageNames[locale.toLanguageTag()] ??
    _languageNames[locale.languageCode] ??
    locale.toLanguageTag();

const _languageNames = <String, String>{
  'en': 'English',
  'zh-Hans': '简体中文',
  'zh-Hant': '繁體中文',
  'cs': 'Čeština',
  'de': 'Deutsch',
  'fr': 'Français',
  'it': 'Italiano',
  'nl': 'Nederlands',
  'bg': 'Български',
  'hr': 'Hrvatski',
  'el': 'Ελληνικά',
  'et': 'Eesti',
  'fi': 'Suomi',
  'lv': 'Latviešu',
  'lt': 'Lietuvių',
  'lb': 'Lëtzebuergesch',
  'mt': 'Malti',
  'pt': 'Português',
  'sk': 'Slovenčina',
  'sl': 'Slovenščina',
  'es': 'Español',
  'sv': 'Svenska',
  'nb': 'Norsk bokmål',
  'uk': 'Українська',
  'ru': 'Русский',
  'da': 'Dansk',
  'hu': 'Magyar',
  'pl': 'Polski',
  'tr': 'Türkçe',
  'id': 'Bahasa Indonesia',
  'hi': 'हिन्दी',
  'ms': 'Bahasa Melayu',
  'th': 'ไทย',
  'ur': 'اردو',
  'ar': 'العربية',
  'he': 'עברית',
  'ja': '日本語',
  'ko': '한국어',
};

class AppLanguageScreen extends StatelessWidget {
  const AppLanguageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('defaultLanguage'))),
      body: _SettingsList(
        children: [
          for (final locale in AppLocalizations.supportedLocales)
            ListTile(
              key: ValueKey('language-${locale.toLanguageTag()}'),
              title: Text(appLanguageLabel(locale)),
              selected: app.locale == locale,
              trailing: app.locale == locale ? const Icon(Icons.check) : null,
              onTap: () => _saveAndClose(context, app.setDefaultLocale(locale)),
            ),
        ],
      ),
    );
  }
}

class CashSettingsScreen extends StatelessWidget {
  const CashSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('cashTallySettings'))),
      body: _SettingsList(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text(
              context.tr('countingSetup'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          Card(
            child: Column(
              children: [
                _SettingsLink(
                  icon: Icons.store_outlined,
                  label: context.tr('businessProfile'),
                  subtitle: app.businessProfile.businessName.isEmpty
                      ? context.tr('businessProfileHelp')
                      : app.businessProfile.businessName,
                  destination: const BusinessProfileScreen(),
                ),
                const Divider(height: 1),
                _SettingsLink(
                  icon: Icons.point_of_sale_outlined,
                  label: context.tr('tillTemplates'),
                  subtitle: context.tr('tillTemplatesHelp'),
                  destination: const TillTemplatesScreen(),
                ),
                const Divider(height: 1),
                _SettingsLink(
                  icon: Icons.tune_outlined,
                  label: context.tr('denominationSettings'),
                  subtitle: context.tr('denominationSettingsHelp'),
                  destination: const DenominationSettingsScreen(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                _SettingsLink(
                  icon: Icons.public_outlined,
                  label: context.tr('cashCountryRegion'),
                  subtitle: _regionName(context, app.selectedCountry),
                  destination: const _CountryRegionScreen(),
                ),
                const Divider(height: 1),
                _SettingsLink(
                  icon: Icons.currency_exchange,
                  label: context.tr('defaultCurrency'),
                  subtitle: _currencyLabel(context, app.selectedCurrencyCode),
                  destination: const _CurrencySettingsScreen(pickDefault: true),
                ),
                const Divider(height: 1),
                _SettingsLink(
                  icon: Icons.star_outline_rounded,
                  label: context.tr('supportedCurrencies'),
                  destination: const _CurrencySettingsScreen(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: _SettingsLink(
              icon: Icons.settings_backup_restore,
              label: context.tr('backupAndRestore'),
              subtitle: context.tr('backupAndRestoreHelp'),
              destination: const BackupScreen(),
            ),
          ),
        ],
      ),
    );
  }
}

class _CountryRegionScreen extends StatelessWidget {
  const _CountryRegionScreen();

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('cashCountryRegion'))),
      body: _SettingsList(
        children: [
          for (final country in CountryCatalog.mostToLeastPopulous)
            ListTile(
              key: ValueKey('cash-region-${country.id}'),
              leading: Text(country.flag, style: const TextStyle(fontSize: 24)),
              title: Text(_regionName(context, country)),
              subtitle: Text(_currencyLabel(context, country.currencyCode)),
              trailing: app.selectedCountry.id == country.id
                  ? const Icon(Icons.check)
                  : null,
              onTap: () => _saveAndClose(context, app.selectCountry(country)),
            ),
        ],
      ),
    );
  }
}

class _CurrencySettingsScreen extends StatelessWidget {
  const _CurrencySettingsScreen({this.pickDefault = false});

  final bool pickDefault;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final favorites = app.favoriteCurrencyOrder;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr(
          pickDefault ? 'defaultCurrency' : 'supportedCurrencies',
        )),
      ),
      body: _SettingsList(
        children: [
          if (!pickDefault && favorites.length > 1) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(
                context.tr('favoriteCurrencyOrder'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: favorites.length,
              onReorder: (from, to) => _save(
                context,
                app.reorderFavoriteCurrencies(from, to),
              ),
              itemBuilder: (context, index) {
                final code = favorites[index];
                return ListTile(
                  key: ValueKey('favorite-$code'),
                  title: Text(_currencyLabel(context, code)),
                );
              },
            ),
            const Divider(),
          ],
          for (final currency in app.currencies)
            _buildCurrency(context, currency),
        ],
      ),
    );
  }

  Widget _buildCurrency(BuildContext context, CurrencyDefinition currency) {
    final app = AppScope.of(context);
    final code = currency.code;
    final favorite = app.favoriteCurrencyCodes.contains(code);
    final title = context.tr('currency$code');
    return ListTile(
      key: ValueKey('cash-currency-$code'),
      leading: CircleAvatar(
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: FittedBox(child: Text(currency.symbol)),
        ),
      ),
      title: Text(title),
      subtitle: Text(code),
      selected: pickDefault && app.selectedCurrencyCode == code,
      onTap: pickDefault
          ? () => _saveAndClose(context, app.setDefaultCurrency(code))
          : () => _save(context, app.toggleFavoriteCurrency(code)),
      trailing: pickDefault
          ? (app.selectedCurrencyCode == code ? const Icon(Icons.check) : null)
          : IconButton(
              tooltip: context.tr('favoriteCurrency'),
              onPressed: () => _save(context, app.toggleFavoriteCurrency(code)),
              icon: Icon(favorite ? Icons.star : Icons.star_border),
            ),
    );
  }
}

class _SettingsList extends StatelessWidget {
  const _SettingsList({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: children,
          ),
        ),
      );
}

class _SettingsLink extends StatelessWidget {
  const _SettingsLink({
    required this.icon,
    required this.label,
    required this.destination,
    this.subtitle,
  });

  final IconData icon;
  final String label;
  final Widget destination;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => ListTile(
        leading: Icon(icon),
        title: Text(label),
        subtitle: subtitle == null ? null : Text(subtitle!),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => destination),
        ),
      );
}

String _regionName(BuildContext context, CountryProfile country) {
  const translated = {'CN', 'HK', 'MO', 'TW'};
  return translated.contains(country.id)
      ? context.tr('cashRegion${country.id}')
      : country.localName;
}

String _currencyLabel(BuildContext context, String code) =>
    '$code · ${context.tr('currency$code')}';

Future<bool> _save(BuildContext context, Future<void> write) async {
  try {
    await write;
    return true;
  } on Object {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('selectionSaveFailed'))),
      );
    }
    return false;
  }
}

Future<void> _saveAndClose(BuildContext context, Future<void> write) async {
  if (await _save(context, write) &&
      context.mounted &&
      ModalRoute.of(context)?.isCurrent == true) {
    Navigator.of(context).pop();
  }
}
