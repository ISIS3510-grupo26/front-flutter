import 'package:flutter/material.dart';

import '../services/nearby_favorites_loader.dart';
import '../theme/app_colors.dart';

class NearbyFailureView extends StatelessWidget {
  final NearbyFailure failure;
  final VoidCallback onRetry;
  final VoidCallback onOpenSettings;

  const NearbyFailureView({
    super.key,
    required this.failure,
    required this.onRetry,
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    final (message, action) = switch (failure) {
      NearbyFailure.signedOut => (
          'Sign in to see which saved places are open nearby.',
          null,
        ),
      NearbyFailure.locationOff => (
          'Turn on location to find saved places nearby.',
          TextButton(onPressed: onRetry, child: const Text('Try again')),
        ),
      NearbyFailure.locationDenied => (
          'Allow location access to find saved places nearby.',
          TextButton(onPressed: onRetry, child: const Text('Try again')),
        ),
      NearbyFailure.locationBlocked => (
          'Location access is turned off for CampusBites. Enable it in settings.',
          TextButton(
            onPressed: onOpenSettings,
            child: const Text('Open settings'),
          ),
        ),
      NearbyFailure.network => (
          "Couldn't reach CampusBites. Check your connection and try again.",
          TextButton(onPressed: onRetry, child: const Text('Try again')),
        ),
    };

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.muted),
            ),
            if (action != null) ...[
              const SizedBox(height: 8),
              action,
            ],
          ],
        ),
      ),
    );
  }
}
