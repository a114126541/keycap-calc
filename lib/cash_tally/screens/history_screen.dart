import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../data/currency_catalog.dart';
import '../l10n/app_localizations.dart';
import '../models/cash_count_session.dart';
import '../models/count_mode.dart';
import '../state/app_scope.dart';
import '../widgets/cash_keyboard.dart';
import '../widgets/cash_panels.dart';
import 'session_detail_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

typedef _HistoryEntry = ({DateTime day, CashCountSession? session});

class _HistoryScreenState extends State<HistoryScreen> {
  final _searchController = TextEditingController();
  final _scroll = ScrollController();
  String? _currencyCode;
  bool _differencesOnly = false;
  DateTimeRange? _dateRange;
  String? _selectedId;
  bool _showDetail = false;

  @override
  void initState() {
    super.initState();
    AppScope.read(context).loadHistory();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sessions = app.sessions;
    final matches = sessions.where(_matches).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final codes = sessions.map((item) => item.currencyCode).toSet().toList()
      ..sort();
    final selected =
        sessions.where((item) => item.id == _selectedId).firstOrNull;
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth =
            constraints.maxWidth - MediaQuery.paddingOf(context).horizontal;
        final split =
            MediaQuery.orientationOf(context) == Orientation.landscape &&
                availableWidth >= cashSplitWidth;
        final width =
            math.min(availableWidth, split ? cashWorkspaceWidth : 680.0);
        final visibleSelection =
            matches.where((item) => item.id == _selectedId).firstOrNull ??
                matches.firstOrNull;
        final detail = split ? visibleSelection : selected;
        final showPortraitDetail = !split && _showDetail && detail != null;
        final detailPanel = detail == null
            ? null
            : CashSessionDetail(
                key: ValueKey('cash-session-${detail.id}'),
                session: detail,
                showHeading: split,
                onDeleted: () => _onDeleted(detail.id),
              );
        final records = _recordList(
          matches: matches,
          codes: codes,
          activeId: split ? visibleSelection?.id : _selectedId,
          loading: app.historyLoading,
          unavailable: app.historyUnavailable,
          empty: sessions.isEmpty,
        );

        return PopScope(
          canPop: !showPortraitDetail,
          onPopInvokedWithResult: (popped, _) {
            if (!popped && showPortraitDetail) _closeDetail();
          },
          child: Scaffold(
            appBar: AppBar(
              backgroundColor: Theme.of(context).scaffoldBackgroundColor,
              scrolledUnderElevation: 0,
              toolbarHeight: 48,
              leading: showPortraitDetail
                  ? BackButton(onPressed: _closeDetail)
                  : null,
              title: split
                  ? SizedBox(
                      width: width * 0.43 - 56,
                      child: Row(
                        children: [
                          Expanded(child: Text(context.tr('cashTallyHistory'))),
                          _filterAction(),
                        ],
                      ),
                    )
                  : Text(context.tr(showPortraitDetail
                      ? 'cashRecordDetails'
                      : 'cashTallyHistory')),
              actions: showPortraitDetail
                  ? [
                      SessionDetailMenu(
                          session: detail,
                          onDeleted: () => _onDeleted(detail.id))
                    ]
                  : split
                      ? null
                      : [_filterAction()],
            ),
            body: SafeArea(
              top: false,
              child: Center(
                child: SizedBox(
                  width: width,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
                    child: split
                        ? Row(
                            key: const ValueKey('cash-history-two-panes'),
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(flex: 43, child: records),
                              const SizedBox(width: 10),
                              Expanded(
                                flex: 57,
                                child: detailPanel ??
                                    const CashPanel(child: SizedBox.expand()),
                              ),
                            ],
                          )
                        : showPortraitDetail
                            ? detailPanel!
                            : records,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _filterAction() => IconButton(
        tooltip:
            context.tr(_hasFilters ? 'clearFilters' : 'cashHistoryFilters'),
        icon: Icon(_hasFilters ? LucideIcons.filterX : LucideIcons.filter),
        onPressed: _hasFilters ? _clearFilters : _scrollToFilters,
      );

  void _scrollToFilters() {
    if (_scroll.hasClients) {
      _scroll.animateTo(0,
          duration: const Duration(milliseconds: 180), curve: Curves.easeOut);
    }
  }

  Widget _recordList({
    required List<CashCountSession> matches,
    required List<String> codes,
    required String? activeId,
    required bool loading,
    required bool unavailable,
    required bool empty,
  }) {
    final entries = <_HistoryEntry>[];
    DateTime? previousDay;
    for (final item in matches) {
      final day = DateUtils.dateOnly(item.updatedAt.toLocal());
      if (day != previousDay) {
        entries.add((day: day, session: null));
        previousDay = day;
      }
      entries.add((day: day, session: item));
    }
    return CashPanel(
      child: Scrollbar(
        controller: _scroll,
        child: ListView.builder(
          key: const PageStorageKey('cash-record-list'),
          controller: _scroll,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.all(12),
          itemCount: entries.length + (entries.isEmpty ? 2 : 1),
          itemBuilder: (context, index) {
            if (index == 0) return _filters(codes);
            if (entries.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 28),
                child: Center(
                  child: loading
                      ? const CircularProgressIndicator()
                      : Text(
                          context.tr(unavailable
                              ? 'cashHistoryUnavailable'
                              : empty
                                  ? 'historyEmpty'
                                  : 'noHistoryMatches'),
                          textAlign: TextAlign.center,
                        ),
                ),
              );
            }
            final entry = entries[index - 1];
            if (entry.session case final item?) {
              return _recordRow(item, selected: item.id == activeId);
            }
            final material = MaterialLocalizations.of(context);
            final day = entry.day;
            return Padding(
              padding: const EdgeInsets.fromLTRB(3, 13, 3, 7),
              child: Text(
                day.year == DateTime.now().year
                    ? material.formatShortMonthDay(day)
                    : material.formatShortDate(day),
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _filters(List<String> codes) {
    final theme = Theme.of(context);
    final shape =
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(9));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const ValueKey('cash-history-search'),
          onTapOutside: dismissCashKeyboard,
          controller: _searchController,
          decoration: InputDecoration(
            hintText: context.tr('searchHistory'),
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            prefixIcon: const Icon(LucideIcons.search, size: 20),
            suffixIcon: _searchController.text.isEmpty
                ? null
                : IconButton(
                    onPressed: () {
                      _searchController.clear();
                      setState(() {});
                    },
                    icon: const Icon(LucideIcons.x, size: 19),
                  ),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            PopupMenuButton<String>(
              key: const ValueKey('cash-history-currency'),
              tooltip: context.tr('currency'),
              position: PopupMenuPosition.under,
              onSelected: (value) =>
                  setState(() => _currencyCode = value.isEmpty ? null : value),
              itemBuilder: (_) => [
                CheckedPopupMenuItem(
                  value: '',
                  checked: _currencyCode == null,
                  child: Text(context.tr('allCurrencies')),
                ),
                for (final code in codes)
                  CheckedPopupMenuItem(
                      value: code,
                      checked: _currencyCode == code,
                      child: Text(code)),
              ],
              child: Container(
                constraints: const BoxConstraints(minHeight: 44),
                decoration: ShapeDecoration(
                  shape: shape.copyWith(
                      side:
                          BorderSide(color: theme.colorScheme.outlineVariant)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 9),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(_currencyCode ?? context.tr('allCurrencies'),
                          style: theme.textTheme.labelMedium),
                    ),
                    const SizedBox(width: 4),
                    const Icon(LucideIcons.chevronDown, size: 15),
                  ],
                ),
              ),
            ),
            OutlinedButton.icon(
              key: const ValueKey('cash-history-date'),
              onPressed: _pickDateRange,
              icon: const Icon(LucideIcons.calendarDays, size: 16),
              label: Text(
                context
                    .tr(_dateRange == null ? 'dateRange' : 'dateRangeActive'),
                style: theme.textTheme.labelMedium,
              ),
              style: OutlinedButton.styleFrom(
                shape: shape,
                side: BorderSide(color: theme.colorScheme.outlineVariant),
                minimumSize: const Size(0, 44),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                foregroundColor: theme.colorScheme.onSurface,
              ),
            ),
            InkWell(
              key: const ValueKey('cash-history-differences'),
              borderRadius: BorderRadius.circular(8),
              onTap: () => setState(() => _differencesOnly = !_differencesOnly),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Checkbox(
                    visualDensity: VisualDensity.compact,
                    value: _differencesOnly,
                    onChanged: (value) =>
                        setState(() => _differencesOnly = value ?? false),
                  ),
                  Flexible(
                    child: Text(context.tr('differencesOnly'),
                        style: theme.textTheme.labelMedium),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _recordRow(CashCountSession session, {required bool selected}) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final currency =
        session.currencyFor(CurrencyCatalog.byCode(session.currencyCode));
    final locale = Localizations.localeOf(context).toLanguageTag();
    final total = currency.formatMinor(session.totalMinorUnits(currency),
        localeCode: locale, fixedFractionDigits: true);
    final difference = session.differenceMinorUnits(currency);
    final time = MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(session.updatedAt.toLocal()),
      alwaysUse24HourFormat: true,
    );
    final metadata = [
      time,
      session.currencyCode,
      if (session.tillName.trim().isNotEmpty) session.tillName.trim(),
    ].join(' · ');
    final ink = selected ? colors.onPrimaryContainer : colors.onSurface;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: selected ? colors.primaryContainer : Colors.transparent,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
              color: selected
                  ? colors.primary.withValues(alpha: 0.48)
                  : colors.outlineVariant),
        ),
        child: InkWell(
          key: ValueKey('cash-record-${session.id}'),
          onTap: () {
            FocusManager.instance.primaryFocus?.unfocus();
            setState(() {
              _selectedId = session.id;
              _showDetail = true;
            });
          },
          child: Semantics(
            selected: selected,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(11, 10, 8, 10),
              child: Row(
                children: [
                  Expanded(
                    flex: 6,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.tr(session.mode == CountMode.quick
                              ? 'quickCount'
                              : 'professionalClose'),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                              color: ink, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          metadata,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: selected ? ink : colors.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    flex: 4,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        CashAmountText(total,
                            style: theme.textTheme.titleMedium?.copyWith(
                                color: ink, fontWeight: FontWeight.w700)),
                        if (difference != null && difference != 0)
                          CashAmountText(
                            '${context.tr('difference')} ${currency.formatMinor(difference, localeCode: locale, fixedFractionDigits: true)}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: difference < 0 ? colors.error : ink,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 5),
                  Icon(LucideIcons.chevronRight, size: 18, color: ink),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _closeDetail() => setState(() => _showDetail = false);

  void _onDeleted(String id) {
    if (!mounted || _selectedId != id) return;
    setState(() {
      _selectedId = null;
      _showDetail = false;
    });
  }

  bool get _hasFilters =>
      _searchController.text.isNotEmpty ||
      _currencyCode != null ||
      _differencesOnly ||
      _dateRange != null;

  bool _matches(CashCountSession session) {
    if (_currencyCode != null && session.currencyCode != _currencyCode) {
      return false;
    }
    final date = DateUtils.dateOnly(session.updatedAt.toLocal());
    if (_dateRange case final range?) {
      if (date.isBefore(range.start) || date.isAfter(range.end)) return false;
    }
    if (_differencesOnly) {
      final currency =
          session.currencyFor(CurrencyCatalog.byCode(session.currencyCode));
      if ((session.differenceMinorUnits(currency) ?? 0) == 0) return false;
    }
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return true;
    return [
      session.documentNumber,
      session.currencyCode,
      session.businessName,
      session.locationName,
      session.tillName,
      session.cashierName,
      session.managerName,
      session.shiftName,
      session.note,
      session.posReport?.id ?? '',
      session.posReport?.sourceFileName ?? '',
      session.posReport?.tillName ?? '',
      session.posReport?.cashierName ?? '',
    ].any((value) => value.toLowerCase().contains(query));
  }

  Future<void> _pickDateRange() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final now = DateTime.now();
    final selected = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 1),
      initialDateRange: _dateRange,
    );
    if (selected != null && mounted) {
      setState(() => _dateRange = selected);
    }
  }

  void _clearFilters() {
    _searchController.clear();
    setState(() {
      _currencyCode = null;
      _differencesOnly = false;
      _dateRange = null;
    });
    _scrollToFilters();
  }
}
