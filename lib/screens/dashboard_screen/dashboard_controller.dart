import 'package:flutter/material.dart';
import 'package:get/get.dart';

class DashboardController extends GetxController {
  static DashboardController get instance => Get.find<DashboardController>();
  final PageController pageController = PageController(initialPage: 1);
  int index = 1;
  bool showCashTally = false;
  bool hasOpenedCashTally = false;

  void switchMode() {
    FocusManager.instance.primaryFocus?.unfocus();
    showCashTally = !showCashTally;
    hasOpenedCashTally = true;
    update();
  }

  void animateToPage(int page) {
    pageController.animateToPage(page,
        duration: const Duration(milliseconds: 200), curve: Curves.easeIn);
  }
}
