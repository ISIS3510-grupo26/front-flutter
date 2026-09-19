import 'package:flutter/material.dart';

import '../data/spots_data.dart';
import '../models/spot.dart';
import '../theme/app_colors.dart';
import '../widgets/campus_bottom_nav_bar.dart';
import '../widgets/coming_soon_view.dart';
import 'for_you_screen.dart';
import 'saved_places_screen.dart';
import 'taste_map_screen.dart';

/// Hosts the four main tabs and owns the single list of [Spot]s shared by
/// the For You feed and Saved Places, so toggling the heart on a card in
/// either screen updates the same underlying saved state.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  List<Spot> _spots = List.of(sampleSpots);

  void _toggleSaved(String id) {
    setState(() {
      _spots = [
        for (final spot in _spots)
          if (spot.id == id) spot.copyWith(isSaved: !spot.isSaved) else spot,
      ];
    });
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      ForYouScreen(spots: _spots, onToggleSaved: _toggleSaved),
      const TasteMapScreen(),
      SavedPlacesScreen(spots: _spots, onToggleSaved: _toggleSaved),
      const ComingSoonView(title: 'Profile', icon: Icons.person_outline),
    ];

    return Scaffold(
      backgroundColor: AppColors.cream,
      body: IndexedStack(index: _index, children: screens),
      bottomNavigationBar: CampusBottomNavBar(
        currentIndex: _index,
        onTap: (index) => setState(() => _index = index),
      ),
    );
  }
}
