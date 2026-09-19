import 'dart:math';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'place_detail_screen.dart';

class TasteMapScreen extends StatefulWidget {
  const TasteMapScreen({super.key});

  @override
  State<TasteMapScreen> createState() => _TasteMapScreenState();
}

class _TasteMapScreenState extends State<TasteMapScreen> {
  int _selected = 0;
  final List<_MapSpot> _spots = _sampleMapSpots;

  @override
  Widget build(BuildContext context) {
    final selected = _spots[_selected];
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Taste Map',
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    color: AppColors.espresso,
                    letterSpacing: -0.5,
                  ),
                ),
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: AppColors.surface,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.tune, color: AppColors.espresso),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
            child: Container(
              height: 52,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  const Icon(Icons.search, color: AppColors.muted, size: 20),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: TextField(
                      readOnly: true,
                      style: TextStyle(fontSize: 14, color: AppColors.espresso),
                      decoration: InputDecoration.collapsed(
                        hintText: 'Search food stalls, trucks, campus spots...',
                        hintStyle: TextStyle(fontSize: 14, color: AppColors.muted),
                      ),
                    ),
                  ),
                  const Icon(Icons.mic_none, color: AppColors.muted, size: 20),
                ],
              ),
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                    final w = constraints.maxWidth;
                    final h = constraints.maxHeight;
                    return Stack(
                      children: [
                        Container(color: const Color(0xFFD9EDE2)),
                        Positioned(
                          left: w * 0.05,
                          top: h * 0.08,
                          child: _zoneBlock(120, 90, const Color(0xFFE4D5CC)),
                        ),
                        Positioned(
                          left: w * 0.45,
                          top: h * 0.05,
                          child: _zoneBlock(140, 70, const Color(0xFFF2CFC6)),
                        ),
                        Positioned(
                          left: w * 0.7,
                          top: h * 0.3,
                          child: _zoneBlock(90, 110, const Color(0xFFE4D5CC)),
                        ),
                        Positioned(
                          left: w * 0.08,
                          top: h * 0.45,
                          child: _zoneBlock(100, 80, const Color(0xFFF2CFC6)),
                        ),
                        Positioned(
                          left: w * 0.4,
                          top: h * 0.55,
                          child: _zoneBlock(130, 95, const Color(0xFFE4D5CC)),
                        ),
                        Positioned(
                          left: w * 0.65,
                          top: h * 0.68,
                          child: _zoneBlock(110, 75, const Color(0xFFF2CFC6)),
                        ),
                        Positioned(
                          left: 0,
                          top: h * 0.27,
                          child: Container(width: w, height: 14, color: AppColors.cream),
                        ),
                        Positioned(
                          left: 0,
                          top: h * 0.62,
                          child: Container(width: w, height: 14, color: AppColors.cream),
                        ),
                        Positioned(
                          left: w * 0.32,
                          top: 0,
                          child: Container(width: 14, height: h, color: AppColors.cream),
                        ),
                        Positioned(
                          left: w * 0.78,
                          top: 0,
                          child: Container(width: 14, height: h, color: AppColors.cream),
                        ),
                        const Positioned(left: 16, top: 16, child: _ZoneLabel('SCIENCE QUAD')),
                        const Positioned(right: 16, top: 40, child: _ZoneLabel('ENGINEERING HUB')),
                        const Positioned(left: 16, bottom: 140, child: _ZoneLabel('STUDENT UNION')),
                        const Positioned(right: 16, bottom: 110, child: _ZoneLabel('SPORTS ARENA')),
                        Positioned(
                          top: 16,
                          right: 16,
                          child: Container(
                            width: 44,
                            height: 44,
                            alignment: Alignment.center,
                            decoration: const BoxDecoration(
                              color: AppColors.card,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.navigation_outlined, color: AppColors.espresso),
                          ),
                        ),
                        for (var i = 0; i < _spots.length; i++)
                          Positioned(
                            left: _spots[i].dx * w - 28,
                            top: _spots[i].dy * h - 18,
                            child: _Pin(
                              spot: _spots[i],
                              selected: i == _selected,
                              onTap: () => setState(() => _selected = i),
                            ),
                          ),
                        Positioned(
                          left: 16,
                          right: 16,
                          bottom: 16,
                          child: _SelectedPlaceCard(spot: selected),
                        ),
                      ],
                    );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _zoneBlock(double width, double height, Color color) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
      ),
    );
  }
}

class _ZoneLabel extends StatelessWidget {
  final String label;

