import 'package:flutter/material.dart';

import 'app_colors.dart';

class AppTheme {
  AppTheme._();

  static ThemeData get light {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.cream,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.tomato,
        primary: AppColors.tomato,
        secondary: AppColors.mint,
        surface: AppColors.card,
      ),
      fontFamily: 'WorkSans',
      textTheme: const TextTheme().apply(
        bodyColor: AppColors.espresso,
        displayColor: AppColors.espresso,
      ).copyWith(
        displayLarge: const TextStyle(fontFamily: 'DMSans'),
        displayMedium: const TextStyle(fontFamily: 'DMSans'),
        displaySmall: const TextStyle(fontFamily: 'DMSans'),
        headlineLarge: const TextStyle(fontFamily: 'DMSans'),
        headlineMedium: const TextStyle(fontFamily: 'DMSans'),
        headlineSmall: const TextStyle(fontFamily: 'DMSans'),
        titleLarge: const TextStyle(fontFamily: 'DMSans'),
        titleMedium: const TextStyle(fontFamily: 'DMSans'),
        titleSmall: const TextStyle(fontFamily: 'DMSans'),
      ),
    );
  }
}
