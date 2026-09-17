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
      textTheme: const TextTheme().apply(
        bodyColor: AppColors.espresso,
        displayColor: AppColors.espresso,
      ),
    );
  }
}
