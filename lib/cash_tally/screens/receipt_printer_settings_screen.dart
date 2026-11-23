import 'dart:io';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/receipt_printer_settings.dart';
import '../services/receipt_printer.dart';
import '../state/app_scope.dart';
import '../widgets/cash_keyboard.dart';

class ReceiptPrinterSettingsScreen extends StatefulWidget {
  const ReceiptPrinterSettingsScreen({super.key});

  @override
  State<ReceiptPrinterSettingsScreen> createState() =>
      _ReceiptPrinterSettingsScreenState();
}

class _ReceiptPrinterSettingsScreenState
    extends State<ReceiptPrinterSettingsScreen> {
  final _form = GlobalKey<FormState>();
  late final ReceiptPrinter _printer;
  late final TextEditingController _host;
  late final TextEditingController _port;
  late ReceiptConnection _connection;
  late ReceiptPaper _paper;
  late ReceiptEncoding _encoding;
  late ReceiptImageCommand _imageCommand;
  late ReceiptFeed _feed;
  late ReceiptCut _cut;
  ReceiptPrinterDevice? _device;
  ReceiptPrinterSettings? _verified;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    final app = AppScope.read(context);
    _printer = app.receiptPrinter;
    final saved = _printer.settings;
    _connection = saved?.connection ?? ReceiptConnection.network;
    _host = TextEditingController(
      text: _connection == ReceiptConnection.network ? saved?.address : '',
    );
    _port = TextEditingController(
      text: (saved?.port ?? ReceiptPrinter.defaultPort).toString(),
    );
    _paper = saved?.paper ?? ReceiptPaper.narrow;
    _imageCommand = saved?.imageCommand ?? ReceiptImageCommand.raster;
    _feed = saved?.feed ?? ReceiptFeed.standard;
    _cut = saved?.cut ?? ReceiptCut.partial;
    _encoding = saved?.encoding ??
        switch (app.locale.toLanguageTag()) {
          'zh-Hans' => ReceiptEncoding.gbk,
          'zh-Hant' => ReceiptEncoding.big5,
          _ => ReceiptEncoding.ascii,
        };
    if (saved != null && _connection != ReceiptConnection.network) {
      _device = ReceiptPrinterDevice(address: saved.address, name: saved.name);
    }
    _verified = saved;
  }

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    super.dispose();
  }

  ReceiptPrinterSettings get _draft => ReceiptPrinterSettings(
        connection: _connection,
        address: _connection == ReceiptConnection.network
            ? _host.text.trim()
            : _device?.address ?? '',
        port: _connection == ReceiptConnection.network
            ? int.tryParse(_port.text.trim()) ?? 0
            : ReceiptPrinter.defaultPort,
        paper: _paper,
        encoding: _encoding,
        imageCommand: _imageCommand,
        feed: _feed,
        cut: _cut,
        deviceName:
            _connection == ReceiptConnection.network ? '' : _device?.name ?? '',
      );

  String _proofFor(ReceiptPrinterSettings draft) =>
      _verified?.hasSameTextProfile(draft) == true
          ? _verified!.verifiedGlyphs
          : '';

  ReceiptPrinterSettings? _validatedSettings() {
    FocusManager.instance.primaryFocus?.unfocus();
    if (!_form.currentState!.validate()) return null;
    final draft = _draft;
    if (draft.address.isEmpty) {
      _message('receiptChooseDevice');
      return null;
    }
    return draft.withVerifiedGlyphs(_proofFor(draft));
  }

  @override
  Widget build(BuildContext context) {
    final proof = _proofFor(_draft);
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('receiptPrinter'))),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Form(
              key: _form,
              child: ListView(
                padding: const EdgeInsets.all(16),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                children: [
                  _dropdown(
                    label: 'receiptConnection',
                    value: _connection,
                    choices: ReceiptConnection.values,
                    itemLabel: (value) =>
                        context.tr('receiptConnection-${value.name}'),
                    onChanged: (value) => setState(() {
                      _connection = value;
                      _device = null;
                    }),
                  ),
                  const SizedBox(height: 16),
                  if (_connection == ReceiptConnection.network) ...[
                    TextFormField(
                      key: const ValueKey('receipt-printer-address'),
                      controller: _host,
                      enabled: !_working,
                      onTapOutside: dismissCashKeyboard,
                      keyboardType: TextInputType.url,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                          labelText: context.tr('receiptAddress')),
                      onChanged: (_) => setState(() {}),
                      validator: (value) {
                        final host = value?.trim() ?? '';
                        return InternetAddress.tryParse(host) != null ||
                                RegExp(r'^[a-zA-Z0-9_.-]+$').hasMatch(host)
                            ? null
                            : context.tr('receiptInvalidAddress');
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const ValueKey('receipt-printer-port'),
                      controller: _port,
                      enabled: !_working,
                      onTapOutside: dismissCashKeyboard,
                      keyboardType: TextInputType.number,
                      decoration:
                          InputDecoration(labelText: context.tr('receiptPort')),
                      onChanged: (_) => setState(() {}),
                      validator: (value) {
                        final port = int.tryParse(value?.trim() ?? '');
                        return port != null && port >= 1 && port <= 65535
                            ? null
                            : context.tr('receiptInvalidPort');
                      },
                    ),
                  ] else
                    OutlinedButton.icon(
                      onPressed: _working ? null : _selectDevice,
                      icon: Icon(_connection == ReceiptConnection.bluetooth
                          ? Icons.bluetooth
                          : Icons.usb),
                      label: Text(
                          _device?.name ?? context.tr('receiptChooseDevice')),
                    ),
                  const SizedBox(height: 16),
                  _dropdown(
                    label: 'receiptPaper',
                    value: _paper,
                    choices: ReceiptPaper.values,
                    itemLabel: (value) => context.tr('receiptPaperOption', {
                      'mm': value == ReceiptPaper.narrow ? 58 : 80,
                      'dots': value.dots,
                    }),
                    onChanged: (value) => setState(() => _paper = value),
                  ),
                  const SizedBox(height: 16),
                  _dropdown(
                    label: 'receiptImageCommand',
                    value: _imageCommand,
                    choices: ReceiptImageCommand.values,
                    itemLabel: (value) =>
                        context.tr('receiptImage-${value.name}'),
                    onChanged: (value) => setState(() => _imageCommand = value),
                  ),
                  const SizedBox(height: 16),
                  _dropdown(
                    label: 'receiptFeed',
                    value: _feed,
                    choices: ReceiptFeed.values,
                    itemLabel: (value) => context.tr('receiptFeedOption', {
                      'mm': value.millimeters,
                    }),
                    onChanged: (value) => setState(() => _feed = value),
                  ),
                  const SizedBox(height: 16),
                  _dropdown(
                    label: 'receiptCut',
                    help: 'receiptCutHelp',
                    value: _cut,
                    choices: ReceiptCut.values,
                    itemLabel: (value) =>
                        context.tr('receiptCut-${value.name}'),
                    onChanged: (value) => setState(() => _cut = value),
                  ),
                  const SizedBox(height: 16),
                  _dropdown(
                    label: 'receiptEncoding',
                    value: _encoding,
                    choices: ReceiptEncoding.values,
                    itemLabel: (value) =>
                        context.tr('receiptEncoding-${value.name}'),
                    onChanged: (value) => setState(() => _encoding = value),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.tr(proof.isEmpty
                        ? 'receiptFontUnverified'
                        : 'receiptFontVerified'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      OutlinedButton.icon(
                        key: const ValueKey('receipt-test-font'),
                        onPressed: _working ? null : _testFont,
                        icon: const Icon(Icons.receipt_long_outlined),
                        label: Text(context.tr('receiptTestFont')),
                      ),
                      OutlinedButton.icon(
                        onPressed: _working ? null : _testFeed,
                        icon: const Icon(Icons.content_cut),
                        label: Text(context.tr('receiptTestFeed')),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    key: const ValueKey('receipt-save-printer'),
                    onPressed: _working ? null : _save,
                    icon: const Icon(Icons.check),
                    label: Text(context.tr('save')),
                  ),
                  if (_working) ...[
                    const SizedBox(height: 12),
                    const LinearProgressIndicator(),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _dropdown<T extends Enum>({
    required String label,
    required T value,
    required List<T> choices,
    required String Function(T) itemLabel,
    required ValueChanged<T> onChanged,
    String? help,
  }) =>
      DropdownButtonFormField<T>(
        value: value,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: context.tr(label),
          helperText: help == null ? null : context.tr(help),
          helperMaxLines: 3,
        ),
        items: [
          for (final option in choices)
            DropdownMenuItem(
              value: option,
              child: Text(itemLabel(option), overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: _working
            ? null
            : (selected) {
                if (selected != null) onChanged(selected);
              },
      );

  Future<void> _selectDevice() async {
    if (_working) return;
    setState(() => _working = true);
    try {
      final devices = await _printer.devices(_connection);
      if (!mounted) return;
      if (devices.isEmpty) {
        _message(_connection == ReceiptConnection.bluetooth
            ? 'receiptNoPairedPrinters'
            : 'receiptNoUsbPrinters');
        return;
      }
      final device = await showDialog<ReceiptPrinterDevice>(
        context: context,
        builder: (context) => SimpleDialog(
          title: Text(context.tr('receiptChooseDevice')),
          children: [
            for (final device in devices)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, device),
                child: Text(device.name),
              ),
          ],
        ),
      );
      if (mounted && device != null) setState(() => _device = device);
    } on ReceiptPrinterException catch (error) {
      _message('receiptError-${error.code}');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _testFont() async {
    if (_working) return;
    final draft = _validatedSettings();
    if (draft == null) return;
    setState(() => _working = true);
    try {
      final sample = await _printer.printFontTest(draft);
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.tr('receiptConfirmFont')),
          scrollable: true,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(context.tr('receiptCompareSample')),
              const SizedBox(height: 12),
              SelectableText(sample,
                  style: const TextStyle(fontFamily: 'monospace')),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.tr('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(context.tr('receiptFontMatches')),
            ),
          ],
        ),
      );
      if (mounted) {
        setState(() => _verified =
            confirmed == true ? draft.withVerifiedGlyphs(sample) : null);
      }
    } on ReceiptPrinterException catch (error) {
      _message('receiptError-${error.code}');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _testFeed() async {
    if (_working) return;
    final draft = _validatedSettings();
    if (draft == null) return;
    setState(() => _working = true);
    try {
      await _printer.testPaperFeed(draft);
      _message('receiptFeedSent');
    } on ReceiptPrinterException catch (error) {
      _message('receiptError-${error.code}');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _save() async {
    if (_working) return;
    final draft = _validatedSettings();
    if (draft == null) return;
    setState(() => _working = true);
    try {
      await _printer.saveSettings(draft);
      if (mounted) Navigator.pop(context, true);
    } on ReceiptPrinterException catch (error) {
      _message('receiptError-${error.code}');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  void _message(String key) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr(key))),
      );
    }
  }
}
