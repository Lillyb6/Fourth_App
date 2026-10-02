import 'package:flutter/material.dart';

const blueberry = Color(0xff342568);

ThemeData berryTheme() {
  final colors = ColorScheme.fromSeed(seedColor: const Color(0xff4935a3));
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: colors,
    fontFamily: 'Nunito',
  );
  TextStyle heading(TextStyle? style) => style!.copyWith(
    fontFamily: 'Lora',
    color: blueberry,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.4,
    height: 1.25,
  );
  return base.copyWith(
    scaffoldBackgroundColor: const Color(0xfff7f5fc),
    textTheme: base.textTheme.copyWith(
      headlineLarge: heading(base.textTheme.headlineLarge),
      headlineMedium: heading(base.textTheme.headlineMedium),
      headlineSmall: heading(base.textTheme.headlineSmall),
      titleLarge: heading(base.textTheme.titleLarge),
      titleMedium: base.textTheme.titleMedium!.copyWith(
        color: blueberry,
        fontWeight: FontWeight.w700,
      ),
      bodyLarge: base.textTheme.bodyLarge!.copyWith(height: 1.5),
      bodyMedium: base.textTheme.bodyMedium!.copyWith(height: 1.5),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: const Color(0xfff7f5fc),
      foregroundColor: blueberry,
      titleTextStyle: heading(base.textTheme.titleLarge),
      elevation: 0,
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: colors.primaryContainer,
      foregroundColor: blueberry,
      extendedTextStyle: const TextStyle(
        fontFamily: 'Nunito',
        fontWeight: FontWeight.w800,
        fontSize: 15,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: colors.primaryContainer,
      surfaceTintColor: Colors.transparent,
      indicatorColor: blueberry,
      elevation: 0,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontFamily: 'Nunito',
          fontSize: 12,
          color: blueberry,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w800
              : FontWeight.w600,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? Colors.white
              : blueberry,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: colors.outlineVariant),
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    ),
  );
}
