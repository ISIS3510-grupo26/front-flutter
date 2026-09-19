import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class PlaceDetailScreen extends StatefulWidget {
  const PlaceDetailScreen({super.key});

  @override
  State<PlaceDetailScreen> createState() => _PlaceDetailScreenState();
}

class _PlaceDetailScreenState extends State<PlaceDetailScreen> {
  bool _saved = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cream,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back, color: AppColors.espresso),
                  ),
                  const Expanded(
                    child: Text(
                      _name,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.espresso,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => setState(() => _saved = !_saved),
                    icon: Icon(
                      _saved ? Icons.favorite : Icons.favorite_border,
                      color: AppColors.tomato,
                    ),
                  ),
                  const IconButton(
                    onPressed: null,
                    icon: Icon(Icons.share_outlined, color: AppColors.espresso),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            sliver: SliverList.list(
              children: [
                SizedBox(
                  height: 200,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            color: _emojiBackground,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          alignment: Alignment.center,
                          child: const Text(_emoji, style: TextStyle(fontSize: 72)),
                        ),
                      ),
                      const Positioned(
                        left: 12,
                        top: 12,
                        child: _TomatoPill(label: '$_affinity% Taste Match'),
                      ),
                      Positioned(
                        right: 12,
                        top: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppColors.card,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.star, size: 14, color: AppColors.tomato),
                              const SizedBox(width: 4),
                              const Text(
                                '$_rating',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.espresso,
                                ),
                              ),
                              Text(
                                ' ($_totalReviews)',
                                style: const TextStyle(fontSize: 12, color: AppColors.muted),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        left: 12,
                        bottom: 12,
                        child: Row(
                          children: [
                            if (_acceptsCampusCard)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: AppColors.mint,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.check, size: 14, color: Colors.white),
                                    SizedBox(width: 4),
                                    Text(
                                      'Campus Card Accepted',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            if (_acceptsCampusCard) const SizedBox(width: 8),
                            if (_veggieFriendly)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: AppColors.card,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: const Text(
                                  'Veggie Friendly',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.espresso,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        _name,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: AppColors.espresso,
                        ),
                      ),
                    ),
                    if (_isOpenNow)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.mintLight,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.circle, size: 8, color: AppColors.mint),
                            SizedBox(width: 6),
                            Text(
                              'Open Now',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppColors.mint,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  _subtitle,
                  style: TextStyle(fontSize: 13, color: AppColors.muted),
                ),
                const SizedBox(height: 16),
                Row(
                  children: const [
                    Expanded(
                      child: _StatTile(icon: Icons.directions_walk, label: 'Distance', value: _distanceLabel),
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: _StatTile(icon: Icons.access_time, label: 'Wait Time', value: _waitTimeLabel),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: const [
                    Expanded(
                      child: _StatTile(icon: Icons.attach_money, label: 'Price Range', value: _priceRangeLabel),
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: _StatTile(icon: Icons.calendar_today, label: 'Hours Today', value: _hoursTodayLabel),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.tomatoLight,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Why it fits your profile',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.tomato,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        _whyItFits,
                        style: TextStyle(fontSize: 13, height: 1.5, color: AppColors.espresso),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          SizedBox(
                            width: 56,
                            height: 24,
                            child: Stack(
                              children: const [
                                Positioned(left: 0, child: _Avatar('JL')),
                                Positioned(left: 16, child: _Avatar('M')),
                                Positioned(left: 32, child: _Avatar('AR')),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Verified student community consensus',
                              style: TextStyle(fontSize: 11, color: AppColors.muted),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const Center(
                  child: Text(
                    'Scroll down for Campus Menu & Reviews',
                    style: TextStyle(fontSize: 12, color: AppColors.muted),
                  ),
                ),
                const SizedBox(height: 4),
                const Center(
                  child: Icon(Icons.keyboard_arrow_down, color: AppColors.muted),
                ),
              ],
            ),
          ),
        ],
      ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.tomato,
                disabledBackgroundColor: AppColors.tomato,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.explore_outlined, color: Colors.white),
                  SizedBox(width: 8),
                  Text(
                    'Get Walking Directions ($_walkMinutes min)',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _StatTile({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.tomatoLight,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppColors.tomato),
              const SizedBox(width: 8),
              Text(label, style: const TextStyle(fontSize: 11, color: AppColors.muted)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.espresso),
          ),
        ],
      ),
    );
  }
}

class _TomatoPill extends StatelessWidget {
  final String label;

  const _TomatoPill({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.tomato,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String initials;

  const _Avatar(this.initials);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.surface,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.cream, width: 2),
      ),
      child: Text(
        initials,
        style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: AppColors.espresso),
      ),
    );
  }
}

const _emoji = '🍔';
const _emojiBackground = AppColors.tomatoLight;
const _name = 'La Esquina Burger Lab';
const _subtitle = 'Artisanal Smash Burgers • Craft Sauces • Student Perks';
const _affinity = 98;
const _rating = 4.8;
const _totalReviews = 142;
const _distanceLabel = '180m (3 min walk)';
const _waitTimeLabel = '8-12 min';
const _priceRangeLabel = '\$16k - \$22k COP';
const _hoursTodayLabel = '11:00 AM - 7:30 PM';
const _isOpenNow = true;
const _acceptsCampusCard = true;
const _veggieFriendly = true;
const _walkMinutes = 3;
const _whyItFits =
    'Based on 47 students in Engineering & Tech with Vegetarian and '
    'Artisanal Burger preferences: 96% rated value-for-money 5/5, and 92% '
    'praised the garlic sauce and rapid turnaround between class blocks.';
