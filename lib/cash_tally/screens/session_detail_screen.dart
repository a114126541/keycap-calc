import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../core/formatters.dart';
import '../data/currency_catalog.dart';
import '../l10n/app_localizations.dart';
import '../models/cash_count_session.dart';
import '../models/count_mode.dart';
import '../models/currency_definition.dart';
import '../services/closing_proof_service.dart';
import '../services/receipt_printer.dart';
import '../state/app_scope.dart';
import '../widgets/cash_panels.dart';
import '../widgets/receipt_print_button.dart';
import 'count_screen.dart';
import 'report_preview_screen.dart';

class CashSessionDetail extends StatefulWidget {
  const CashSessionDetail({
    required this.session,
    required this.onDeleted,
    this.showHeading = false,
    super.key,
  });

  final CashCountSession session;
  final VoidCallback onDeleted;
  final bool showHeading;

  @override
  State<CashSessionDetail> createState() => _CashSessionDetailState();
}

class _CashSessionDetailState extends State<CashSessionDetail> {
  final _scroll = ScrollController();

  CashCountSession get _session => widget.session;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currency =
        _session.currencyFor(CurrencyCatalog.byCode(_session.currencyCode));
    final locale = Localizations.localeOf(context).toLanguageTag();
    final used = currency.denominations
        .where((item) => _session.quantityFor(item) > 0)
        .toList()
      ..sort((a, b) => b.minorUnits.compareTo(a.minorUnits));

