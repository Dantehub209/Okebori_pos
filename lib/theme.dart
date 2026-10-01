import 'package:flutter/material.dart';

/// Dark palette shared by the phone app and the web admin.
class AppColors {
  static const navy = Color(0xFF010409); // header bars and route cards
  static const orange = Color(0xFFF26A1B);
  static const background = Color(0xFF0D1117);
  static const surface = Color(0xFF161B22);
  static const selected = Color(0xFF262C36);
  static const border = Color(0xFF30363D);
  static const text = Color(0xFFE6EDF3);
  static const muted = Color(0xFF8B949E);
  static const successBg = Color(0xFF12261A);
  static const successText = Color(0xFF3FB950);
  static const errorBg = Color(0xFF3D1A1A);
  static const errorText = Color(0xFFFF7B72);
}

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.orange,
    brightness: Brightness.dark,
    primary: AppColors.orange,
    onPrimary: Colors.white,
    surface: AppColors.surface,
    onSurface: AppColors.text,
    onSurfaceVariant: AppColors.muted,
    outline: AppColors.border,
    outlineVariant: AppColors.border,
  ).copyWith(surfaceContainerHigh: AppColors.surface, surfaceContainer: AppColors.surface);
  final roundedBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(8),
    borderSide: const BorderSide(color: AppColors.border),
  );

  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.background,
    dividerColor: AppColors.border,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.navy,
      foregroundColor: AppColors.text,
      surfaceTintColor: Colors.transparent,
      centerTitle: true,
      elevation: 0,
    ),
    cardTheme: CardThemeData(
      color: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
    ),
    dialogTheme: const DialogThemeData(backgroundColor: AppColors.surface, surfaceTintColor: Colors.transparent),
    bottomSheetTheme: const BottomSheetThemeData(backgroundColor: AppColors.surface, surfaceTintColor: Colors.transparent),
    listTileTheme: const ListTileThemeData(textColor: AppColors.text, iconColor: AppColors.muted),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.background,
      border: roundedBorder,
      enabledBorder: roundedBorder,
      focusedBorder: roundedBorder.copyWith(borderSide: const BorderSide(color: AppColors.orange, width: 2)),
      labelStyle: const TextStyle(color: AppColors.muted),
      hintStyle: const TextStyle(color: AppColors.muted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.orange,
        foregroundColor: Colors.white,
        disabledBackgroundColor: AppColors.selected,
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
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: AppColors.orange)),
  );
}
