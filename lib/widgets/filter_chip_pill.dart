import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class FilterChipPill extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const FilterChipPill({
    super.key,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: active ? AppColors.tomato : AppColors.surface.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(999),
          border: active
              ? null
              : Border.all(color: AppColors.espresso.withValues(alpha: 0.1)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: active ? FontWeight.bold : FontWeight.w600,
            color: active ? Colors.white : AppColors.espresso,
          ),
        ),
      ),
    );
  }
}
