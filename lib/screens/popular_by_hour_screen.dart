import 'package:flutter/material.dart';

import '../models/hourly_ranking.dart';
import '../services/popularity_loader.dart';
import '../theme/app_colors.dart';
import '../widgets/popular_now_section.dart';

/// "See all" from Popular right now: the ranking of every hour with activity
/// over the last days, with the current hour marked.
class PopularByHourScreen extends StatefulWidget {
  final PopularityLoader loader;
  final ValueChanged<String>? onOpenSpot;

  const PopularByHourScreen({super.key, required this.loader, this.onOpenSpot});

  @override
  State<PopularByHourScreen> createState() => _PopularByHourScreenState();
}

class _PopularByHourScreenState extends State<PopularByHourScreen> {
  PopularByHourState _state = const PopularByHourLoading();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_state is! PopularByHourLoading) {
      setState(() => _state = const PopularByHourLoading());
    }
    final state = await widget.loader.loadByHours();
    if (mounted) setState(() => _state = state);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: AppBar(
        backgroundColor: AppColors.cream,
        foregroundColor: AppColors.espresso,
        elevation: 0,
        title: const Text(
          'Popular by hour',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: AppColors.espresso,
          ),
        ),
      ),
      body: switch (_state) {
        PopularByHourLoading() => const Center(
          child: CircularProgressIndicator(color: AppColors.tomato),
        ),
        PopularByHourFailed(reason: PopularityFailure.network) => _Message(
          "You're offline. The ranking by hour needs a connection; "
          'Popular right now on For You still shows the last one saved.',
          onRetry: _load,
        ),
        PopularByHourFailed(reason: PopularityFailure.server) => _Message(
          "Couldn't load the ranking by hour. Try again in a moment.",
          onRetry: _load,
        ),
        PopularByHourLoaded(:final report) when report.hours.isEmpty =>
          _Message('No student activity in the last ${report.days} days yet.'),
        PopularByHourLoaded(:final report, :final currentHour) =>
          ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            itemCount: report.hours.length,
            separatorBuilder: (_, _) => const SizedBox(height: 14),
            itemBuilder: (context, index) {
              final ranking = report.hours[index];
              return _HourCard(
                ranking: ranking,
                isNow: ranking.hour == currentHour,
                onOpenSpot: widget.onOpenSpot,
              );
            },
          ),
      },
    );
  }
}

class _HourCard extends StatelessWidget {
  final HourlyRanking ranking;
  final bool isNow;
  final ValueChanged<String>? onOpenSpot;

  const _HourCard({
    required this.ranking,
    required this.isNow,
    this.onOpenSpot,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isNow
              ? AppColors.tomato
              : AppColors.espresso.withValues(alpha: 0.05),
          width: isNow ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                ranking.label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.espresso,
                ),
              ),
              if (isNow)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.tomato,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'Now',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            activitySummary(ranking.totalPageViews, ranking.totalSearches),
            style: const TextStyle(fontSize: 12, color: AppColors.muted),
          ),
          const SizedBox(height: 8),
          for (final spot in ranking.spots)
            InkWell(
              onTap: onOpenSpot == null ? null : () => onOpenSpot!(spot.spotId),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    SizedBox(
                      width: 28,
                      child: Text(
                        '#${spot.rank}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: AppColors.tomato,
                        ),
                      ),
                    ),
                    Text(spot.emoji, style: const TextStyle(fontSize: 20)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            spot.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.espresso,
                            ),
                          ),
                          Text(
                            activitySummary(spot.pageViews, spot.searches),
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  final String text;
  final VoidCallback? onRetry;

  const _Message(this.text, {this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.muted, height: 1.4),
            ),
            if (onRetry case final retry?) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: retry,
                style: TextButton.styleFrom(foregroundColor: AppColors.tomato),
                child: const Text('Try again'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
