import 'package:flutter/material.dart';

import '../models/spot.dart';
import '../services/nearby_favorites_loader.dart';
import '../theme/app_colors.dart';
import '../widgets/nearby_failure_view.dart';
import '../widgets/spot_card.dart';

sealed class _Filter {
  const _Filter();
}

final class _All extends _Filter {
  const _All();
}

final class _ByCategory extends _Filter {
  final SpotCategory category;

  const _ByCategory(this.category);
}

final class _Nearby extends _Filter {
  final NearbyState state;

  const _Nearby(this.state);
}

class SavedPlacesScreen extends StatefulWidget {
  final List<Spot> spots;
  final ValueChanged<String> onToggleSaved;
  final ValueChanged<String>? onOpenSpot;
  final NearbyFavoritesLoader nearbyLoader;

  const SavedPlacesScreen({
    super.key,
    required this.spots,
    required this.onToggleSaved,
    this.onOpenSpot,
    required this.nearbyLoader,
  });

  @override
  State<SavedPlacesScreen> createState() => _SavedPlacesScreenState();
}

class _SavedPlacesScreenState extends State<SavedPlacesScreen> {
  static const _maxWalk = NearbyFavoritesLoader.maxWalkMinutes;

  _Filter _filter = const _All();

  bool get _nearbyLoading =>
      switch (_filter) { _Nearby(state: NearbyLoading()) => true, _ => false };

  Future<void> _showNearby() async {
    if (_nearbyLoading) return;
    setState(() => _filter = const _Nearby(NearbyLoading()));
    final state = await widget.nearbyLoader.load();
    // Drop the result if the user switched filters while it was loading.
    if (mounted && _nearbyLoading) {
      setState(() => _filter = _Nearby(state));
    }
  }

  List<Spot> _visible(List<Spot> saved) => switch (_filter) {
        _All() => saved,
        _ByCategory(:final category) =>
          saved.where((s) => s.category == category).toList(),
        _Nearby(state: NearbyLoaded(:final walkMinutes)) => [
            for (final s in saved)
              if (walkMinutes[s.id] case final minutes?)
                s.copyWith(walkMinutes: minutes, distance: '$minutes min walk'),
          ]..sort((a, b) => a.walkMinutes.compareTo(b.walkMinutes)),
        _Nearby() => const [],
      };

  @override
  Widget build(BuildContext context) {
    final saved = widget.spots.where((s) => s.isSaved).toList();
    final visible = _visible(saved);
    return SafeArea(
      bottom: false,
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Saved Places',
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      color: AppColors.espresso,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Your favorite campus spots • ${saved.length} places saved',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.muted,
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 36,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        _FilterPill(
                          label: 'All Saved',
                          count: saved.length,
                          active: _filter is _All,
                          onTap: () => setState(() => _filter = const _All()),
                        ),
                        const SizedBox(width: 10),
                        _FilterPill(
                          label: 'Open • ≤$_maxWalk min',
                          count: switch (_filter) {
                            _Nearby(state: NearbyLoaded()) => visible.length,
                            _ => null,
                          },
                          active: _filter is _Nearby,
                          onTap: _showNearby,
                        ),
                        for (final category in SpotCategory.values) ...[
                          const SizedBox(width: 10),
                          _FilterPill(
                            label: category.label,
                            count: saved.where((s) => s.category == category).length,
                            active: switch (_filter) {
                              _ByCategory(category: final c) => c == category,
                              _ => false,
                            },
                            onTap: () =>
                                setState(() => _filter = _ByCategory(category)),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
              ),
            ),
          ),
          switch (_filter) {
            _Nearby(state: NearbyLoading()) => const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: CircularProgressIndicator(color: AppColors.tomato),
                ),
              ),
            _Nearby(state: NearbyFailed(:final failure)) => SliverFillRemaining(
                hasScrollBody: false,
                child: NearbyFailureView(
                  failure: failure,
                  onRetry: _showNearby,
                  onOpenSettings: widget.nearbyLoader.openLocationSettings,
                ),
              ),
            _ when visible.isEmpty => SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      _filter is _Nearby
                          ? 'None of your saved places are open within a '
                              '$_maxWalk-minute walk right now.'
                          : 'No saved places in this category yet.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.muted),
                    ),
                  ),
                ),
              ),
            _ => SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
                sliver: SliverList.separated(
                  itemCount: visible.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 14),
                  itemBuilder: (context, index) {
                    final spot = visible[index];
                    return SpotCard(
                      spot: spot,
                      onToggleSaved: () => widget.onToggleSaved(spot.id),
                    onTap: widget.onOpenSpot == null ? null : () => widget.onOpenSpot!(spot.id),
                    );
                  },
                ),
              ),
          },
        ],
      ),
    );
  }
}

class _FilterPill extends StatelessWidget {
  final String label;
  final int? count;
  final bool active;
  final VoidCallback onTap;

  const _FilterPill({
    required this.label,
    required this.count,
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
