import 'dart:math' as math;

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:neumorphic_calculator/cash_tally/l10n/app_localizations.dart';
import 'package:neumorphic_calculator/cash_tally/screens/cash_settings_screen.dart';
import 'package:neumorphic_calculator/cash_tally/state/app_scope.dart';
import 'package:neumorphic_calculator/cash_tally/widgets/cash_panels.dart';
import 'package:neumorphic_calculator/controllers/theme_controller.dart';
import 'package:neumorphic_calculator/screens/settings_screen/settings_controller.dart';
import 'package:neumorphic_calculator/utils/enum.dart';
import 'package:neumorphic_calculator/utils/extensions/color_extension.dart';
import 'package:neumorphic_calculator/utils/extensions/widget_extension.dart';
import 'package:neumorphic_calculator/utils/hardware_palette.dart';
import 'package:neumorphic_calculator/utils/settings_model.dart';
import 'package:neumorphic_calculator/widgets/button_radius_dialog.dart';
import 'package:neumorphic_calculator/widgets/neumorphic_button.dart';
import 'package:neumorphic_calculator/widgets/settings_row.dart';
import 'package:system_theme/system_theme.dart';

enum _Section {
  appearance('appearance', LucideIcons.monitor),
  general('keycapGeneral', LucideIcons.settings),
  calculatorKeys('keycapCalculatorKeys', LucideIcons.keyboard),
  cash('cashTallySettings', LucideIcons.banknote);

  const _Section(this.label, this.icon);

  final String label;
  final IconData icon;
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({this.showAppBar = false, super.key});

  final bool showAppBar;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static final _colorPresets = [
    ThemeColor.midnightAmber,
    ThemeColor.ivoryDesk,
    ThemeColor.silverOrange,
    ThemeColor.graphiteTeal,
    ThemeColor.vintageSilver,
    ...ThemeColor.values.where(
      (color) => color != ThemeColor.midnightAmber && color.hardware == null,
    ),
  ];

  final _detailScroll = ScrollController();
  var _section = _Section.appearance;

