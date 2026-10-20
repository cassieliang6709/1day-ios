import 'package:flutter/material.dart';

const oneDayBlue = Color(0xFF1677FF);
const oneDayCyan = Color(0xFF38B6FF);
const oneDayNavy = Color(0xFF0F2E6B);
const oneDayCanvas = Color(0xFFF5F8FF);
const oneDayMist = Color(0xFFDCEBFF);

bool isChinese(BuildContext context) =>
    Localizations.localeOf(context).languageCode == 'zh';

String say(BuildContext context, String zh, String en) =>
    isChinese(context) ? zh : en;

ThemeData oneDayTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: oneDayBlue,
    primary: oneDayBlue,
    surface: Colors.white,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: oneDayCanvas,
    appBarTheme: const AppBarTheme(
      backgroundColor: oneDayCanvas,
      foregroundColor: oneDayNavy,
      elevation: 0,
      centerTitle: false,
    ),
    textTheme: const TextTheme(
      headlineMedium: TextStyle(
        color: oneDayNavy,
        fontSize: 30,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.8,
      ),
      titleLarge: TextStyle(color: oneDayNavy, fontWeight: FontWeight.w700),
      bodyMedium: TextStyle(color: oneDayNavy),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: oneDayBlue,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(54),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
  );
}

class BluePanel extends StatelessWidget {
  const BluePanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(26),
      border: Border.all(color: oneDayMist),
    ),
    child: child,
  );
}
