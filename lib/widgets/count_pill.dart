import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// A pill-shaped filter chip with an optional count badge.
class CountPill extends StatelessWidget {
  final String label;
  final int? count;
  final bool active;
  final VoidCallback onTap;

  const CountPill({
    super.key,
    required this.label,
    this.count,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: active ? AppColors.tomato : AppColors.card,
          borderRadius: BorderRadius.circular(999),
          border: active ? null : Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: active ? Colors.white : AppColors.espresso,
              ),
            ),
            if (count != null) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: active
                      ? Colors.white.withValues(alpha: 0.2)
                      : AppColors.tomatoLight,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: active ? Colors.white : AppColors.tomato,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