  @override
  void dispose() {
    _detailScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GetBuilder<SettingsController>(builder: (controller) {
      final settings = controller.state ?? SettingsModel.normal();
      return Scaffold(
        appBar: widget.showAppBar
            ? AppBar(title: Text(context.tr('settings')))
            : null,
        body: SafeArea(
          top: false,
          child: LayoutBuilder(builder: (context, constraints) {
            final split =
                MediaQuery.orientationOf(context) == Orientation.landscape &&
                    constraints.maxWidth >= cashSplitWidth;
            return Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: split ? cashWorkspaceWidth : 680,
                ),
                child: split
                    ? _splitSettings(context, controller, settings)
                    : _singleColumn(context, controller, settings),
              ),
            );
          }),
        ),
      );
    });
  }

  Widget _splitSettings(
    BuildContext context,
    SettingsController controller,
    SettingsModel settings,
  ) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final rows = switch (_section) {
      _Section.appearance => _appearance(context, controller, settings),
      _Section.general => _general(context, controller, settings),
      _Section.calculatorKeys => _calculatorKeys(context, controller, settings),
      _Section.cash => const <Widget>[CashSettingsContent(embedded: true)],
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        key: const ValueKey('settings-two-panes'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 3,
            child: CashPanel(
              child: ListView.separated(
                padding: EdgeInsets.zero,
                primary: false,
                itemCount: _Section.values.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, indent: 12, endIndent: 12),
                itemBuilder: (context, index) {
                  final section = _Section.values[index];
                  final selected = _section == section;
                  return ListTile(
                    key: ValueKey('settings-section-${section.name}'),
                    minTileHeight: 60,
                    minVerticalPadding: 12,
                    leading: Icon(section.icon, size: 24),
                    title: Text(
                      context.tr(section.label),
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: selected
                            ? colors.onPrimaryContainer
                            : colors.onSurface,
                      ),
                    ),
                    selected: selected,
                    selectedTileColor: colors.primaryContainer,
                    selectedColor: colors.onPrimaryContainer,
                    onTap: () => setState(() => _section = section),
                  );
                },
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 7,
            child: CashPanel(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Semantics(
                        header: true,
                        child: Text(
                          context.tr(_section.label),
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: Scrollbar(
                        controller: _detailScroll,
                        thumbVisibility: true,
                        child: ListView(
                          key: PageStorageKey(
                              'settings-detail-${_section.name}'),
                          controller: _detailScroll,
                          padding: const EdgeInsets.fromLTRB(0, 8, 0, 14),
                          children: rows,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _singleColumn(
    BuildContext context,
    SettingsController controller,
    SettingsModel settings,
  ) {
    return ListView(
      key: const PageStorageKey('settings-single-column'),
      primary: false,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
      children: [
        _sectionPanel(
            context, _Section.general, _general(context, controller, settings)),
        const SizedBox(height: 12),
        CashPanel(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: SettingsRow(
              icon: _Section.cash.icon,
              title: context.tr(_Section.cash.label),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const CashSettingsScreen(),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _sectionPanel(context, _Section.appearance,
            _appearance(context, controller, settings)),
        const SizedBox(height: 12),
        _sectionPanel(context, _Section.calculatorKeys,
            _calculatorKeys(context, controller, settings)),
      ],
    );
  }

  Widget _sectionPanel(
    BuildContext context,
    _Section section,
    List<Widget> rows,
  ) {
    return CashPanel(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                context.tr(section.label),
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const Divider(),
            ...rows,
          ],
        ),
      ),
    );
  }

  List<Widget> _appearance(
    BuildContext context,
    SettingsController controller,
    SettingsModel settings,
  ) {
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
        child: _settingLabel(
          context,
          LucideIcons.palette,
          context.tr('keycapThemeColor'),
        ),
      ),
      _themeSwatches(context, controller, settings),
      const Divider(height: 1),
      _displayMode(context),
      const Divider(height: 1),
      SettingsRow(
        icon: LucideIcons.type,
        title: context.tr('keycapFont'),
        value: settings.font.name.capitalize ?? settings.font.name,
        onTap: () => _chooseFont(context, controller, settings),
      ),
    ];
  }

  List<Widget> _general(
    BuildContext context,
    SettingsController controller,
    SettingsModel settings,
  ) {
    return [
      SettingsRow(
        icon: LucideIcons.globe,
        title: context.tr('defaultLanguage'),
        value: appLanguageLabel(AppScope.of(context).locale),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const AppLanguageScreen()),
        ),
      ),
      const Divider(height: 1),
      SwitchListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        secondary: const Icon(LucideIcons.vibrate, size: 22),
        title: Text(
          context.tr('keycapHaptics'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        subtitle: Text(context.tr('keycapHapticsHelp')),
        value: settings.hapticEnabled,
        onChanged: (value) {
          if (value) HapticFeedback.mediumImpact();
          final current = controller.state ?? settings;
          controller.updateSettings(current.copyWith(hapticEnabled: value));
        },
      ),
    ];
  }

  List<Widget> _calculatorKeys(
    BuildContext context,
    SettingsController controller,
    SettingsModel settings,
  ) {
    final theme = Theme.of(context);
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 2, 4, 6),
        child: Text(
          context.tr('keycapCalculatorSettings'),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
      SettingsRow(
        icon: LucideIcons.layers,
        title: context.tr('keycapKeyStyle'),
        value: context.tr('keycapStyle-${settings.keyStyle.name}'),
        onTap: () async {
          final style = await _selectKeyStyle(context, settings);
          if (style == null || !context.mounted) return;
          final current = controller.state ?? settings;
          controller.updateSettings(current.copyWith(keyStyle: style));
        },
      ),
      const Divider(height: 1),
      SettingsRow(
        icon: LucideIcons.squareDashedBottom,
        title: context.tr('keycapButtonRadius'),
        value: settings.buttonRadius.toString(),
        onTap: () async {
          final radius = await ButtonRadiusDialog(
            buttonRadius: settings.buttonRadius,
            keyStyle: settings.keyStyle,
          ).show(context);
          if (radius is! double || !context.mounted) return;
          final current = controller.state ?? settings;
          controller.updateSettings(current.copyWith(buttonRadius: radius));
        },
      ),
    ];
  }

  Widget _themeSwatches(
    BuildContext context,
    SettingsController controller,
    SettingsModel settings,
  ) {
    final accent = SystemTheme.accentColor.accent;
    final hasSystemAccent = accent != SystemTheme.fallbackColor &&
        defaultTargetPlatform.supportsAccentColor;
    final themeController = ThemeController.instance;

    return SizedBox(
      height: 56,
      child: ListView(
        key: const PageStorageKey('themeColor'),
        scrollDirection: Axis.horizontal,
        primary: false,
        children: [
          if (hasSystemAccent) ...[
            _ThemeSwatch(
              label: context.tr('keycapSystemAccent'),
              color: accent.withValues(alpha: 1),
              selected: settings.dynamicColor,
              onTap: () {
                final current = controller.state ?? settings;
                final color = accent.withValues(alpha: 1);
                controller.updateSettings(current.copyWith(dynamicColor: true));
                themeController.updateTheme(
                  color.getTheme(current.font.textTheme),
                  color.getTheme(current.font.textTheme,
                      brightness: Brightness.dark),
                );
              },
            ),
            const VerticalDivider(width: 8, indent: 10, endIndent: 10),
          ],
          for (final preset in _colorPresets)
            _ThemeSwatch(
              label: preset.hardware?.label ??
                  (preset == ThemeColor.midnightAmber
                      ? 'Midnight Amber'
                      : preset.name),
              color: preset.color,
              palette: preset.hardware,
              selected: !settings.dynamicColor && settings.themeColor == preset,
              onTap: () {
                final current = controller.state ?? settings;
                controller.updateSettings(
                  current.copyWith(themeColor: preset, dynamicColor: false),
                );
                final textTheme = current.font.textTheme;
                themeController.updateTheme(
                  preset.getTheme(textTheme),
                  preset.getTheme(textTheme, brightness: Brightness.dark),
                );
                if (preset == ThemeColor.midnightAmber) {
                  themeController.saveThemeMode(ThemeMode.dark);
                } else if (preset.hardware case final palette?) {
                  themeController.saveThemeMode(palette.preferredMode);
                }
              },
            ),
        ],
      ),
    );
  }

  Widget _displayMode(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: LayoutBuilder(builder: (context, constraints) {
        final colors = Theme.of(context).colorScheme;
        return Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 8,
          children: [
            _settingLabel(
                context, LucideIcons.monitor, context.tr('keycapDisplayMode')),
            SizedBox(
              width: math.min(constraints.maxWidth, 348),
              child: GetBuilder<ThemeController>(
                builder: (controller) => SegmentedButton<ThemeMode>(
                  expandedInsets: EdgeInsets.zero,
                  showSelectedIcon: false,
                  selected: {controller.themeMode},
                  style: SegmentedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    foregroundColor: colors.onSurface,
                    selectedBackgroundColor: colors.primaryContainer,
                    selectedForegroundColor: colors.onPrimaryContainer,
                    minimumSize: const Size(0, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    side: BorderSide(color: colors.outlineVariant),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  segments: [
                    ButtonSegment(
                      value: ThemeMode.system,
                      label: Text(context.tr('keycapFollowSystem'),
                          textAlign: TextAlign.center),
                    ),
                    ButtonSegment(
                      value: ThemeMode.light,
                      label: Text(context.tr('keycapLightMode')),
                    ),
                    ButtonSegment(
                      value: ThemeMode.dark,
                      label: Text(context.tr('keycapDarkMode')),
                    ),
                  ],
                  onSelectionChanged: (modes) =>
                      controller.saveThemeMode(modes.single),
                ),
              ),
            ),
          ],
        );
      }),
    );
  }

  Widget _settingLabel(BuildContext context, IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 22),
        const SizedBox(width: 16),
        Flexible(
          child: Text(label, style: Theme.of(context).textTheme.titleMedium),
        ),
      ],
    );
  }

  Future<void> _chooseFont(
    BuildContext context,
    SettingsController controller,
    SettingsModel settings,
  ) async {
    final font = await showAdaptiveDialog<Fonts>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(context.tr('keycapSelectFont')),
        children: [
          for (final font in Fonts.values)
            Theme(
              data: font.setToTheme(Theme.of(context)),
              child: ListTile(
                trailing:
                    settings.font == font ? const Icon(Icons.check) : null,
                onTap: () => Navigator.of(dialogContext).pop(font),
                title: Text(font.name.capitalize ?? font.name),
                subtitle: Text(context.tr('keycapFontExample')),
              ),
            ),
        ],
      ),
    );
    if (font == null || !context.mounted) return;
    final current = controller.state ?? settings;
    if (current.font == font) return;
    ThemeController.instance.updateFont(font);
    controller.updateSettings(current.copyWith(font: font));
  }

  Future<KeyStyle?> _selectKeyStyle(
      BuildContext context, SettingsModel settings) {
    final theme = Theme.of(context);
    final hardware = theme.extension<HardwarePalette>();
    return showDialog<KeyStyle>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(context.tr('keycapKeyStyle')),
        children: [
          for (final style in KeyStyle.values)
            ListTile(
              key: ValueKey(style),
              selected: settings.keyStyle == style,
              leading: SizedBox(
                width: 44,
                height: 38,
                child: NeumorphicButton(
                  constraints: const BoxConstraints(),
                  borderRadius: settings.buttonRadius.clamp(0, 19).toDouble(),
                  backgroundColor: hardware?.digits.fill ??
                      theme.colorScheme.surfaceContainer,
                  keyStyle: style,
                  child: ExcludeSemantics(
                    child: Text('7',
                        style: TextStyle(color: hardware?.digits.ink)),
                  ),
                ),
              ),
              title: Text(context.tr('keycapStyle-${style.name}')),
              trailing:
                  settings.keyStyle == style ? const Icon(Icons.check) : null,
              onTap: () => Navigator.of(dialogContext).pop(style),
            ),
        ],
      ),
    );
  }
}

