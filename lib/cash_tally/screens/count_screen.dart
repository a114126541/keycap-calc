import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../screens/settings_screen/settings_controller.dart';
import '../core/formatters.dart';
import '../data/currency_catalog.dart';
import '../l10n/app_localizations.dart';
import '../models/business_profile.dart';
import '../models/cash_count_session.dart';
import '../models/count_mode.dart';
import '../models/currency_definition.dart';
import '../models/pos_reconciliation.dart';
import '../models/till_template.dart';
import '../services/closing_proof_service.dart';
import '../services/pos_import_service.dart';
import '../services/receipt_printer.dart';
import '../state/app_scope.dart';
import '../widgets/cash_keyboard.dart';
import '../widgets/cash_panels.dart';
import '../widgets/denomination_row.dart';
import '../widgets/receipt_print_button.dart';
import 'signature_capture_screen.dart';

class CountScreen extends StatefulWidget {
  const CountScreen({
    this.initialCurrencyCode,
    this.existingSession,
    this.mode = CountMode.professional,
    this.toolbarBuilder,
    this.onSaved,
    super.key,
  }) : assert(
          initialCurrencyCode != null || existingSession != null,
          'A currency or an existing session is required.',
        );

  final String? initialCurrencyCode;
  final CashCountSession? existingSession;
  final CountMode mode;
  final PreferredSizeWidget Function(Widget currencyAction)? toolbarBuilder;
  final VoidCallback? onSaved;

  @override
  State<CountScreen> createState() => _CountScreenState();
}

class _CountScreenState extends State<CountScreen> {
  late String _currencyCode;
  late String _sessionId;
  late String _documentNumber;
  late DateTime _createdAt;
  late Map<String, int> _quantities;
  late List<Denomination> _customDenominationSnapshots;
  late bool _blindCount;
  DateTime? _blindCountLockedAt;
  String? _cashierSignaturePngBase64;
  String? _managerSignaturePngBase64;
  PosReconciliation? _posReport;

  late final TextEditingController _expectedController;
  late final TextEditingController _floatController;
  late final TextEditingController _noteController;
  late final TextEditingController _closingTitleController;
  late final TextEditingController _businessNameController;
  late final TextEditingController _registrationIdController;
  late final TextEditingController _businessAddressController;
  late final TextEditingController _locationNameController;
  late final TextEditingController _tillNameController;
  late final TextEditingController _cashierNameController;
  late final TextEditingController _managerNameController;
  late final TextEditingController _shiftNameController;
  final _denominationScroll = ScrollController();
  final _summaryScroll = ScrollController();
  final _portraitScroll = ScrollController();

  var _saving = false;
  var _quickStep = 1;
  var _posImportBusy = false;
  var _closingDetailsExpanded = false;
  var _countedKind = DenominationKind.banknote;
  var _professionalDefaultsLoaded = false;

  CountMode get _mode => widget.existingSession?.mode ?? widget.mode;

  CurrencyDefinition get _currency {
    final configured = AppScope.read(
      context,
    ).countingCurrency(_currencyCode, keepVisible: _quantities.keys.toSet());
    final knownIds = configured.denominations.map((item) => item.id).toSet();
    return configured.copyWithDenominations(<Denomination>[
      ...configured.denominations,
      ..._customDenominationSnapshots.where((item) => knownIds.add(item.id)),
    ]);
  }

