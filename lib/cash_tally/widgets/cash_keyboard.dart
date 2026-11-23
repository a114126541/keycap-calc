import 'package:flutter/material.dart';

void dismissCashKeyboard(PointerDownEvent event) {
  FocusManager.instance.primaryFocus?.unfocus();
}
