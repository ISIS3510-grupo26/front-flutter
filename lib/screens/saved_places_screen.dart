import 'package:flutter/material.dart';

import '../models/spot.dart';
import '../theme/app_colors.dart';
import '../widgets/spot_card.dart';

class SavedPlacesScreen extends StatefulWidget {
  final List<Spot> spots;
  final ValueChanged<String> onToggleSaved;

  const SavedPlacesScreen({
    super.key,
    required this.spots,
    required this.onToggleSaved,
  });

  @override
  State<SavedPlacesScreen> createState() => _SavedPlacesScreenState();
}

class _SavedPlacesScreenState extends State<SavedPlacesScreen> {
  SpotCategory? _selectedCategory;

  List<Spot> get _savedSpots => widget.spots.where((s) => s.isSaved).toList();

  List<Spot> get _filteredSpots {
    final saved = _savedSpots;
    if (_selectedCategory == null) return saved;
    return saved.where((s) => s.category == _selectedCategory).toList();
  }

  int _countFor(SpotCategory category) =>
      _savedSpots.where((s) => s.category == category).length;

  @override
  Widget build(BuildContext context) {
    final saved = _savedSpots;
    final filtered = _filteredSpots;
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
                          active: _selectedCategory == null,
                          onTap: () => setState(() => _selectedCategory = null),
                        ),
                        const SizedBox(width: 10),
                        _FilterPill(
                          label: SpotCategory.foodTrucks.label,
                          count: _countFor(SpotCategory.foodTrucks),
                          active: _selectedCategory == SpotCategory.foodTrucks,
                          onTap: () => setState(
                              () => _selectedCategory = SpotCategory.foodTrucks),
                        ),
                        const SizedBox(width: 10),
                        _FilterPill(
                          label: SpotCategory.studySpots.label,
                          count: _countFor(SpotCategory.studySpots),
                          active: _selectedCategory == SpotCategory.studySpots,
                          onTap: () => setState(
                              () => _selectedCategory = SpotCategory.studySpots),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
              ),
            ),
          ),
          if (filtered.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Text(
                  'No saved places in this category yet.',
                  style: TextStyle(color: AppColors.muted),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
              sliver: SliverList.separated(
                itemCount: filtered.length,
                separatorBuilder: (_, _) => const SizedBox(height: 14),
                itemBuilder: (context, index) {
                  final spot = filtered[index];
                  return SpotCard(
                    spot: spot,
                    onToggleSaved: () => widget.onToggleSaved(spot.id),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _FilterPill extends StatelessWidget {
  final String label;
  final int count;
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
        ),
      ),
    );
  }
}