    return CashPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.showHeading)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 14, end: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(context.tr('cashRecordDetails'),
                        style: theme.textTheme.titleLarge),
                  ),
                  SessionDetailMenu(
                      session: _session, onDeleted: widget.onDeleted),
                ],
              ),
            ),
          Expanded(
            child: Scrollbar(
              controller: _scroll,
              child: ListView(
                key: PageStorageKey('cash-record-details-${_session.id}'),
                controller: _scroll,
                padding: EdgeInsets.fromLTRB(
                    12, widget.showHeading ? 0 : 12, 12, 24),
                children: [
                  _amountHeader(currency, locale),
                  CashSummaryRows(
                      currency: currency, quantityFor: _session.quantityFor),
                  if (_session.note.trim().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    _note(),
                  ],
                  const SizedBox(height: 10),
                  Text(context.tr('cashBreakdown'),
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  if (used.isEmpty)
                    Text(context.tr('noDenominations'))
                  else
                    _denominations(currency, used, locale),
                  ..._additionalDetails(currency, locale),
                ],
              ),
            ),
          ),
          CashActionBar(
            primary: FilledButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ReportPreviewScreen(session: _session),
                ),
              ),
              icon: const Icon(LucideIcons.fileText),
              label: Text(context.tr('openReport')),
            ),
            secondary: ReceiptPrinter.isSupported
                ? ReceiptPrintButton(
                    currency: currency, quantityFor: _session.quantityFor)
                : null,
          ),
        ],
      ),
    );
  }

  Widget _amountHeader(CurrencyDefinition currency, String locale) {
    final formatted = currency.formatMinor(
      _session.totalMinorUnits(currency),
      localeCode: locale,
      fixedFractionDigits: true,
    );
    final mode = context.tr(
        _session.mode == CountMode.quick ? 'quickCount' : 'professionalClose');
    const metadataStyle = TextStyle(fontSize: 13, height: 1.25);
    return CashAmountHighlight(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: IntrinsicHeight(
        child: Row(
          children: [
            Expanded(
              flex: 6,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(context.tr('actualInTill'),
                      style: const TextStyle(fontSize: 15, height: 1.2)),
                  const SizedBox(height: 2),
                  CashAmountText(
                    formatted,
                    alignment: AlignmentDirectional.centerStart,
                    style: const TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w700,
                        height: 1.15),
                  ),
                ],
              ),
            ),
            VerticalDivider(
              width: 18,
              indent: 2,
              endIndent: 2,
              color: DefaultTextStyle.of(context)
                  .style
                  .color
                  ?.withValues(alpha: 0.35),
            ),
            Expanded(
              flex: 5,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('$mode · ${_session.currencyCode}',
                      style: metadataStyle),
                  const SizedBox(height: 3),
                  Text(
                      AppFormatters.dateTime(_session.updatedAt,
                          localeCode: locale),
                      style: metadataStyle),
                  const SizedBox(height: 3),
                  Text(
                      '${context.tr('documentNumber')} ${_session.documentNumber}',
                      style: metadataStyle),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _note() => CashPanel(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(LucideIcons.clipboardList, size: 19),
              const SizedBox(width: 8),
              Text(context.tr('note')),
              const SizedBox(width: 12),
              Expanded(child: Text(_session.note)),
            ],
          ),
        ),
      );

  Widget _denominations(
      CurrencyDefinition currency, List<Denomination> used, String locale) {
    final theme = Theme.of(context);
    final seenLabels = <String>{};
    final duplicateLabels = {
      for (final item in used)
        if (!seenLabels.add(item.label)) item.label,
    };
    Widget line(Widget label, Widget quantity, Widget subtotal) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
          child: Row(
            children: [
              Expanded(flex: 4, child: label),
              Expanded(
                  flex: 3,
                  child: Align(alignment: Alignment.center, child: quantity)),
              Expanded(
                  flex: 4,
                  child: Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: subtotal)),
            ],
          ),
        );

    return Column(
      children: [
        line(
          Text(context.tr('denomination'), style: theme.textTheme.labelLarge),
          Text(context.tr('quantity'), style: theme.textTheme.labelLarge),
          Text(context.tr('subtotal'), style: theme.textTheme.labelLarge),
        ),
        const Divider(height: 1),
        for (final item in used) ...[
          line(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.label, style: theme.textTheme.titleMedium),
                if (duplicateLabels.contains(item.label))
                  Text(
                    context.tr(item.isBanknote ? 'banknotes' : 'coins'),
                    style: theme.textTheme.bodySmall,
                  ),
                if (item.calculationWeightMilligrams != null)
                  Text(
                    AppFormatters.weight(
                      item.calculationWeightMilligrams,
                      localeCode: locale,
                      approximate: item.weightIsApproximate,
                      unavailableLabel: context.tr('weightUnavailable'),
                    ),
                    style: theme.textTheme.bodySmall,
                  ),
              ],
            ),
            CashAmountText(
              '${_session.quantityFor(item)}',
              alignment: AlignmentDirectional.center,
              style: theme.textTheme.titleMedium,
            ),
            CashAmountText(
              currency.formatMinor(item.minorUnits * _session.quantityFor(item),
                  localeCode: locale),
              style: theme.textTheme.titleMedium,
            ),
          ),
          const Divider(height: 1),
        ],
      ],
    );
  }

  List<Widget> _additionalDetails(CurrencyDefinition currency, String locale) {
    final theme = Theme.of(context);
    final difference = _session.differenceMinorUnits(currency);
    final deposit = _session.depositMinorUnits(currency);
    String money(int amount) => currency.formatMinor(amount,
        localeCode: locale, fixedFractionDigits: true);
    final showCashCheck = _session.mode == CountMode.professional ||
        _session.expectedMinorUnits != null ||
        _session.floatMinorUnits != null;
    return [
      if (showCashCheck) ...[
        const SizedBox(height: 18),
        Text(context.tr('cashCheck'), style: theme.textTheme.titleLarge),
        const SizedBox(height: 6),
        if (_session.blindCount)
          Text(context.tr(_session.quantitiesAreLocked
              ? 'blindCountLocked'
              : 'blindCountHelp')),
        if (_session.expectedMinorUnits case final expected?)
          _SummaryRow(
              label: context.tr('cashExpectedAmount'), value: money(expected)),
        if (_session.floatMinorUnits case final retained?)
          _SummaryRow(
              label: context.tr('cashRetainedFloat'), value: money(retained)),
        if (difference != null)
          _SummaryRow(
            label: context.tr('difference'),
            value: money(difference),
            emphasized: true,
            negative: difference < 0,
          ),
        if (deposit != null)
          _SummaryRow(
            label: context.tr('deposit'),
            value: money(deposit < 0 ? 0 : deposit),
            emphasized: true,
          ),
      ],
      const SizedBox(height: 12),
      if (_session.closingTitle.trim().isNotEmpty)
        Text(_session.closingTitle.trim(), style: theme.textTheme.titleLarge),
      if (_session.hasBusinessIdentity)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(
            '${context.tr('closingIdentitySentence')} · ${_identitySentence(_session)}',
            style: theme.textTheme.bodySmall,
          ),
        ),
      _ProofCard(session: _session, currency: currency),
      if (_session.posReport != null)
        _PosReportCard(session: _session, currency: currency),
      if (_session.cashierSignaturePngBase64 != null ||
          _session.managerSignaturePngBase64 != null) ...[
        const SizedBox(height: 18),
        Text(context.tr('signatures'), style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _SignaturePreview(
                label: context.tr('cashierSignature'),
                encodedPng: _session.cashierSignaturePngBase64,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _SignaturePreview(
                label: context.tr('managerSignature'),
                encodedPng: _session.managerSignaturePngBase64,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(context.tr('signatureGraphicNotice'),
            style: theme.textTheme.bodySmall),
      ],
    ];
  }
}

enum _RecordAction { edit, delete }

class SessionDetailMenu extends StatelessWidget {
  const SessionDetailMenu(
      {required this.session, required this.onDeleted, super.key});

  final CashCountSession session;
  final VoidCallback onDeleted;

  @override
  Widget build(BuildContext context) => PopupMenuButton<_RecordAction>(
        key: const ValueKey('cash-record-actions'),
        icon: const Icon(LucideIcons.moreVertical),
        itemBuilder: (_) => [
          PopupMenuItem(
              value: _RecordAction.edit, child: Text(context.tr('edit'))),
          PopupMenuItem(
              value: _RecordAction.delete, child: Text(context.tr('delete'))),
        ],
        onSelected: (action) {
          if (action == _RecordAction.edit) {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                  builder: (_) => CountScreen(existingSession: session)),
            );
          } else {
            _delete(context);
          }
        },
      );

  Future<void> _delete(BuildContext context) async {
    final controller = AppScope.read(context);
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.tr('deleteTitle')),
        content: Text(context.tr('deleteBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.tr('keep')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.tr('delete')),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final deleted = context.tr('deleted');
    final failed = context.tr('deleteFailed');
    try {
      await controller.deleteSession(session.id);
      onDeleted();
      if (messenger.mounted) {
        messenger.showSnackBar(SnackBar(content: Text(deleted)));
      }
    } on Object {
      if (messenger.mounted) {
        messenger.showSnackBar(SnackBar(content: Text(failed)));
      }
    }
  }
}

