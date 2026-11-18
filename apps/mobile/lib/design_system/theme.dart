import 'package:material_ui/material_ui.dart';

class MailTheme {
  static const primary = Color(0xFF2458D3);
  static ThemeData create(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme =
        ColorScheme.fromSeed(
          seedColor: primary,
          brightness: brightness,
        ).copyWith(
          primary: dark ? const Color(0xFFAFC6FF) : primary,
          onPrimary: dark ? const Color(0xFF102B67) : Colors.white,
          primaryContainer: dark
              ? const Color(0xFF203358)
              : const Color(0xFFEAF0FF),
          surface: dark ? const Color(0xFF1B202A) : Colors.white,
          onSurface: dark ? const Color(0xFFF0F3FA) : const Color(0xFF17233B),
          onSurfaceVariant: dark
              ? const Color(0xFFB2BDD1)
              : const Color(0xFF5C6880),
          outlineVariant: dark
              ? const Color(0xFF3F4B60)
              : const Color(0xFFDEE4EF),
        );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: brightness,
      scaffoldBackgroundColor: dark
          ? const Color(0xFF11141B)
          : const Color(0xFFF4F6FA),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          fontSize: 32,
          height: 1.25,
          fontWeight: FontWeight.w600,
          letterSpacing: -1,
        ),
        headlineMedium: TextStyle(
          fontSize: 28,
          height: 1.3,
          fontWeight: FontWeight.w600,
          letterSpacing: -.8,
        ),
        titleLarge: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
        titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        bodyLarge: TextStyle(fontSize: 16, height: 1.55),
        bodyMedium: TextStyle(fontSize: 16, height: 1.45),
        labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        bodySmall: TextStyle(fontSize: 12, height: 1.4),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLow,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 18,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primaryContainer,
        height: 80,
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1),
      cardTheme: CardThemeData(
        color: scheme.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }
}