  bool get _quantitiesLocked => _blindCount && _blindCountLockedAt != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existingSession;
    final app = AppScope.read(context);
    final initialCode = widget.initialCurrencyCode ?? 'CZK';
    final configured = app.configuredCurrency(initialCode);
    final customSnapshots = configured.denominations
        .where((item) => item.customId != null)
        .toList(growable: false);
    _professionalDefaultsLoaded =
        existing != null || _mode == CountMode.professional;
    final profile = _professionalDefaultsLoaded
        ? app.businessProfile
        : const BusinessProfile();
    final seed = existing ??
        CashCountSession.create(
          initialCode,
          profile: profile,
          mode: _mode,
          customDenominations: customSnapshots,
        );
    _currencyCode = seed.currencyCode;
    _sessionId = seed.id;
    _documentNumber = seed.documentNumber;
    _createdAt = seed.createdAt;
    _quantities = Map<String, int>.from(seed.quantities);
    _customDenominationSnapshots = List<Denomination>.from(
      seed.customDenominations,
    );
    _blindCount = seed.blindCount;
    _blindCountLockedAt = seed.blindCountLockedAt;
    _cashierSignaturePngBase64 = seed.cashierSignaturePngBase64;
    _managerSignaturePngBase64 = seed.managerSignaturePngBase64;
    _posReport = seed.posReport;
    _expectedController = TextEditingController(
      text: AppFormatters.moneyInputFromMinor(
        seed.expectedMinorUnits,
        fractionDigits: _currency.fractionDigits,
      ),
    );
    _floatController = TextEditingController(
      text: AppFormatters.moneyInputFromMinor(
        seed.floatMinorUnits,
        fractionDigits: _currency.fractionDigits,
      ),
    );
    _noteController = TextEditingController(text: seed.note);
    _closingTitleController = TextEditingController(text: seed.closingTitle);
    _businessNameController = TextEditingController(text: seed.businessName);
    _registrationIdController =
        TextEditingController(text: seed.businessRegistrationId);
    _businessAddressController =
        TextEditingController(text: seed.businessAddress);
    _locationNameController = TextEditingController(text: seed.locationName);
    _tillNameController = TextEditingController(text: seed.tillName);
    _cashierNameController = TextEditingController(text: seed.cashierName);
    _managerNameController = TextEditingController(text: seed.managerName);
    _shiftNameController = TextEditingController(text: seed.shiftName);
  }

  @override
  void didUpdateWidget(covariant CountScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_mode == CountMode.professional && !_professionalDefaultsLoaded) {
      _applyBusinessProfile(AppScope.read(context).businessProfile);
      _professionalDefaultsLoaded = true;
    }
    final defaultCurrency = widget.initialCurrencyCode;
    if (widget.toolbarBuilder != null &&
        defaultCurrency != null &&
        oldWidget.initialCurrencyCode != defaultCurrency &&
        _quantities.isEmpty) {
      _currencyCode = defaultCurrency;
      _customDenominationSnapshots = AppScope.read(context)
          .configuredCurrency(defaultCurrency)
          .denominations
          .where((item) => item.customId != null)
          .toList(growable: false);
    }
  }

  @override
  void dispose() {
    _expectedController.dispose();
    _floatController.dispose();
    _noteController.dispose();
    _closingTitleController.dispose();
    _businessNameController.dispose();
    _registrationIdController.dispose();
    _businessAddressController.dispose();
    _locationNameController.dispose();
    _tillNameController.dispose();
    _cashierNameController.dispose();
    _managerNameController.dispose();
    _shiftNameController.dispose();
    _denominationScroll.dispose();
    _summaryScroll.dispose();
    _portraitScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final currency = _currency;
    final currencyChoices = CurrencyCatalog.displayOrder(
      _currencyCode,
      favoriteCodes: app.favoriteCurrencyCodes,
    );
    final currencyAction = _currencyAction(currencyChoices);
    return Scaffold(
      appBar: widget.toolbarBuilder?.call(currencyAction) ??
          _countAppBar(currencyAction),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final landscape =
                MediaQuery.orientationOf(context) == Orientation.landscape;
            final split = landscape && constraints.maxWidth >= cashSplitWidth;
            final counting = _countingControls(currency);
            final summary = _summaryContent(currency, spacious: split);
            final footer = _countFooter(currency);

            return Center(
              child: ConstrainedBox(
                constraints:
                    BoxConstraints(maxWidth: split ? cashWorkspaceWidth : 680),
                child: split
                    ? Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                        child: Row(
                          key: const ValueKey('cash-tally-two-panes'),
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              flex: 54,
                              child: CashPanel(
                                  child: _scrollPane(
                                _denominationScroll,
                                counting,
                                'cash-denomination-list',
                              )),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              flex: 46,
                              child: CashPanel(
                                  child: Column(
                                children: [
                                  Expanded(
                                      child: _scrollPane(_summaryScroll,
                                          summary, 'cash-summary-list')),
                                  footer,
                                ],
                              )),
                            ),
                          ],
                        ),
                      )
                    : Column(
                        children: [
                          Expanded(
                              child: _scrollPane(
                                  _portraitScroll,
                                  [
                                    _stackedPanel(counting),
                                    const SizedBox(height: 10),
                                    _stackedPanel(summary),
                                  ],
                                  'cash-portrait-list')),
                          footer,
                        ],
                      ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _stackedPanel(List<Widget> children) => CashPanel(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      );

  Widget _scrollPane(
          ScrollController controller, List<Widget> children, String key) =>
      Scrollbar(
        controller: controller,
        child: ListView(
          key: ValueKey(key),
          controller: controller,
          cacheExtent: 1000,
          padding: const EdgeInsets.all(12),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          children: children,
        ),
      );

  PreferredSizeWidget _countAppBar(Widget currencyAction) {
    final professional = _mode == CountMode.professional;
    final title = context.tr(
      professional
          ? 'professionalClose'
          : widget.existingSession == null
              ? 'quickCountTitle'
              : 'editCount',
    );
    return AppBar(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      scrolledUnderElevation: 0,
      titleSpacing: professional ? 8 : null,
      actionsPadding: const EdgeInsetsDirectional.only(end: 8),
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(child: Text(title, overflow: TextOverflow.ellipsis)),
          if (professional)
            IconButton(
              tooltip: context.tr('professionalCloseInfo'),
              icon: const Icon(LucideIcons.info, size: 21),
              onPressed: _showProfessionalInfo,
            ),
        ],
      ),
      actions: [currencyAction],
    );
  }

  Widget _currencyAction(List<CurrencyDefinition> choices) {
    final theme = Theme.of(context);
    return PopupMenuButton<String>(
      key: const ValueKey('count-currency-switch'),
      tooltip: context.tr('currency'),
      enabled: !_quantitiesLocked,
      position: PopupMenuPosition.under,
      borderRadius: BorderRadius.circular(12),
      itemBuilder: (_) => [
        for (final currency in choices)
          CheckedPopupMenuItem<String>(
            value: currency.code,
            checked: currency.code == _currencyCode,
            child: Text(_currencyLabel(currency)),
          ),
      ],
      onSelected: _changeCurrency,
      child: SizedBox(
        height: kMinInteractiveDimension,
        child: Center(
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: theme.colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_currencyCode, style: theme.textTheme.labelLarge),
                  const SizedBox(width: 4),
                  Icon(
                    LucideIcons.chevronDown,
                    size: 16,
                    color: _quantitiesLocked ? theme.disabledColor : null,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _currencyLabel(CurrencyDefinition currency) =>
      '${currency.code} · ${context.tr('currency${currency.code}')}';

  List<Widget> _countingControls(CurrencyDefinition currency) {
    final banknotes = _countedKind == DenominationKind.banknote;
    final denominations = (banknotes ? currency.banknotes : currency.coins)
      ..sort((a, b) => b.minorUnits.compareTo(a.minorUnits));
    final canClear =
        !_quantitiesLocked && denominations.any((item) => _quantity(item) > 0);
    final theme = Theme.of(context);
    return [
      Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Flexible(child: _denominationTab(DenominationKind.banknote)),
                const SizedBox(width: 4),
                Flexible(child: _denominationTab(DenominationKind.coin)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 112),
            child: TextButton.icon(
              onPressed: canClear ? () => _clearSection(denominations) : null,
              style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 6)),
              icon: const Icon(LucideIcons.trash2, size: 17),
              label: Text(context.tr('clear'),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
      SegmentedButton<int>(
        showSelectedIcon: false,
        expandedInsets: EdgeInsets.zero,
        style: ButtonStyle(
          padding:
              const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 4)),
          shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(9))),
          side: WidgetStatePropertyAll(
              BorderSide(color: theme.colorScheme.outlineVariant)),
        ),
        segments: const [
          ButtonSegment<int>(value: 1, label: Text('×1')),
          ButtonSegment<int>(value: 10, label: Text('×10')),
          ButtonSegment<int>(value: 50, label: Text('×50')),
          ButtonSegment<int>(value: 100, label: Text('×100')),
        ],
        selected: {_quickStep},
        onSelectionChanged: _quantitiesLocked
            ? null
            : (values) => setState(() => _quickStep = values.first),
      ),
      const SizedBox(height: 12),
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 9),
        child: Row(children: [
          Expanded(
              child: Text(context.tr('denomination'),
                  style: theme.textTheme.labelLarge)),
          SizedBox(
            width: DenominationRow.stepperWidth,
            child: Text(context.tr('quantity'),
                textAlign: TextAlign.center, style: theme.textTheme.labelLarge),
          ),
          Expanded(
              child: Text(context.tr('subtotal'),
                  textAlign: TextAlign.end, style: theme.textTheme.labelLarge)),
        ]),
      ),
      const Divider(height: 1),
      if (denominations.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Text(context.tr('noDenominations')),
        ),
      for (final item in denominations) ...[
        _denominationRow(currency, item),
        const Divider(height: 1),
      ],
    ];
  }

  Widget _denominationTab(DenominationKind kind) {
    final colors = Theme.of(context).colorScheme;
    final selected = _countedKind == kind;
    final banknote = kind == DenominationKind.banknote;
    return Semantics(
      selected: selected,
      child: TextButton.icon(
        key: ValueKey('cash-kind-${kind.name}'),
        onPressed: () => setState(() => _countedKind = kind),
        icon:
            Icon(banknote ? LucideIcons.banknote : LucideIcons.coins, size: 19),
        label: Text(context.tr(banknote ? 'banknotes' : 'coins'),
            maxLines: 1, overflow: TextOverflow.ellipsis),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          backgroundColor: selected ? colors.primaryContainer : null,
          foregroundColor:
              selected ? colors.onPrimaryContainer : colors.onSurface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        ),
      ),
    );
  }

  Widget _blindCountControl() => CashPanel(
        child: SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          value: _blindCount,
          onChanged: _quantitiesLocked
              ? null
              : (value) => setState(() => _blindCount = value),
          secondary: const Icon(LucideIcons.eyeOff),
          title: Text(context.tr('blindCount')),
          subtitle: Text(
            _quantitiesLocked
                ? context.tr('blindCountLocked')
                : context.tr('blindCountHelp'),
          ),
        ),
      );

  List<Widget> _summaryContent(CurrencyDefinition currency,
      {required bool spacious}) {
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final total = _totalMinorUnits(currency);
    return [
      CashSummaryRows(
          currency: currency, quantityFor: _quantity, spacious: spacious),
      const SizedBox(height: 8),
      CashAmountHighlight(
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: Text(
                context.tr('total'),
                style:
                    const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
            ),
            Expanded(
              flex: 6,
              child: CashAmountText(
                currency.formatMinor(total,
                    localeCode: locale, fixedFractionDigits: true),
                style: TextStyle(
                  fontSize: spacious ? 35 : 32,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
      if (_mode == CountMode.professional)
        ..._settlementFields(currency, total),
      const SizedBox(height: 16),
      Text(context.tr('note'), style: theme.textTheme.titleMedium),
      const SizedBox(height: 6),
      TextField(
        key: const ValueKey('cash-note'),
        controller: _noteController,
        onTapOutside: dismissCashKeyboard,
        minLines: 2,
        maxLines: 4,
        textCapitalization: TextCapitalization.sentences,
        inputFormatters: const [SentenceCaseTextFormatter()],
        decoration: InputDecoration(
          hintText: context.tr('cashNotePlaceholder'),
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    ];
  }

  List<Widget> _settlementFields(CurrencyDefinition currency, int total) {
    final theme = Theme.of(context);
    final revealRequired = _blindCount && !_quantitiesLocked;
    final expected = AppFormatters.parseMoneyToMinor(
      _expectedController.text,
      fractionDigits: currency.fractionDigits,
    );
    final difference = expected == null ? null : total - expected;
    final locale = Localizations.localeOf(context).toLanguageTag();

    return [
      const SizedBox(height: 18),
      Text(context.tr('cashCheck'), style: theme.textTheme.titleLarge),
      const SizedBox(height: 10),
      _closingDetailsCard(),
      const SizedBox(height: 8),
      _blindCountControl(),
      const SizedBox(height: 8),
      if (revealRequired)
        CashPanel(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(context.tr('blindCountBeforeReveal')),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: _lockBlindCount,
                  icon: const Icon(LucideIcons.lock),
                  label: Text(context.tr('finishBlindCount')),
                ),
              ],
            ),
          ),
        )
      else
        CashPanel(
          child: Column(
            children: [
              _reconciliationRow(
                icon: LucideIcons.clipboardCheck,
                label: context.tr('cashExpectedAmount'),
                value: _moneyField(
                  key: const ValueKey('cash-expected'),
                  controller: _expectedController,
                  label: context.tr('expectedState', {'code': currency.code}),
                  currency: currency,
                ),
              ),
              const Divider(height: 1, indent: 10, endIndent: 10),
              _reconciliationRow(
                icon: LucideIcons.wallet,
                label: context.tr('cashRetainedFloat'),
                value: _moneyField(
                  key: const ValueKey('cash-float'),
                  controller: _floatController,
                  label: context.tr('leaveInTill', {'code': currency.code}),
                  currency: currency,
                ),
              ),
              const Divider(height: 1, indent: 10, endIndent: 10),
              _reconciliationRow(
                icon: LucideIcons.calculator,
                label: context.tr('difference'),
                value: CashAmountText(
                  difference == null
                      ? '—'
                      : currency.formatMinor(
                          difference,
                          localeCode: locale,
                          fixedFractionDigits: true,
                        ),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: difference != null && difference < 0
                        ? theme.colorScheme.error
                        : null,
                  ),
                ),
              ),
            ],
          ),
        ),
    ];
  }

  Widget _reconciliationRow({
    required IconData icon,
    required String label,
    required Widget value,
  }) =>
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            Icon(icon, size: 19),
            const SizedBox(width: 8),
            Expanded(child: Text(label)),
            const SizedBox(width: 8),
            Expanded(child: value),
          ],
        ),
      );

  Widget _moneyField({
    required Key key,
    required TextEditingController controller,
    required String label,
    required CurrencyDefinition currency,
  }) =>
      Semantics(
        label: label,
        child: TextField(
          key: key,
          controller: controller,
          onTapOutside: dismissCashKeyboard,
          textAlign: TextAlign.end,
          keyboardType: const TextInputType.numberWithOptions(
            decimal: true,
            signed: true,
          ),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\- ]')),
          ],
          decoration: InputDecoration(
            isDense: true,
            prefixText: currency.symbolBefore ? currency.symbol : null,
            suffixText: currency.symbolBefore ? null : currency.symbol,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onChanged: (_) => setState(() {}),
        ),
      );

  Widget _countFooter(CurrencyDefinition currency) => CashActionBar(
        primary: FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(LucideIcons.check),
          label: Text(context.tr('save')),
        ),
        secondary: ReceiptPrinter.isSupported
            ? ReceiptPrintButton(currency: currency, quantityFor: _quantity)
            : null,
      );

  Widget _closingDetailsCard() {
    final templates = AppScope.read(context).tillTemplates;
    return CashPanel(
      child: ExpansionTile(
        initiallyExpanded: _closingDetailsExpanded,
        onExpansionChanged: (value) => _closingDetailsExpanded = value,
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        leading: const Icon(LucideIcons.clipboardList),
        title: Text(context.tr('closingDetails')),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: <Widget>[
          Row(
            children: [
              Expanded(child: Text(_documentNumber)),
              IconButton(
                tooltip: context.tr('professionalCloseInfo'),
                onPressed: _showProfessionalInfo,
                icon: const Icon(LucideIcons.info, size: 19),
              ),
            ],
          ),
          if (templates.isNotEmpty)
            OutlinedButton.icon(
              onPressed: () => _chooseTillTemplate(templates),
              icon: const Icon(LucideIcons.clipboardList),
              label: Text(context.tr('tillTemplate')),
            ),
          TextField(
            controller: _closingTitleController,
            onTapOutside: dismissCashKeyboard,
            textCapitalization: TextCapitalization.sentences,
            inputFormatters: const <TextInputFormatter>[
              SentenceCaseTextFormatter(),
            ],
            decoration: InputDecoration(
              labelText: context.tr('closingTitle'),
              helperText: context.tr('closingTitleHelp'),
              prefixIcon: const Icon(Icons.title_outlined),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            context.tr('closingSnapshotHelp'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _posImportBusy ? null : _importPosReport,
            icon: _posImportBusy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.point_of_sale_outlined),
            label: Text(context.tr('importPosReport')),
          ),
          if (_posReport != null) ...<Widget>[
            const SizedBox(height: 8),
            _posReportSummary(),
          ],
          const SizedBox(height: 8),
          _detailField(
            _businessNameController,
            context.tr('businessName'),
            Icons.business_outlined,
          ),
          _detailField(
            _registrationIdController,
            context.tr('registrationId'),
            Icons.badge_outlined,
            capitalize: false,
          ),
          _detailField(
            _businessAddressController,
            context.tr('businessAddress'),
            Icons.location_on_outlined,
          ),
          _detailField(
            _locationNameController,
            context.tr('locationName'),
            Icons.store_outlined,
          ),
          _detailField(
            _tillNameController,
            context.tr('tillName'),
            Icons.point_of_sale_outlined,
          ),
          _detailField(
            _shiftNameController,
            context.tr('shiftName'),
            Icons.schedule_outlined,
          ),
          _detailField(
            _cashierNameController,
            context.tr('cashierName'),
            Icons.person_outline,
          ),
          _signatureField(
            label: context.tr('cashierSignature'),
            value: _cashierSignaturePngBase64,
            onChanged: (value) {
              setState(() => _cashierSignaturePngBase64 = value);
            },
          ),
          _detailField(
            _managerNameController,
            context.tr('managerName'),
            Icons.supervisor_account_outlined,
          ),
          _signatureField(
            label: context.tr('managerSignature'),
            value: _managerSignaturePngBase64,
            onChanged: (value) {
              setState(() => _managerSignaturePngBase64 = value);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _showProfessionalInfo() => showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(context.tr('professionalClose')),
          content: Text(context.tr('professionalCloseHelp')),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(context.tr('close')),
            ),
          ],
        ),
      );

  void _applyBusinessProfile(BusinessProfile profile) {
    _businessNameController.text = profile.businessName;
    _registrationIdController.text = profile.registrationId;
    _businessAddressController.text = profile.address;
    _locationNameController.text = profile.locationName;
    _tillNameController.text = profile.tillName;
    _cashierNameController.text = profile.cashierName;
    _managerNameController.text = profile.managerName;
    _shiftNameController.text = profile.shiftName;
  }

  Future<void> _chooseTillTemplate(List<TillTemplate> templates) async {
    final template = await showDialog<TillTemplate>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(context.tr('tillTemplate')),
        children: [
          for (final item in templates)
            SimpleDialogOption(
              onPressed: _quantitiesLocked && item.currencyCode != _currencyCode
                  ? null
                  : () => Navigator.pop(dialogContext, item),
              child: Text('${item.name} · ${item.currencyCode}'),
            ),
        ],
      ),
    );
    if (template == null || !mounted) return;
    await _changeCurrency(template.currencyCode);
    if (!mounted || _currencyCode != template.currencyCode) return;
    setState(() {
      final profile = AppScope.read(context).businessProfile;
      _applyBusinessProfile(template.profile.withDefaults(profile));
      _floatController.text = AppFormatters.moneyInputFromMinor(
        template.floatMinorUnits,
        fractionDigits: _currency.fractionDigits,
      );
    });
  }

  Widget _detailField(
    TextEditingController controller,
    String label,
    IconData icon, {
    bool capitalize = true,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        onTapOutside: dismissCashKeyboard,
        textInputAction: TextInputAction.next,
        textCapitalization:
            capitalize ? TextCapitalization.sentences : TextCapitalization.none,
        inputFormatters: capitalize
            ? const <TextInputFormatter>[SentenceCaseTextFormatter()]
            : null,
        decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
      ),
    );
  }

  Future<void> _importPosReport() async {
    final path = await FlutterFileDialog.pickFile(
      params: const OpenFileDialogParams(
        fileExtensionsFilter: <String>['csv', 'txt'],
        mimeTypesFilter: <String>['text/csv', 'text/plain'],
        copyFileToCacheDir: true,
      ),
    );
    if (path == null || !mounted) {
      return;
    }
    setState(() => _posImportBusy = true);
    try {
      final report = const PosImportService().parse(
        bytes: await File(path).readAsBytes(),
        sourceFileName: path.split(Platform.pathSeparator).last,
      );
      if (report.currencyCode != _currencyCode) {
        throw const PosImportException('currencyMismatch');
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _posReport = report;
        _expectedController.text = AppFormatters.moneyInputFromMinor(
          report.expectedCashMinorUnits,
          fractionDigits: _currency.fractionDigits,
        );
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.tr('posImportSucceeded'))));
    } on PosImportException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_posImportError(error.code))));
      }
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.tr('posImportFailed'))));
      }
    } finally {
      if (mounted) {
        setState(() => _posImportBusy = false);
      }
    }
  }

  String _posImportError(String code) {
    return switch (code) {
      'emptyFile' => context.tr('posImportEmpty'),
      'currencyMissing' => context.tr('posImportCurrencyMissing'),
      'expectedCashMissing' => context.tr('posImportExpectedMissing'),
      'amountInvalid' => context.tr('posImportAmountInvalid'),
      'currencyMismatch' => context.tr('posImportCurrencyMismatch'),
      _ => context.tr('posImportFailed'),
    };
  }

  Widget _posReportSummary() {
    final report = _posReport!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final localeCode = Localizations.localeOf(context).toLanguageTag();
    final rows = <String>[
      '${context.tr('posReportId')}: ${report.id}',
      '${context.tr('posSource')}: ${report.sourceFileName}',
      '${context.tr('posExpectedCash')}: ${_currency.formatMinor(report.expectedCashMinorUnits ?? 0, localeCode: localeCode)}',
      if (report.cardMinorUnits != null)
        '${context.tr('posCardTotal')}: ${_currency.formatMinor(report.cardMinorUnits!, localeCode: localeCode)}',
      if (report.totalSalesMinorUnits != null)
        '${context.tr('posTotalSales')}: ${_currency.formatMinor(report.totalSalesMinorUnits!, localeCode: localeCode)}',
      '${context.tr('posSourceHash')}: ${report.sourceSha256.substring(0, 16)}…',
    ];
    return Card(
      color: colors.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final row in rows)
              Text(row, style: TextStyle(color: colors.onSecondaryContainer)),
          ],
        ),
      ),
    );
  }

  Widget _signatureField({
    required String label,
    required String? value,
    required ValueChanged<String?> onChanged,
  }) {
    Widget preview = const Icon(Icons.draw_outlined, size: 32);
    if (value != null) {
      try {
        preview = Image.memory(
          base64Decode(value),
          width: 96,
          height: 44,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined),
        );
      } on FormatException {
        preview = const Icon(Icons.broken_image_outlined);
      }
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).colorScheme.outline),
          borderRadius: BorderRadius.circular(12),
        ),
        child: ListTile(
          leading: SizedBox(width: 96, child: Center(child: preview)),
          title: Text(label),
          subtitle: Text(
            value == null
                ? context.tr('signatureMissing')
                : context.tr('signatureCaptured'),
          ),
          trailing: value == null
              ? const Icon(Icons.chevron_right)
              : IconButton(
                  tooltip: context.tr('clear'),
                  onPressed: () => onChanged(null),
                  icon: const Icon(Icons.delete_outline),
                ),
          onTap: () async {
            final result = await Navigator.of(context).push<String>(
              MaterialPageRoute<String>(
                builder: (_) => SignatureCaptureScreen(title: label),
              ),
            );
            if (result != null && mounted) {
              onChanged(result);
            }
          },
        ),
      ),
    );
  }

  Widget _denominationRow(
      CurrencyDefinition currency, Denomination denomination) {
    return DenominationRow(
      currency: currency,
      denomination: denomination,
      quantity: _quantity(denomination),
      enabled: !_quantitiesLocked,
      onChanged: (value) => _setQuantity(denomination, value),
      onEdit: () => _editQuantity(denomination),
      step: _quickStep,
    );
  }

  int _totalMinorUnits(CurrencyDefinition currency) {
    var total = 0;
    for (final denomination in currency.denominations) {
      total += denomination.minorUnits * _quantity(denomination);
    }
    return total;
  }

  int _quantity(Denomination denomination) => _quantities[denomination.id] ?? 0;

  void _setQuantity(Denomination denomination, int value) {
    if (_quantitiesLocked) {
      return;
    }
    if (SettingsController.hapticsEnabled) {
      HapticFeedback.selectionClick();
    }
    setState(() {
      if (value <= 0) {
        _quantities.remove(denomination.id);
      } else {
        _quantities[denomination.id] = value;
      }
    });
  }

  Future<void> _editQuantity(Denomination denomination) async {
    if (_quantitiesLocked) {
      return;
    }
    final quantityField = GlobalKey<FormFieldState<String>>();
    final result = await showDialog<int>(
      context: context,
      builder: (dialogContext) {
        void submit() {
          final field = quantityField.currentState;
          if (field != null && field.validate()) {
            Navigator.pop(dialogContext, int.parse(field.value!));
          }
        }

        return AlertDialog(
          title: Text(
            context.tr('quantityTitle', {'label': denomination.label}),
          ),
          content: TextFormField(
            key: quantityField,
            onTapOutside: dismissCashKeyboard,
            initialValue: _quantity(denomination).toString(),
            autofocus: true,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(labelText: context.tr('quantity')),
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.digitsOnly,
            ],
            validator: (value) => int.tryParse(value ?? '') == null
                ? context.tr('quantityInvalid')
                : null,
            onEditingComplete: submit,
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(context.tr('cancel')),
            ),
            FilledButton(onPressed: submit, child: Text(context.tr('confirm'))),
          ],
        );
      },
    );
    if (result != null && mounted) {
      _setQuantity(denomination, result);
    }
  }

  Future<void> _changeCurrency(String code) async {
    if (_quantitiesLocked || code == _currencyCode) {
      return;
    }
    final clearedFields = <String>[
      if (_quantities.isNotEmpty) context.tr('denominationSettings'),
      if (_expectedController.text.trim().isNotEmpty)
        context.tr('expectedState', {'code': _currencyCode}),
      if (_floatController.text.trim().isNotEmpty)
        context.tr('leaveInTill', {'code': _currencyCode}),
      if (_cashierSignaturePngBase64 != null) context.tr('cashierSignature'),
      if (_managerSignaturePngBase64 != null) context.tr('managerSignature'),
      if (_posReport != null) context.tr('posReconciliation'),
    ];
    if (clearedFields.isNotEmpty) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(context.tr('changeCurrencyTitle')),
          content: Text('${context.tr('clear')}\n${clearedFields.join('\n')}'),
          scrollable: true,
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(context.tr('keep')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(context.tr('change')),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) {
        return;
      }
    }
    setState(() {
      _currencyCode = code;
      _quantities.clear();
      _expectedController.clear();
      _floatController.clear();
      _blindCountLockedAt = null;
      _cashierSignaturePngBase64 = null;
      _managerSignaturePngBase64 = null;
      _posReport = null;
      _customDenominationSnapshots = AppScope.read(context)
          .configuredCurrency(code)
          .denominations
          .where((item) => item.customId != null)
          .toList(growable: false);
    });
  }

  Future<void> _clearSection(List<Denomination> denominations) async {
    if (_quantitiesLocked) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.tr('clearSectionTitle')),
        content: Text(context.tr('clearSectionBody')),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.tr('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.tr('clear')),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      setState(() {
        for (final denomination in denominations) {
          _quantities.remove(denomination.id);
        }
      });
    }
  }

  Future<void> _lockBlindCount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.tr('finishBlindCount')),
        content: Text(context.tr('finishBlindCountConfirm')),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.tr('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.tr('lockAndContinue')),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      setState(() => _blindCountLockedAt = DateTime.now());
    }
  }

  Future<void> _save() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final includeClosing =
        _mode == CountMode.professional || widget.existingSession != null;
    if (includeClosing && _blindCount && !_quantitiesLocked) {
      ScaffoldMessenger.of(context).showSnackBar(
        CashActionBar.feedback(context, context.tr('finishBlindBeforeSave')),
      );
      return;
    }
    final app = AppScope.read(context);
    final currency = _currency;
    String closingText(TextEditingController field) =>
        includeClosing ? field.text.trim() : '';

    int? closingAmount(TextEditingController field) => includeClosing
        ? AppFormatters.parseMoneyToMinor(
            field.text,
            fractionDigits: currency.fractionDigits,
          )
        : null;

    final session = CashCountSession(
      id: _sessionId,
      documentNumber: _documentNumber,
      currencyCode: _currencyCode,
      createdAt: _createdAt,
      updatedAt: DateTime.now(),
      quantities: _quantities,
      expectedMinorUnits: closingAmount(_expectedController),
      floatMinorUnits: closingAmount(_floatController),
      note: _noteController.text.trim(),
      closingTitle: closingText(_closingTitleController),
      businessName: closingText(_businessNameController),
      businessRegistrationId: closingText(_registrationIdController),
      businessAddress: closingText(_businessAddressController),
      locationName: closingText(_locationNameController),
      tillName: closingText(_tillNameController),
      cashierName: closingText(_cashierNameController),
      managerName: closingText(_managerNameController),
      shiftName: closingText(_shiftNameController),
      cashierSignaturePngBase64:
          includeClosing ? _cashierSignaturePngBase64 : null,
      managerSignaturePngBase64:
          includeClosing ? _managerSignaturePngBase64 : null,
      blindCount: includeClosing && _blindCount,
      blindCountLockedAt: includeClosing ? _blindCountLockedAt : null,
      mode: _mode,
      customDenominations: _customDenominationSnapshots,
      posReport: includeClosing ? _posReport : null,
    );
    final proofed = session.copyWith(
      closingHash: ClosingProofService.hashFor(session, currency),
    );

    setState(() => _saving = true);
    try {
      final saved = await app.saveSession(proofed);
      if (!mounted) {
        return;
      }
      setState(() => _saving = false);
      if (!saved) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(
            CashActionBar.feedback(context, context.tr('saveFailed')));
        return;
      }
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(CashActionBar.feedback(context, context.tr('saved')));
      final onSaved = widget.onSaved;
      if (onSaved == null) {
        Navigator.of(context).pop();
      } else {
        onSaved();
      }
    } on Object {
      if (!mounted) {
        return;
      }
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(CashActionBar.feedback(context, context.tr('saveFailed')));
    }
  }
}
