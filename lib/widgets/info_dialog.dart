import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:neumorphic_calculator/cash_tally/l10n/app_localizations.dart';
import 'package:neumorphic_calculator/cash_tally/services/receipt_printer.dart';
import 'package:neumorphic_calculator/screens/settings_screen/settings_controller.dart';
import 'package:neumorphic_calculator/utils/const.dart';
import 'package:neumorphic_calculator/utils/extensions/widget_extension.dart';
import 'package:neumorphic_calculator/widgets/confirm_dialog.dart';
import 'package:url_launcher/url_launcher.dart';

class InfoDialog extends StatefulWidget {
  const InfoDialog({super.key});

  @override
  State<InfoDialog> createState() => _InfoDialogState();
}

class _InfoDialogState extends State<InfoDialog> {
  Timer? _versionTapTimer;
  int _versionTapCount = 0;

  void _resetVersionTaps() {
    _versionTapTimer?.cancel();
    _versionTapTimer = null;
    _versionTapCount = 0;
  }

  void _onVersionTap() {
    if (ModalRoute.of(context)?.isCurrent != true) return;

    _versionTapTimer ??= Timer(const Duration(seconds: 3), _resetVersionTaps);
    _versionTapCount++;
    if (_versionTapCount < 5) return;

    _resetVersionTaps();
    ConfirmDialog(
      title: Text(context.tr('keycapExitTitle')),
      content: context.tr('keycapExitConfirm'),
      confirmText: context.tr('keycapExit'),
      onConfirm: SystemNavigator.pop,
    ).show(context);
  }

  @override
  void dispose() {
    _versionTapTimer?.cancel();
    super.dispose();
  }

  Future<void> _openGitHub(String link) async {
    try {
      await launchUrl(Uri.parse(link));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final version = SettingsController.instance.packageInfo.version;
    return AlertDialog(
      scrollable: true,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      backgroundColor: Color.lerp(
        theme.scaffoldBackgroundColor,
        colors.surfaceContainerLowest,
        0.6,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: colors.outlineVariant),
      ),
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
      title: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.asset(
              'assets/icons/icon.png',
              width: 56,
              height: 56,
              excludeFromSemantics: true,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: theme.platform == TargetPlatform.android
                  ? _onVersionTap
                  : null,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    AppConst.appName,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: colors.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    context.tr('keycapAboutVersion', {'version': version}),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 24),
      content: SizedBox(
        width: 360,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Divider(height: 1),
            _AboutFeature(
              icon: LucideIcons.calculator,
              title: context.tr('keycapCalculator'),
              description: context.tr('keycapAboutCalculatorDescription'),
            ),
            _AboutFeature(
              icon: LucideIcons.banknote,
              title: context.tr('cashTally'),
              description: context.tr('keycapAboutCashDescription'),
            ),
            if (ReceiptPrinter.isSupported)
              _AboutFeature(
                icon: LucideIcons.printer,
                title: context.tr('keycapAboutPrinting'),
                description: context.tr('keycapAboutPrintingDescription'),
              ),
            const Divider(height: 1),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                style: TextButton.styleFrom(padding: EdgeInsets.zero),
                onPressed: () => _openGitHub(AppConst.developerGithubLink),
                child: Text(
                  context
                      .tr('keycapDeveloper', {'name': AppConst.developerName}),
                ),
              ),
            ),
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
      actions: [
        TextButton.icon(
          onPressed: () => _openGitHub(AppConst.projectGithubLink),
          icon: const Icon(LucideIcons.github, size: 18),
          label: const Text('GitHub'),
        ),
        TextButton(
          onPressed: () => showLicensePage(context: context),
          child: Text(context.tr('keycapLicenses')),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.tr('close')),
        ),
      ],
    );
  }
}

class _AboutFeature extends StatelessWidget {
  const _AboutFeature({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      minVerticalPadding: 10,
      leading: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.secondaryContainer,
          borderRadius: BorderRadius.circular(10),
        ),
        child: SizedBox.square(
          dimension: 38,
          child: Icon(icon, size: 21, color: colors.onSecondaryContainer),
        ),
      ),
      title: Text(title, style: theme.textTheme.titleMedium),
      subtitle: Text(description),
    );
  }
}
