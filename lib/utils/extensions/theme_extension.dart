import 'package:flutter/material.dart';

extension ThemeExtension on ThemeData {
  bool get isDarkMode => brightness == Brightness.dark;

  List<BoxShadow> get neumorphicShadows => [
        BoxShadow(
          color: isDarkMode
              ? Color.alphaBlend(
                  const Color(0x20000000), scaffoldBackgroundColor)
              : const Color(0xFFEBEFFF),
          offset: const Offset(5, 5),
          blurRadius: 10,
        ),
        BoxShadow(
          color: isDarkMode
              ? Color.alphaBlend(
                  const Color(0x0CFFFFFF), scaffoldBackgroundColor)
              : Colors.white,
          offset: const Offset(-5, -5),
          blurRadius: 10,
        ),
      ];
}
