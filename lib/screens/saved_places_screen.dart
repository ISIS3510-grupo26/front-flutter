import 'package:flutter/material.dart';

import '../models/spot.dart';
import '../services/favorites_controller.dart';
import '../services/nearby_favorites_loader.dart';
import '../theme/app_colors.dart';
import '../widgets/count_pill.dart';
import '../widgets/nearby_failure_view.dart';
import '../widgets/offline_banner.dart';
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

  /// Until the server answers there are no saved places to show, so the
  /// empty list says why instead of claiming there are none.
  final FavoritesSync sync;
  final VoidCallback onRetrySync;

  /// When the copy on the phone came from the server; shown while offline.
  final DateTime? offlineSince;

  /// Spots changed offline that the server doesn't have yet.
  final Set<String> pendingIds;

  const SavedPlacesScreen({
    super.key,
    required this.spots,
    required this.onToggleSaved,
    this.onOpenSpot,
    required this.nearbyLoader,
    this.sync = FavoritesSync.loaded,
    required this.onRetrySync,
    this.offlineSince,
    this.pendingIds = const {},
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
                        CountPill(
                          label: 'All Saved',
                          count: saved.length,
                          active: _filter is _All,
                          onTap: () => setState(() => _filter = const _All()),
                        ),
                        const SizedBox(width: 10),
                        CountPill(
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
                          CountPill(
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
                  if (widget.sync == FavoritesSync.offline &&
                      saved.isNotEmpty &&
                      _filter is! _Nearby) ...[
                    const SizedBox(height: 10),
                    OfflineBanner(
                      message: switch (widget.offlineSince) {
                        final at? => 'Offline · saved places from ${hourMinute(at)}',
                        null => 'Offline · saved places on this phone',
                      },
                    ),
                  ],
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
            // A server error is not "offline": the copy on the phone isn't
            // shown as if it were current, the student gets the error and Retry.
            _ when _filter is! _Nearby && widget.sync == FavoritesSync.failed =>
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          "The server couldn't load your saved places right now.",
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.muted),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: widget.onRetrySync,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            _ when visible.isEmpty &&
                    _filter is! _Nearby &&
                    widget.sync == FavoritesSync.loading =>
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: CircularProgressIndicator(color: AppColors.tomato),
                ),
              ),
            _ when saved.isEmpty &&
                    _filter is! _Nearby &&
                    widget.sync == FavoritesSync.offline =>
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      "Offline · your saved places show up when you're back online",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.muted),
                    ),
                  ),
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
                    final card = SpotCard(
                      spot: spot,
                      onToggleSaved: () => widget.onToggleSaved(spot.id),
                    onTap: widget.onOpenSpot == null ? null : () => widget.onOpenSpot!(spot.id),
                    );
                    if (!widget.pendingIds.contains(spot.id)) return card;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        card,
                        const Padding(
                          padding: EdgeInsets.only(top: 6, left: 4),
                          child: Row(
                            children: [
                              Icon(Icons.sync, size: 13, color: AppColors.muted),
                              SizedBox(width: 4),
                              Text(
                                'Waiting to sync',
                                style: TextStyle(fontSize: 11, color: AppColors.muted),
                              ),
                            ],
                          ),
                        ),
                      ],
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
