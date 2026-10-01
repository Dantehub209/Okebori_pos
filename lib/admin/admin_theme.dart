import 'package:flutter/material.dart';
import '../theme.dart';

/// The web admin's palette; the same colours as the phone app (theme.dart).
class AdminColors {
  static const background = AppColors.background;
  static const header = AppColors.navy;
  static const surface = AppColors.surface;
  static const border = AppColors.border;
  static const text = AppColors.text;
  static const muted = AppColors.muted;
  static const selected = AppColors.selected;
  static const orange = AppColors.orange;
  static const successText = AppColors.successText;
  static const errorBg = AppColors.errorBg;
  static const errorText = AppColors.errorText;
}

ThemeData buildAdminTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AdminColors.orange,
    brightness: Brightness.dark,
    primary: AdminColors.orange,
    onPrimary: Colors.white,
    surface: AdminColors.surface,
    onSurface: AdminColors.text,
    onSurfaceVariant: AdminColors.muted,
    outline: AdminColors.border,
    outlineVariant: AdminColors.border,
  ).copyWith(surfaceContainerHigh: AdminColors.surface, surfaceContainer: AdminColors.surface);
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(8),
    borderSide: const BorderSide(color: AdminColors.border),
  );

  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AdminColors.background,
    dividerColor: AdminColors.border,
    dividerTheme: const DividerThemeData(color: AdminColors.border, space: 1, thickness: 1),
    appBarTheme: const AppBarTheme(
      backgroundColor: AdminColors.background,
      foregroundColor: AdminColors.text,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AdminColors.text),
    ),
    cardTheme: CardThemeData(
      color: AdminColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: AdminColors.border),
      ),
    ),
    dialogTheme: const DialogThemeData(backgroundColor: AdminColors.surface, surfaceTintColor: Colors.transparent),
    listTileTheme: const ListTileThemeData(textColor: AdminColors.text, iconColor: AdminColors.muted),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AdminColors.background,
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(borderSide: const BorderSide(color: AdminColors.orange, width: 2)),
      labelStyle: const TextStyle(color: AdminColors.muted),
      hintStyle: const TextStyle(color: AdminColors.muted),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AdminColors.orange,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AdminColors.text,
        side: const BorderSide(color: AdminColors.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: AdminColors.orange)),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating, width: 480),
  );
}
