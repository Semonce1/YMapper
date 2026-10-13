import 'package:flutter/material.dart';

/// Paleta de OrigenLabs Mapper: oscura, de alto contraste para usar a pleno
/// sol en obra, con amarillo de señalización como acento.
class OrigenColors {
  static const background = Color(0xFF12161B);
  static const surface = Color(0xFF1C232B);
  static const surfaceHigh = Color(0xFF242D36);
  static const border = Color(0xFF2C3640);
  static const text = Color(0xFFE8ECEF);
  static const textMuted = Color(0xFF9AA6B2);
  static const accent = Color(0xFFF2C230);
  static const onAccent = Color(0xFF12161B);
  static const gcp = Color(0xFF5AA9E6);
  static const check = Color(0xFFFF8A3D);
  static const ok = Color(0xFF3BB273);
  static const danger = Color(0xFFE5534B);
  static const dangerBg = Color(0xFF3A2418);
  static const dangerText = Color(0xFFFFB48A);
}

class OrigenTheme {
  static ThemeData get dark {
    const scheme = ColorScheme(
      brightness: Brightness.dark,
      primary: OrigenColors.accent,
      onPrimary: OrigenColors.onAccent,
      primaryContainer: Color(0xFF3A3218),
      onPrimaryContainer: OrigenColors.accent,
      secondary: OrigenColors.gcp,
      onSecondary: OrigenColors.background,
      tertiary: OrigenColors.accent,
      onTertiary: OrigenColors.onAccent,
      error: OrigenColors.danger,
      onError: Colors.white,
      errorContainer: OrigenColors.dangerBg,
      onErrorContainer: OrigenColors.dangerText,
      surface: OrigenColors.surface,
      onSurface: OrigenColors.text,
      onSurfaceVariant: OrigenColors.textMuted,
      surfaceContainerHighest: OrigenColors.background,
      surfaceContainerHigh: OrigenColors.surfaceHigh,
      surfaceContainer: OrigenColors.surface,
      outline: OrigenColors.border,
      outlineVariant: OrigenColors.border,
    );

    final shape12 = RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
    final shape14 = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: OrigenColors.background,
      canvasColor: OrigenColors.surface,
      dividerColor: OrigenColors.border,
      cardTheme: CardThemeData(
        color: OrigenColors.surface,
        elevation: 0,
        shape: shape14,
        margin: const EdgeInsets.symmetric(vertical: 6),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: OrigenColors.accent,
          foregroundColor: OrigenColors.onAccent,
          minimumSize: const Size(44, 48),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
          shape: shape14,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: OrigenColors.accent,
          foregroundColor: OrigenColors.onAccent,
          minimumSize: const Size(44, 48),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
          shape: shape14,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: OrigenColors.text,
          minimumSize: const Size(44, 48),
          side: const BorderSide(color: OrigenColors.border),
          shape: shape14,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: OrigenColors.accent),
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: OrigenColors.accent,
        inactiveTrackColor: OrigenColors.border,
        thumbColor: OrigenColors.accent,
        overlayColor: Color(0x33F2C230),
        valueIndicatorColor: OrigenColors.accent,
        valueIndicatorTextStyle: TextStyle(color: OrigenColors.onAccent),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected)
                ? OrigenColors.onAccent
                : OrigenColors.textMuted),
        trackColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected)
                ? OrigenColors.accent
                : OrigenColors.border),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: OrigenColors.background,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: OrigenColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: OrigenColors.border),
        ),
        labelStyle: const TextStyle(color: OrigenColors.textMuted),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: OrigenColors.surface,
        shape: shape14,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: OrigenColors.surfaceHigh,
        contentTextStyle: const TextStyle(color: OrigenColors.text),
        behavior: SnackBarBehavior.floating,
        shape: shape12,
      ),
      listTileTheme: const ListTileThemeData(iconColor: OrigenColors.textMuted),
    );
  }
}
