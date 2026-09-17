import 'package:flutter/material.dart';

import '../models/spot.dart';
import '../theme/app_colors.dart';

/// The single card representation used everywhere a [Spot] is shown, in
/// both the For You feed and Saved Places. Tapping the heart toggles
/// [Spot.isSaved] — which is the same flag Saved Places filters on — so
/// saving a spot from the feed makes it show up there immediately.
class SpotCard extends StatelessWidget {
  final Spot spot;
  final VoidCallback onToggleSaved;

  const SpotCard({
    super.key,
    required this.spot,
    required this.onToggleSaved,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.espresso.withValues(alpha: 0.05)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F3A2A22),
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (spot.isSaved)
                _Pill(
                  color: AppColors.mint,
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check, size: 14, color: Colors.white),
                      SizedBox(width: 4),
                      Text(
                        'Saved',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                )
              else
                _Pill(
                  color: AppColors.tomato,
                  child: Text(
                    '${spot.affinityPercent}%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              IconButton(
                onPressed: onToggleSaved,
                tooltip: spot.isSaved ? 'Remove from saved' : 'Save this spot',
                icon: Icon(
                  spot.isSaved ? Icons.favorite : Icons.favorite_border,
                  color: AppColors.tomato,
                ),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 64,
                height: 64,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: spot.emojiBackground,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: spot.emojiBorder),
                ),
                child: Text(spot.emoji, style: const TextStyle(fontSize: 28)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      spot.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.espresso,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      spot.subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: AppColors.muted,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.star, size: 14, color: AppColors.tomato),
                            const SizedBox(width: 2),
                            Text(
                              '${spot.rating}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.tomato,
                              ),
                            ),
                          ],
                        ),
                        const _MetaDot(),
                        Text(
                          spot.price,
                          style: const TextStyle(fontSize: 12, color: AppColors.espresso),
                        ),
                        const _MetaDot(),
                        Text(
                          spot.distance,
                          style: const TextStyle(fontSize: 12, color: AppColors.muted),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.surface.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(12),
              border: const Border(
                left: BorderSide(color: AppColors.tomato, width: 4),
              ),
            ),
            child: Text.rich(
              TextSpan(
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.espresso,
                  height: 1.4,
                ),
                children: [
                  TextSpan(
                    text: '${spot.noteLabel}: ',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppColors.tomato,
                    ),
                  ),
                  TextSpan(text: spot.note),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final Color color;
  final Widget child;

  const _Pill({required this.color, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: child,
    );
  }
}

class _MetaDot extends StatelessWidget {
  const _MetaDot();

  @override
  Widget build(BuildContext context) {
    return const Text(' • ', style: TextStyle(color: AppColors.muted));
  }
}
