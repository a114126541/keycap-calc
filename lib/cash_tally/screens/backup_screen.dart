import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';

import '../l10n/app_localizations.dart';
import '../services/backup_service.dart';
import '../state/app_scope.dart';
import '../widgets/cash_keyboard.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  final _service = BackupService();
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('backupAndRestore'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    context.tr('encryptedBackup'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(context.tr('encryptedBackupHelp')),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _busy ? null : _export,
                    icon: const Icon(Icons.save_alt),
                    label: Text(context.tr('exportBackup')),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    context.tr('restoreBackup'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(context.tr('restoreBackupHelp')),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _import,
                    icon: const Icon(Icons.settings_backup_restore),
                    label: Text(context.tr('importBackup')),
                  ),
                ],
              ),
            ),
          ),
          if (_busy) ...<Widget>[
            const SizedBox(height: 24),
            const Center(child: CircularProgressIndicator()),
          ],
        ],
      ),
    );
  }

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      final password = await _askPassword(confirm: true);
      if (password == null || !mounted) return;

      final app = AppScope.read(context);
      final bytes = await _service.encrypt(
        bundle: await app.exportBackupData(),
        password: password,
      );
      if (!mounted) return;
      final date = DateTime.now().toIso8601String().split('T').first;
      final path = await FlutterFileDialog.saveFile(
        params: SaveFileDialogParams(
          data: bytes,
          fileName: 'Keycap-Calc-$date.vycbak',
          mimeTypesFilter: const ['application/octet-stream'],
        ),
      );
      if (path != null) _message('backupSaved');
    } on Object {
      _message('backupFailed');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    setState(() => _busy = true);
    try {
      final path = await FlutterFileDialog.pickFile(
        params: const OpenFileDialogParams(
          fileExtensionsFilter: ['vycbak'],
          mimeTypesFilter: ['application/octet-stream'],
          copyFileToCacheDir: true,
        ),
      );
      if (path == null || !mounted) return;

      final password = await _askPassword();
      if (password == null || !mounted) return;

      final BackupBundle bundle;
      try {
        final file = File(path);
        if (await file.length() > BackupService.maxFileBytes) {
          throw const FormatException('Backup file is too large');
        }
        bundle = await _service.decrypt(
          bytes: await file.readAsBytes(),
          password: password,
        );
      } on Object {
        _message('backupPasswordOrFileInvalid');
        return;
      }
      if (!mounted) return;
      await AppScope.read(context).restoreBackup(bundle);
      _message('backupImported');
    } on Object {
      _message('backupRestoreFailed');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _askPassword({bool confirm = false}) => showDialog<String>(
        context: context,
        builder: (_) => _BackupPasswordDialog(confirm: confirm),
      );

  void _message(String key) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.tr(key))),
    );
  }
}

class _BackupPasswordDialog extends StatefulWidget {
  const _BackupPasswordDialog({required this.confirm});

  final bool confirm;

  @override
  State<_BackupPasswordDialog> createState() => _BackupPasswordDialogState();
}

class _BackupPasswordDialogState extends State<_BackupPasswordDialog> {
  final _password = TextEditingController();
  final _repeated = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _repeated.dispose();
    super.dispose();
  }

  void _submit() {
    if (_password.text.length < 8) {
      setState(() => _error = 'passwordTooShort');
      return;
    }
    if (widget.confirm && _password.text != _repeated.text) {
      setState(() => _error = 'passwordsDoNotMatch');
      return;
    }
    Navigator.of(context).pop(_password.text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: Text(context.tr('backupPassword')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _password,
            onTapOutside: dismissCashKeyboard,
            autofocus: true,
            obscureText: true,
            textInputAction:
                widget.confirm ? TextInputAction.next : TextInputAction.done,
            onSubmitted: widget.confirm ? null : (_) => _submit(),
            decoration: InputDecoration(
              labelText: context.tr('password'),
              helperText: context.tr('backupPasswordHelp'),
              errorText: _error == null ? null : context.tr(_error!),
            ),
          ),
          if (widget.confirm) ...[
            const SizedBox(height: 10),
            TextField(
              controller: _repeated,
              onTapOutside: dismissCashKeyboard,
              obscureText: true,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: context.tr('repeatPassword'),
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.tr('cancel')),
        ),
        FilledButton(onPressed: _submit, child: Text(context.tr('confirm'))),
      ],
    );
  }
}
