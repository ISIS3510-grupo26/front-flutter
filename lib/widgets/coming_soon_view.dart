import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class ComingSoonView extends StatelessWidget {
  final String title;
  final IconData icon;

  const ComingSoonView({super.key, required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: AppColors.muted),
          const SizedBox(height: 12),
          Text(
            '$title coming soon',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.espresso,
            ),
          ),
        ],
      ),
    );
  }
}
