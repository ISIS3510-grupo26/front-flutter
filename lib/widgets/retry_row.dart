import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'offline_banner.dart';

/// The one-line failure of a For You section: what went wrong and Retry.
/// [offlineMessage] shows as an offline banner when the network failed;
/// [errorMessage] as plain text when the backend did.
class RetryRow extends StatelessWidget {
  final bool offline;
  final String offlineMessage;
  final String errorMessage;
  final VoidCallback onRetry;

  const RetryRow({
    super.key,
    required this.offline,
    required this.offlineMessage,
    required this.errorMessage,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 20, top: 12, right: 8),
      child: Row(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: offline
                  ? OfflineBanner(message: offlineMessage)
                  : Text(
                      errorMessage,
                      style: const TextStyle(fontSize: 13, color: AppColors.muted),
                    ),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(foregroundColor: AppColors.tomato),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