class _ThemeSwatch extends StatelessWidget {
  const _ThemeSwatch({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
    this.palette,
  });

  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  final HardwarePalette? palette;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hardware = palette;
    final gradient = hardware == null
        ? null
        : SweepGradient(
            colors: [
              for (final color in [
                hardware.housing,
                hardware.digits.fill,
                hardware.operators.fill,
                hardware.utility.fill,
                hardware.clear.fill,
                hardware.equals.fill,
              ]) ...[
                color,
                color,
              ],
            ],
            // Repeat colors at sector boundaries to keep hard edges.
            stops: const [
              0,
              .27,
              .27,
              .51,
              .51,
              .66,
              .66,
              .79,
              .79,
              .91,
              .91,
              1
            ],
          );
    return Semantics(
      button: true,
      label: label,
      selected: selected,
      child: SizedBox(
        width: 48,
        child: InkResponse(
          onTap: onTap,
          radius: 23,
          child: Center(
            child: Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color,
                gradient: gradient,
                border: Border.all(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.22),
                ),
              ),
              child: selected
                  ? const DecoratedBox(
                      decoration: BoxDecoration(
                        color: Color(0xBB171A1C),
                        shape: BoxShape.circle,
                      ),
                      child: Padding(
                        padding: EdgeInsets.all(3),
                        child: Icon(Icons.check, size: 16, color: Colors.white),
                      ),
                    )
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}
