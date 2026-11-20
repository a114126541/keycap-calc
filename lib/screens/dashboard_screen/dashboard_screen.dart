import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:neumorphic_calculator/screens/calculator_screen/calculator_controller.dart';
import 'package:neumorphic_calculator/screens/dashboard_screen/dashboard_controller.dart';
import 'package:neumorphic_calculator/screens/calculator_screen/calculator_screen.dart';
import 'package:neumorphic_calculator/screens/history_screen/history_screen.dart';
import 'package:neumorphic_calculator/screens/settings_screen/settings_screen.dart';
import 'package:neumorphic_calculator/tutorial_screen.dart';
import 'package:neumorphic_calculator/utils/extensions/extensions.dart';
import 'package:neumorphic_calculator/utils/hardware_palette.dart';
import 'package:neumorphic_calculator/widgets/calculator_app_bar.dart';
import 'package:neumorphic_calculator/widgets/circular_wipe_overlay_widget.dart';
import 'package:neumorphic_calculator/widgets/custom_scroll_physics.dart';
import 'package:neumorphic_calculator/widgets/input_widget.dart';
import 'package:neumorphic_calculator/widgets/keep_alive_wrapper.dart';
import 'package:neumorphic_calculator/widgets/result_widget.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GetBuilder<DashboardController>(
      builder: (dashCtrl) {
        return PopScope(
          canPop: dashCtrl.index == 1,
          onPopInvokedWithResult: (val, _) {
            if (val) return;
            dashCtrl.animateToPage(1);
          },
          child: TutorialScreen(
            child: AnnotatedRegion<SystemUiOverlayStyle>(
              value: theme.appBarTheme.systemOverlayStyle?.copyWith(
                    systemNavigationBarColor: theme.scaffoldBackgroundColor,
                  ) ??
                  SystemUiOverlayStyle.light,
              child: Scaffold(
                body: SafeArea(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final isLandscape =
                          constraints.maxWidth > constraints.maxHeight;
                      final contentWidth = math.min(
                        constraints.maxWidth,
                        isLandscape ? 1120.0 : 680.0,
                      );
                      final availableHeight = constraints.maxHeight;
                      final keypadHeight = isLandscape
                          ? availableHeight -
                              math.max(
                                availableHeight * 0.32,
                                math.min(96.0, availableHeight * 0.5),
                              )
                          : math.min(
                              availableHeight * 0.66,
                              math.min(constraints.maxWidth * 1.25, 700.0),
                            );

                      return Column(
                        children: [
                          Expanded(
                            child: SizedBox(
                              width: contentWidth,
                              child:
                                  _CalculatorDisplay(isLandscape: isLandscape),
                            ),
                          ),
                          SizedBox(
                            height: keypadHeight,
                            child: PageView(
                              physics: CustomScrollPhysics(),
                              onPageChanged: (index) {
                                dashCtrl.index = index;
                                dashCtrl.update();
                              },
                              controller: dashCtrl.pageController,
                              children: [
                                const KeepAliveWrapper(child: SettingsScreen()),
                                KeepAliveWrapper(
                                  child: Center(
                                    child: SizedBox(
                                      width: contentWidth,
                                      height: double.infinity,
                                      child: CalculatorScreen(
                                        isLandscape: isLandscape,
                                      ),
                                    ),
                                  ),
                                ),
                                const KeepAliveWrapper(child: HistoryScreen()),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CalculatorDisplay extends StatelessWidget {
  const _CalculatorDisplay({required this.isLandscape});

  final bool isLandscape;
  static const _baseReadoutHeight = 156.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hardware = theme.extension<HardwarePalette>();
    return GetBuilder<CalculatorController>(
      builder: (controller) {
        final hasResult = controller.output.trim().isNotEmpty;
        return CircularWipeOverlayWidget(
          triggerWipe: controller.isClearing,
          onWipeComplete: controller.onWipeComplete,
          child: Column(
            children: [
              const CalculatorAppBar(),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final extraPortraitHeight = isLandscape
                        ? 0.0
                        : math.max(
                            0.0, constraints.maxHeight - _baseReadoutHeight);
                    final readoutHeight = _baseReadoutHeight +
                        math.min(extraPortraitHeight * 0.10, 32.0);
                    final bottomInset =
                        math.min(extraPortraitHeight * 0.08, 24.0);
                    final fontScale = readoutHeight / _baseReadoutHeight;
                    final readout = Column(
                      children: [
                        Expanded(
                          child: InputWidget(
                            controller.textCtrl,
                            compact: hasResult,
                            fontScale: fontScale,
                          ),
                        ),
                        if (hasResult)
                          Expanded(
                            flex: 2,
                            child: ResultWidget(
                              controller.output.formatExpression(),
                              fontScale: fontScale,
                            ),
                          ),
                      ],
                    );
                    return Padding(
                      padding: EdgeInsets.only(bottom: bottomInset),
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxHeight: readoutHeight),
                          child: hardware == null
                              ? readout
                              : _LcdPanel(palette: hardware, child: readout),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LcdPanel extends StatelessWidget {
  const _LcdPanel({required this.palette, required this.child});

  final HardwarePalette palette;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final shell = Theme.of(context).scaffoldBackgroundColor;
    final bezel = Color.lerp(shell, const Color(0xFF272C2F), 0.84)!;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: bezel,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: Color.lerp(bezel, Colors.white, 0.20)!),
        boxShadow: const [
          BoxShadow(
              color: Color(0x44000000), blurRadius: 3, offset: Offset(0, 2)),
        ],
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(7),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color.lerp(palette.lcd, const Color(0xFF657262), 0.20)!,
              palette.lcd
            ],
          ),
        ),
        child: child,
      ),
    );
  }
}