  const _ZoneLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.2,
        color: AppColors.muted,
      ),
    );
  }
}

class _Pin extends StatelessWidget {
  final _MapSpot spot;
  final bool selected;
  final VoidCallback onTap;

  const _Pin({required this.spot, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.tomato : AppColors.espresso;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(999),
              border: selected ? Border.all(color: Colors.white, width: 3) : null,
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: AppColors.espresso.withValues(alpha: 0.25),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(spot.emoji, style: const TextStyle(fontSize: 14)),
                const SizedBox(width: 4),
                Text(
                  '${spot.affinity}%',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          Transform.translate(
            offset: const Offset(0, -3),
            child: Transform.rotate(
              angle: pi / 4,
              child: Container(width: 8, height: 8, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectedPlaceCard extends StatelessWidget {
  final _MapSpot spot;

  const _SelectedPlaceCard({required this.spot});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 56,
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(spot.emoji, style: const TextStyle(fontSize: 28)),
              ),
              Positioned(
                top: -6,
                right: -6,
                child: Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: AppColors.tomato,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '${spot.rank}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        spot.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: AppColors.espresso,
                        ),
                      ),
                    ),
                    const Icon(Icons.star, size: 14, color: AppColors.tomato),
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
                const SizedBox(height: 4),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: spot.price,
                        style: const TextStyle(fontSize: 12, color: AppColors.espresso),
                      ),
                      const TextSpan(text: ' • ', style: TextStyle(color: AppColors.muted)),
                      TextSpan(
                        text: spot.walkLabel,
                        style: const TextStyle(fontSize: 12, color: AppColors.muted),
                      ),
                      const TextSpan(text: ' • ', style: TextStyle(color: AppColors.muted)),
                      TextSpan(
                        text: '${spot.affinity}% Taste Match',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppColors.mint,
                        ),
                      ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const _MetaPill(label: 'Quick Line', background: AppColors.tomatoLight, foreground: AppColors.tomato),
                    const SizedBox(width: 8),
                    Flexible(
                      child: _MetaPill(label: spot.location, background: AppColors.surface, foreground: AppColors.espresso),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PlaceDetailScreen()),
            ),
            child: Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: AppColors.tomato,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.chevron_right, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  final String label;
  final Color background;
  final Color foreground;

  const _MetaPill({required this.label, required this.background, required this.foreground});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: foreground),
      ),
    );
  }
}

class _MapSpot {
  final String emoji;
  final String name;
  final int affinity;
  final double rating;
  final String price;
  final String walkLabel;
  final String location;
  final int rank;
  final double dx;
  final double dy;

  const _MapSpot({
    required this.emoji,
    required this.name,
    required this.affinity,
    required this.rating,
    required this.price,
    required this.walkLabel,
    required this.location,
    required this.rank,
    required this.dx,
    required this.dy,
  });
}

const List<_MapSpot> _sampleMapSpots = [
  _MapSpot(
    emoji: '🍔',
    name: 'La Esquina Burger Lab',
    affinity: 98,
    rating: 4.8,
    price: '\$16k - \$22k COP',
    walkLabel: '3 min walk',
    location: 'North Quad Plaza',
    rank: 1,
    dx: 0.28,
    dy: 0.22,
  ),
  _MapSpot(
    emoji: '🥗',
    name: 'Green Bowl Co.',
    affinity: 91,
    rating: 4.0,
    price: '\$15k COP',
    walkLabel: '3 min walk',
    location: 'Central Library 1F',
    rank: 2,
    dx: 0.62,
    dy: 0.15,
  ),
  _MapSpot(
    emoji: '☕',
    name: 'Nitro Coffee & Brew',
    affinity: 87,
    rating: 4.6,
    price: '\$8k COP',
    walkLabel: '5 min walk',
    location: 'Engineering Hub',
    rank: 3,
    dx: 0.8,
    dy: 0.45,
  ),
  _MapSpot(
    emoji: '🌮',
    name: 'Taco Fiesta Truck',
    affinity: 84,
    rating: 4.5,
    price: '\$12k COP',
    walkLabel: '6 min walk',
    location: 'Student Union',
    rank: 4,
    dx: 0.18,
    dy: 0.65,
  ),
  _MapSpot(
    emoji: '🍜',
    name: 'Ramen Corner',
    affinity: 79,
    rating: 4.3,
    price: '\$18k COP',
    walkLabel: '8 min walk',
    location: 'Sports Arena',
    rank: 5,
    dx: 0.55,
    dy: 0.78,
  ),
];
