import 'package:flutter/material.dart';

class AppColors {
  static const navy = Color(0xFF1C2230);
  static const orange = Color(0xFFF26A1B);
  static const background = Color(0xFFF1F3F6);
  static const surface = Colors.white;
  static const border = Color(0xFFD5DAE1);
  static const text = Color(0xFF1C2230);
  static const muted = Color(0xFF5F6673);
  static const successBg = Color(0xFFE6F4EA);
  static const successText = Color(0xFF1E7B3C);
  static const errorBg = Color(0xFFFDE4E4);
  static const errorText = Color(0xFFC62828);
}

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.orange,
    primary: AppColors.orange,
    onPrimary: Colors.white,
    secondary: AppColors.navy,
    surface: AppColors.surface,
  );
  final roundedBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(8),
    borderSide: const BorderSide(color: AppColors.border),
  );

  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: AppColors.background,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.navy,
      foregroundColor: Colors.white,
      centerTitle: true,
      elevation: 0,
    ),
    cardTheme: CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      border: roundedBorder,
      enabledBorder: roundedBorder,
      focusedBorder: roundedBorder.copyWith(borderSide: const BorderSide(color: AppColors.orange, width: 2)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.orange,
        foregroundColor: Colors.white,
        disabledBackgroundColor: AppColors.border,
        elevation: 0,
        padding: const EdgeInsets.symmetric(vertical: 18),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.orange,
        side: const BorderSide(color: AppColors.border),
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
  );
}
