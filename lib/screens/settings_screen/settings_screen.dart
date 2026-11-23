import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:neumorphic_calculator/cash_tally/l10n/app_localizations.dart';
import 'package:neumorphic_calculator/cash_tally/screens/cash_settings_screen.dart';
import 'package:neumorphic_calculator/cash_tally/state/app_scope.dart';
import 'package:neumorphic_calculator/controllers/theme_controller.dart';
import 'package:neumorphic_calculator/screens/settings_screen/settings_controller.dart';
import 'package:neumorphic_calculator/utils/enum.dart';
import 'package:neumorphic_calculator/utils/extensions/color_extension.dart';
import 'package:neumorphic_calculator/utils/extensions/extensions.dart';
import 'package:neumorphic_calculator/utils/extensions/theme_extension.dart';
import 'package:neumorphic_calculator/utils/hardware_palette.dart';
import 'package:neumorphic_calculator/utils/settings_model.dart';
import 'package:neumorphic_calculator/widgets/button_radius_dialog.dart';
import 'package:neumorphic_calculator/widgets/neumorphic_button.dart';
import 'package:system_theme/system_theme.dart';

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

  bool splash = false;

  ThemeController get themeCtrl => ThemeController.instance;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.isDarkMode;
    final titleTextStyle = theme.textTheme.headlineSmall?.copyWith(
      color: isDark ? Colors.white : Colors.black,
    );

    final isDynamicColorAvailable =
        SystemTheme.accentColor.accent != SystemTheme.fallbackColor &&
            defaultTargetPlatform.supportsAccentColor;
    return GetBuilder<SettingsController>(builder: (settingsCtrl) {
      final settings = settingsCtrl.state ?? SettingsModel.normal();
      return Scaffold(
        appBar: widget.showAppBar
            ? AppBar(title: Text(context.tr('settings')))
            : null,
        body: ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          children: [
            NeumorphicButton(
              borderRadius: settings.buttonRadius,
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const AppLanguageScreen(),
                ),
              ),
              child: ListTile(
                leading: const Icon(Icons.language),
                title: Text(context.tr('defaultLanguage')),
                trailing: Text(appLanguageLabel(AppScope.of(context).locale)),
              ),
            ),
            const SizedBox(height: 12),
            NeumorphicButton(
              borderRadius: settings.buttonRadius,
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const CashSettingsScreen(),
                ),
              ),
              child: ListTile(
                leading: const Icon(Icons.payments_outlined),
                title: Text(context.tr('cashTallySettings')),
                trailing: const Icon(Icons.chevron_right),
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              height: 75,
              child: ListView.separated(
                  key: const PageStorageKey('themeColor'),
                  shrinkWrap: true,
                  clipBehavior: Clip.none,
                  padding: EdgeInsets.zero,
                  itemCount: _colorPresets.length + 1,
                  scrollDirection: Axis.horizontal,
                  separatorBuilder: (_, index) {
                    if (index == 0 && !isDynamicColorAvailable) {
                      return const SizedBox.shrink();
                    }
                    if (index == 0 && isDynamicColorAvailable) {
                      return const VerticalDivider(
                        indent: 10,
                        endIndent: 10,
                        thickness: 3,
                      );
                    }
                    return const SizedBox(width: 12.0);
                  },
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      if (!isDynamicColorAvailable) {
                        return const SizedBox.shrink();
                      }
                      return NeumorphicButton(
                        borderRadius: settings.buttonRadius,
                        onPressed: () {
                          final accentColor = SystemTheme.accentColor.accent
                              .withValues(alpha: 1);
                          settingsCtrl.updateSettings(
                              settings.copyWith(dynamicColor: true));
                          final light =
                              accentColor.getTheme(settings.font.textTheme);
                          final dark = accentColor.getTheme(
                              settings.font.textTheme,
                              brightness: Brightness.dark);
                          ThemeController.instance.updateTheme(light, dark);
                        },
                        child: Container(
                          height: 50,
                          width: 50,
                          decoration: BoxDecoration(
                            color: SystemTheme.accentColor.accent
                                .withValues(alpha: 1),
                            borderRadius: BorderRadius.circular(50),
                          ),
                          child: settings.dynamicColor
                              ? const Icon(Icons.check, color: Colors.white)
                              : null,
                        ),
                      );
                    }
                    final themeColor = _colorPresets[index - 1];
                    final hardware = themeColor.hardware;
                    final selected = settings.themeColor == themeColor &&
                        !settings.dynamicColor;
                    return NeumorphicButton(
                      semanticLabel: hardware?.label ??
                          (themeColor == ThemeColor.midnightAmber
                              ? 'Midnight Amber'
                              : null),
                      borderRadius: settings.buttonRadius,
                      onPressed: () {
                        settingsCtrl.updateSettings(settings.copyWith(
                            themeColor: themeColor, dynamicColor: false));

                        final textTheme = settings.font.textTheme;
                        themeCtrl.updateTheme(
                          themeColor.getTheme(textTheme),
                          themeColor.getTheme(textTheme,
                              brightness: Brightness.dark),
                        );
                        if (themeColor == ThemeColor.midnightAmber) {
                          themeCtrl.saveThemeMode(ThemeMode.dark);
                        } else if (hardware != null) {
                          themeCtrl.saveThemeMode(hardware.preferredMode);
                        }
                      },
                      child: hardware != null
                          ? _HardwareSwatch(
                              palette: hardware, selected: selected)
                          : Container(
                              height: 50,
                              width: 50,
                              decoration: BoxDecoration(
                                color: themeColor.color,
                                borderRadius: BorderRadius.circular(50),
                              ),
                              child: selected
                                  ? const Icon(Icons.check, color: Colors.white)
                                  : null,
                            ),
                    );
                  }),
            ),
            const SizedBox(height: 18.0),
            GetBuilder<ThemeController>(builder: (_) {
              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  NeumorphicButton(
                    borderRadius: settings.buttonRadius,
                    onPressed: () async {
                      themeCtrl.saveThemeMode(ThemeMode.system);
                    },
                    child: Icon(
                      Icons.brightness_auto,
                      size: 28,
                      color: themeCtrl.themeMode == ThemeMode.system
                          ? theme.colorScheme.primary
                          : isDark
                              ? Colors.white
                              : Colors.black54,
                    ),
                  ),
                  NeumorphicButton(
                    borderRadius: settings.buttonRadius,
                    onPressed: () {
                      themeCtrl.saveThemeMode(ThemeMode.light);
                    },
                    child: Icon(
                      Icons.light_mode,
                      size: 28,
                      color: themeCtrl.themeMode == ThemeMode.light
                          ? theme.colorScheme.primary
                          : isDark
                              ? Colors.white
                              : Colors.black54,
                    ),
                  ),
                  NeumorphicButton(
                    borderRadius: settings.buttonRadius,
                    onPressed: () {
                      themeCtrl.saveThemeMode(ThemeMode.dark);

                      // context.updateThemeMode(
                      //   themeMode: ThemeMode.dark,
                      //   isReversed: true,
                      // );
                    },
                    child: Icon(
                      Icons.dark_mode,
                      size: 28,
                      color: themeCtrl.themeMode == ThemeMode.dark
                          ? theme.colorScheme.primary
                          : isDark
                              ? Colors.white
                              : Colors.black54,
                    ),
                  ),
                ],
              );
            }),
            const SizedBox(height: 18.0),
            NeumorphicButton(
              borderRadius: settings.buttonRadius,
              child: ListTile(
                title: Text(context.tr('keycapFont')),
                trailing: Text(theme.textTheme.bodyLarge?.fontFamily
                        ?.replaceAll('_regular', '') ??
                    ''),
              ),
              onPressed: () {
                showAdaptiveDialog<Fonts>(
                    context: context,
                    builder: (context) {
                      return SimpleDialog(
                        title: Text(context.tr('keycapSelectFont')),
                        titleTextStyle: titleTextStyle,
                        children: Fonts.values.map((font) {
                          final theme = isDark
                              ? font.setToTheme(themeCtrl.darkTheme)
                              : font.setToTheme(themeCtrl.lightTheme);
                          return Theme(
                            data: theme,
                            child: ListTile(
                              trailing: settings.font == font
                                  ? const Icon(Icons.check)
                                  : null,
                              onTap: () {
                                if (font == settings.font) {
                                  return Navigator.pop(context);
                                }
                                ThemeController.instance.updateTheme(
                                    font.setToTheme(themeCtrl.lightTheme),
                                    font.setToTheme(themeCtrl.darkTheme));
                                SettingsController.instance.updateSettings(
                                    settings.copyWith(font: font));
                                Navigator.pop(context);
                              },
                              title: Text(font.name.capitalize ?? font.name),
                              subtitle: Text(context.tr('keycapFontExample')),
                            ),
                          );
                        }).toList(),
                      );
                    });
              },
            ),
            const SizedBox(height: 18.0),
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 8, bottom: 8),
              child: Text(
                context.tr('keycapCalculatorSettings'),
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            NeumorphicButton(
              borderRadius: settings.buttonRadius,
              onPressed: () async {
                final style = await _selectKeyStyle(context, settings);
                if (style != null && context.mounted) {
                  final current = settingsCtrl.state ?? settings;
                  settingsCtrl
                      .updateSettings(current.copyWith(keyStyle: style));
                }
              },
              child: ListTile(
                title: Text(context.tr('keycapKeyStyle')),
                trailing:
                    Text(context.tr('keycapStyle-${settings.keyStyle.name}')),
              ),
            ),
            const SizedBox(height: 18.0),
            NeumorphicButton(
              borderRadius: settings.buttonRadius,
              child: ListTile(
                title: Text(context.tr('keycapButtonRadius')),
                trailing: Text(settings.buttonRadius.toString()),
              ),
              onPressed: () async {
                await ButtonRadiusDialog(
                  buttonRadius: settings.buttonRadius,
                  keyStyle: settings.keyStyle,
                ).show(context).then(
                  (result) {
                    if (result is double) {
                      settingsCtrl.updateSettings(
                          settings.copyWith(buttonRadius: result));
                      // ThemeController.instance.update();
                    }
                  },
                );
              },
            ),
            const SizedBox(height: 18.0),
            NeumorphicButton(
              borderRadius: settings.buttonRadius,
              child: ListTile(
                title: Text(context.tr('keycapHaptics')),
                trailing: Switch(
                  value: settings.hapticEnabled,
                  onChanged: (value) {
                    if (value) {
                      HapticFeedback.mediumImpact();
                    }
                    settingsCtrl.updateSettings(
                        settings.copyWith(hapticEnabled: value));
                  },
                ),
              ),
              onPressed: () {
                if (!settings.hapticEnabled) {
                  HapticFeedback.mediumImpact();
                }
                settingsCtrl.updateSettings(
                    settings.copyWith(hapticEnabled: !settings.hapticEnabled));
              },
            )
          ],
        ),
      );
    });
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

class _HardwareSwatch extends StatelessWidget {
  const _HardwareSwatch({required this.palette, required this.selected});

  final HardwarePalette palette;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = [
      palette.housing,
      palette.digits.fill,
      palette.operators.fill,
      palette.utility.fill,
      palette.clear.fill,
      palette.equals.fill,
    ];
    return Semantics(
      selected: selected,
      child: Container(
        width: 50,
        height: 50,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.22),
          ),
          gradient: SweepGradient(
            // Duplicate each color at the ends of its sector for crisp edges.
            colors: [
              for (final color in colors) ...[color, color]
            ],
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
                  child: Icon(Icons.check, size: 18, color: Colors.white),
                ),
              )
            : null,
      ),
    );
  }
}