String _identitySentence(CashCountSession session) => <String>[
      session.businessName,
      session.businessRegistrationId,
      session.businessAddress,
      session.locationName,
      session.tillName,
      session.shiftName,
      session.cashierName,
      session.managerName,
    ]
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .join(' · ');

class _ProofCard extends StatelessWidget {
  const _ProofCard({required this.session, required this.currency});

  final CashCountSession session;
  final CurrencyDefinition currency;

  @override
  Widget build(BuildContext context) {
    final hash = ClosingProofService.hashFor(session, currency);
    return Card(
      child: ListTile(
        leading: const Icon(Icons.verified_outlined),
        title: Text(context.tr('proofHash')),
        subtitle: SelectableText(hash),
        isThreeLine: true,
      ),
    );
  }
}

class _PosReportCard extends StatelessWidget {
  const _PosReportCard({required this.session, required this.currency});

  final CashCountSession session;
  final CurrencyDefinition currency;

  @override
  Widget build(BuildContext context) {
    final report = session.posReport!;
    final localeCode = Localizations.localeOf(context).toLanguageTag();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              context.tr('posReconciliation'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text('${context.tr('posReportId')}: ${report.id}'),
            Text('${context.tr('posSource')}: ${report.sourceFileName}'),
            Text(
              '${context.tr('posExpectedCash')}: '
              '${currency.formatMinor(report.expectedCashMinorUnits ?? 0, localeCode: localeCode)}',
            ),
            if (report.cardMinorUnits != null)
              Text(
                '${context.tr('posCardTotal')}: '
                '${currency.formatMinor(report.cardMinorUnits!, localeCode: localeCode)}',
              ),
            if (report.totalSalesMinorUnits != null)
              Text(
                '${context.tr('posTotalSales')}: '
                '${currency.formatMinor(report.totalSalesMinorUnits!, localeCode: localeCode)}',
              ),
            const SizedBox(height: 4),
            SelectableText(
              '${context.tr('posSourceHash')}: ${report.sourceSha256}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _SignaturePreview extends StatelessWidget {
  const _SignaturePreview({required this.label, required this.encodedPng});

  final String label;
  final String? encodedPng;

  @override
  Widget build(BuildContext context) {
    Widget image = Center(child: Text(context.tr('signatureMissing')));
    try {
      final bytes = encodedPng == null ? null : base64Decode(encodedPng!);
      if (bytes != null && bytes.isNotEmpty) {
        image = Image.memory(bytes, fit: BoxFit.contain);
      }
    } on FormatException {
      // The saved record remains visible even if an old signature is malformed.
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(label, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 6),
            SizedBox(height: 88, width: double.infinity, child: image),
          ],
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    this.emphasized = false,
    this.negative = false,
  });

  final String label;
  final String value;
  final bool emphasized;
  final bool negative;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: <Widget>[
            Expanded(child: Text(label)),
            Text(
              value,
              style: emphasized
                  ? Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: negative
                            ? Theme.of(context).colorScheme.error
                            : null,
                      )
                  : Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: negative
                            ? Theme.of(context).colorScheme.error
                            : null,
                      ),
            ),
          ],
        ),
      ),
    );
  }
}
