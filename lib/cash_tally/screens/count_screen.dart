import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';

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
import '../state/app_scope.dart';
import '../widgets/cash_keyboard.dart';
import '../widgets/denomination_row.dart';
import 'signature_capture_screen.dart';

class CountScreen extends StatefulWidget {
  const CountScreen({
    this.initialCurrencyCode,
    this.existingSession,
    this.mode = CountMode.professional,
    this.template,
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
  final TillTemplate? template;
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
  late CountMode _mode;
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

  var _saving = false;
  var _quickStep = 1;
  var _posImportBusy = false;
  var _closingDetailsExpanded = false;

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
    final template = widget.template;
    final initialCode =
        template?.currencyCode ?? widget.initialCurrencyCode ?? 'CZK';
    final configured = app.configuredCurrency(initialCode);
    final customSnapshots = configured.denominations
        .where((item) => item.customId != null)
        .toList(growable: false);
    final profile = widget.mode == CountMode.professional
        ? template?.profile.withDefaults(app.businessProfile) ??
            app.businessProfile
        : const BusinessProfile();
    final seed = existing ??
        CashCountSession.create(
          initialCode,
          profile: profile,
          mode: widget.mode,
          floatMinorUnits: template?.floatMinorUnits,
          customDenominations: customSnapshots,
        );
    _currencyCode = seed.currencyCode;
    _sessionId = seed.id;
    _documentNumber = seed.documentNumber;
    _createdAt = seed.createdAt;
    _quantities = Map<String, int>.from(seed.quantities);
    _mode = seed.mode;
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
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
            final split = landscape && constraints.maxWidth >= 620;
            final showFooter = !keyboardOpen || constraints.maxHeight >= 240;
            final professional = _mode == CountMode.professional;
            final counting = _countingControls(
              blindCountControl:
                  professional && !split ? _blindCountControl() : null,
            );
            final settlement = _settlementFields(split: split);

            return Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: split ? 1120 : 680),
                child: Column(
                  children: [
                    Expanded(
                      child: split
                          ? Row(
                              key: const ValueKey('cash-tally-two-panes'),
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(child: _countList(counting)),
                                const VerticalDivider(width: 1),
                                Expanded(child: _countList(settlement)),
                              ],
                            )
                          : _countList([...counting, ...settlement]),
                    ),
                    if (showFooter) _countFooter(split: split),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

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
              icon: const Icon(Icons.info_outline, size: 21),
              onPressed: () => showDialog<void>(
                context: context,
                builder: (context) => AlertDialog(
                  title: Text(title),
                  content: Text(context.tr('professionalCloseHelp')),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(context.tr('close')),
                    ),
                  ],
                ),
              ),
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
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_currencyCode, style: theme.textTheme.labelLarge),
              const SizedBox(width: 4),
              Icon(
                Icons.swap_horiz_rounded,
                size: 20,
                color: _quantitiesLocked ? theme.disabledColor : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _currencyLabel(CurrencyDefinition currency) =>
      '${currency.code} · ${context.tr('currency${currency.code}')}';

  Widget _countList(List<Widget> children) => ListView(
        primary: false,
        // Keep nearby denomination rows mounted during repeated entry.
        cacheExtent: 1600,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: children,
      );

  List<Widget> _countingControls({Widget? blindCountControl}) {
    final currency = _currency;
    final banknotes = currency.banknotes.reversed.toList(growable: false);
    final coins = currency.coins.reversed.toList(growable: false);
    return [
      SegmentedButton<int>(
        showSelectedIcon: MediaQuery.sizeOf(context).width >= 340,
        style: const ButtonStyle(
          padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 8)),
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
      const SizedBox(height: 6),
      Text(
        context.tr('tapToAddHelp'),
        style: Theme.of(context).textTheme.bodySmall,
      ),
      if (blindCountControl != null) blindCountControl,
      const SizedBox(height: 24),
      _SectionHeader(
        title: context.tr('banknotes'),
        icon: Icons.payments_outlined,
        onClear:
            !_quantitiesLocked && banknotes.any((item) => _quantity(item) > 0)
                ? () => _clearSection(banknotes)
                : null,
      ),
      const SizedBox(height: 8),
      ...banknotes.map(_denominationRow),
      const SizedBox(height: 24),
      _SectionHeader(
        title: context.tr('coins'),
        icon: Icons.toll_outlined,
        onClear: !_quantitiesLocked && coins.any((item) => _quantity(item) > 0)
            ? () => _clearSection(coins)
            : null,
      ),
      const SizedBox(height: 8),
      ...coins.map(_denominationRow),
      const SizedBox(height: 24),
    ];
  }

  Widget _blindCountControl() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Card(
          child: SwitchListTile(
            value: _blindCount,
            onChanged: _quantitiesLocked
                ? null
                : (value) => setState(() => _blindCount = value),
            secondary: const Icon(Icons.visibility_off_outlined),
            title: Text(context.tr('blindCount')),
            subtitle: Text(
              _quantitiesLocked
                  ? context.tr('blindCountLocked')
                  : context.tr('blindCountHelp'),
            ),
          ),
        ),
      );

  List<Widget> _settlementFields({required bool split}) {
    final professional = _mode == CountMode.professional;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final currency = _currency;
    final revealRequired = _blindCount && !_quantitiesLocked;
    final expected = revealRequired
        ? null
        : AppFormatters.parseMoneyToMinor(
            _expectedController.text,
            fractionDigits: currency.fractionDigits,
          );
    final difference = expected == null ? null : _totalMinorUnits - expected;
    final formattedDifference = difference == null
        ? null
        : currency.formatMinor(
            difference,
            localeCode: Localizations.localeOf(context).toLanguageTag(),
          );
    final (differenceBackground, differenceForeground) = switch (difference) {
      0 => (scheme.primaryContainer, scheme.onPrimaryContainer),
      final int amount when amount < 0 => (
          scheme.errorContainer,
          scheme.onErrorContainer
        ),
      _ => (scheme.tertiaryContainer, scheme.onTertiaryContainer),
    };

    return [
      if (professional) ...[
        _closingDetailsCard(),
        if (split) _blindCountControl() else const SizedBox(height: 16),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 4,
          children: [
            Text(context.tr('cashCheck'), style: theme.textTheme.titleLarge),
            if (split && formattedDifference != null)
              DecoratedBox(
                decoration: BoxDecoration(
                  color: differenceBackground,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Text(
                    '${context.tr('difference')} $formattedDifference',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: differenceForeground,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (revealRequired)
          Card(
            color: scheme.secondaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    context.tr('blindCountBeforeReveal'),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSecondaryContainer,
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _lockBlindCount,
                    icon: const Icon(Icons.lock_outline),
                    label: Text(context.tr('finishBlindCount')),
                  ),
                ],
              ),
            ),
          )
        else ...[
          _moneyField(
            controller: _expectedController,
            label: context.tr('expectedState', {'code': currency.code}),
            help: context.tr('expectedHelp'),
            icon: Icons.fact_check_outlined,
          ),
          const SizedBox(height: 12),
          _moneyField(
            controller: _floatController,
            label: context.tr('leaveInTill', {'code': currency.code}),
            help: context.tr('leaveInTillHelp'),
            icon: Icons.savings_outlined,
          ),
        ],
        if (!split && formattedDifference != null) ...[
          const SizedBox(height: 12),
          Card(
            color: differenceBackground,
            child: ListTile(
              textColor: differenceForeground,
              title: Text(context.tr('difference')),
              trailing: Text(
                formattedDifference,
                style: theme.textTheme.titleLarge?.copyWith(
                  color: differenceForeground,
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
      ],
      TextField(
        controller: _noteController,
        onTapOutside: dismissCashKeyboard,
        minLines: 2,
        maxLines: 4,
        textCapitalization: TextCapitalization.sentences,
        inputFormatters: const [SentenceCaseTextFormatter()],
        decoration: InputDecoration(
          labelText: context.tr('note'),
          prefixIcon: const Icon(Icons.notes_outlined),
        ),
      ),
    ];
  }

  Widget _moneyField({
    required TextEditingController controller,
    required String label,
    required String help,
    required IconData icon,
  }) =>
      TextField(
        controller: controller,
        onTapOutside: dismissCashKeyboard,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\- ]')),
        ],
        decoration: InputDecoration(
          labelText: label,
          helperText: help,
          helperMaxLines: 3,
          prefixIcon: Icon(icon),
        ),
        onChanged: (_) => setState(() {}),
      );

  Widget _countFooter({required bool split}) {
    final theme = Theme.of(context);
    const padding = EdgeInsets.symmetric(horizontal: 16, vertical: 8);
    final total = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(context.tr('total')),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: Text(
            _currency.formatMinor(
              _totalMinorUnits,
              localeCode: Localizations.localeOf(context).toLanguageTag(),
            ),
            style: theme.textTheme.headlineSmall,
          ),
        ),
      ],
    );
    final save = FilledButton.icon(
      onPressed: _saving ? null : _save,
      icon: _saving
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.check),
      label: Text(context.tr('save')),
    );

    return Material(
      elevation: 3,
      color: theme.colorScheme.surfaceContainer,
      child: split
          ? IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: Padding(padding: padding, child: total)),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: Padding(
                      padding: padding,
                      child: Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: save,
                      ),
                    ),
                  ),
                ],
              ),
            )
          : Padding(
              padding: padding,
              child: Row(
                children: [
                  Expanded(child: total),
                  const SizedBox(width: 8),
                  save,
                ],
              ),
            ),
    );
  }

  Widget _closingDetailsCard() {
    return Card(
      child: ExpansionTile(
        initiallyExpanded: _closingDetailsExpanded,
        onExpansionChanged: (value) => _closingDetailsExpanded = value,
        leading: const Icon(Icons.assignment_outlined),
        title: Text(context.tr('closingDetails')),
        subtitle: Text(_documentNumber),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: <Widget>[
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

  Widget _denominationRow(Denomination denomination) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DenominationRow(
        currency: _currency,
        denomination: denomination,
        quantity: _quantity(denomination),
        enabled: !_quantitiesLocked,
        onChanged: (value) => _setQuantity(denomination, value),
        onEdit: () => _editQuantity(denomination),
        step: _quickStep,
      ),
    );
  }

  int get _totalMinorUnits {
    var total = 0;
    for (final denomination in _currency.denominations) {
      total += denomination.minorUnits * _quantity(denomination);
    }
    return total;
  }

  int _quantity(Denomination denomination) => _quantities[denomination.id] ?? 0;

  void _setQuantity(Denomination denomination, int value) {
    if (_quantitiesLocked) {
      return;
    }
    HapticFeedback.selectionClick();
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
    if (_blindCount && !_quantitiesLocked) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('finishBlindBeforeSave'))),
      );
      return;
    }
    final app = AppScope.read(context);
    final session = CashCountSession(
      id: _sessionId,
      documentNumber: _documentNumber,
      currencyCode: _currencyCode,
      createdAt: _createdAt,
      updatedAt: DateTime.now(),
      quantities: _quantities,
      expectedMinorUnits: AppFormatters.parseMoneyToMinor(
        _expectedController.text,
        fractionDigits: _currency.fractionDigits,
      ),
      floatMinorUnits: AppFormatters.parseMoneyToMinor(
        _floatController.text,
        fractionDigits: _currency.fractionDigits,
      ),
      note: _noteController.text.trim(),
      closingTitle: _closingTitleController.text.trim(),
      businessName: _businessNameController.text.trim(),
      businessRegistrationId: _registrationIdController.text.trim(),
      businessAddress: _businessAddressController.text.trim(),
      locationName: _locationNameController.text.trim(),
      tillName: _tillNameController.text.trim(),
      cashierName: _cashierNameController.text.trim(),
      managerName: _managerNameController.text.trim(),
      shiftName: _shiftNameController.text.trim(),
      cashierSignaturePngBase64: _cashierSignaturePngBase64,
      managerSignaturePngBase64: _managerSignaturePngBase64,
      blindCount: _blindCount,
      blindCountLockedAt: _blindCountLockedAt,
      mode: _mode,
      customDenominations: _customDenominationSnapshots,
      posReport: _posReport,
    );
    final proofed = session.copyWith(
      closingHash: ClosingProofService.hashFor(session, _currency),
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
        ).showSnackBar(SnackBar(content: Text(context.tr('saveFailed'))));
        return;
      }
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.tr('saved'))));
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
      ).showSnackBar(SnackBar(content: Text(context.tr('saveFailed'))));
    }
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.icon,
    required this.onClear,
  });

  final String title;
  final IconData icon;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Icon(icon),
        const SizedBox(width: 8),
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        if (onClear != null)
          TextButton(onPressed: onClear, child: Text(context.tr('clear'))),
      ],
    );
  }
}
