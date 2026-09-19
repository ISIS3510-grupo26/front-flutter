import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class DietaryPreferencesScreen extends StatefulWidget {
  const DietaryPreferencesScreen({super.key});

  @override
  State<DietaryPreferencesScreen> createState() =>
      _DietaryPreferencesScreenState();
}

class _DietaryPreferencesScreenState
    extends State<DietaryPreferencesScreen> {
  String _diet = 'No specific diet';

  final Set<String> _avoid = {
    'Very spicy food',
  };

  final Set<String> _allergies = {};

  static const _dietOptions = [
    'No specific diet',
    'Vegetarian',
    'Vegan',
    'Pescatarian',
  ];

  static const _avoidOptions = [
    'Meat',
    'Dairy',
    'Gluten',
    'Seafood',
    'Nuts',
    'Very spicy food',
  ];

  static const _allergyOptions = [
    'Dairy',
    'Eggs',
    'Gluten',
    'Peanuts',
    'Tree nuts',
    'Seafood',
  ];

  void _toggle(Set<String> values, String value) {
    setState(() {
      if (values.contains(value)) {
        values.remove(value);
      } else {
        values.add(value);
      }
    });
  }

  void _save() {
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(
            Icons.arrow_back,
            color: AppColors.espresso,
          ),
        ),
        title: const Text(
          'Dietary Preferences',
          style: TextStyle(
            fontFamily: 'DMSans',
            fontSize: 22,
            fontWeight: FontWeight.w900,
            color: AppColors.espresso,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _DietaryIntro(),
                    const SizedBox(height: 24),

                    const _SectionHeader(
                      title: 'Eating style',
                      subtitle:
                          'Do you currently follow a specific type of diet?',
                    ),
                    const SizedBox(height: 12),

                    ..._dietOptions.map(
                      (diet) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _DietOption(
                          title: diet,
                          selected: _diet == diet,
                          onTap: () {
                            setState(() {
                              _diet = diet;
                            });
                          },
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    const _SectionHeader(
                      title: 'Foods you avoid',
                      subtitle:
                          'Select anything you would rather not see in your recommendations.',
                    ),
                    const SizedBox(height: 12),

                    ..._avoidOptions.map(
                      (food) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _DietCheckRow(
                          title: food,
                          selected: _avoid.contains(food),
                          onTap: () => _toggle(_avoid, food),
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    const _SectionHeader(
                      title: 'Allergies or sensitivities',
                      subtitle:
                          'This information can help us highlight relevant dish information.',
                    ),
                    const SizedBox(height: 12),

                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.cream,
                        borderRadius: BorderRadius.circular(13),
                        border: Border.all(
                          color: AppColors.tomatoLight,
                        ),
                      ),
                      child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 19,
                            color: AppColors.tomato,
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'This is only used to personalize recommendations. Always check the restaurant information for possible allergens.',
                              style: TextStyle(
                                fontSize: 10.5,
                                height: 1.4,
                                color: AppColors.muted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),

                    ..._allergyOptions.map(
                      (allergy) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _DietCheckRow(
                          title: allergy,
                          selected: _allergies.contains(allergy),
                          onTap: () => _toggle(_allergies, allergy),
                        ),
                      ),
                    ),

                    const SizedBox(height: 10),

                    const Text(
                      'You can change these preferences at any time.',
                      style: TextStyle(
                        fontSize: 10.5,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(
                  top: BorderSide(
                    color: AppColors.border,
                  ),
                ),
              ),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.tomato,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(13),
                    ),
                  ),
                  child: const Text(
                    'Save preferences',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DietaryIntro extends StatelessWidget {
  const _DietaryIntro();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.mintLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.mint.withOpacity(0.35),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.tune,
              color: AppColors.mint,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Make recommendations fit you',
                  style: TextStyle(
                    fontFamily: 'DMSans',
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.espresso,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Let us know about your dietary needs so we can help you find suitable options.',
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.4,
                    color: AppColors.muted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SectionHeader({
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontFamily: 'DMSans',
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: AppColors.espresso,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: const TextStyle(
            fontSize: 10.5,
            height: 1.35,
            color: AppColors.muted,
          ),
        ),
      ],
    );
  }
}

class _DietOption extends StatelessWidget {
  final String title;
  final bool selected;
  final VoidCallback onTap;

  const _DietOption({
    required this.title,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 14,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? AppColors.mint
                  : AppColors.border,
              width: selected ? 1.5 : 1,
            ),
            color: selected
                ? AppColors.mintLight
                : Colors.white,
          ),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected
                      ? AppColors.mint
                      : AppColors.border,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight:
                        selected ? FontWeight.w700 : FontWeight.w500,
                    color: AppColors.espresso,
                  ),
                ),
              ),
              Icon(
                selected
                    ? Icons.check_circle
                    : Icons.circle_outlined,
                size: 20,
                color: selected
                    ? AppColors.mint
                    : AppColors.border,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DietCheckRow extends StatelessWidget {
  final String title;
  final bool selected;
  final VoidCallback onTap;

  const _DietCheckRow({
    required this.title,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 13,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? AppColors.tomato
                  : AppColors.border,
              width: selected ? 1.5 : 1,
            ),
            color: selected
                ? AppColors.cream
                : Colors.white,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight:
                        selected ? FontWeight.w700 : FontWeight.w500,
                    color: AppColors.espresso,
                  ),
                ),
              ),
              Icon(
                selected
                    ? Icons.check_box
                    : Icons.check_box_outline_blank,
                size: 20,
                color: selected
                    ? AppColors.tomato
                    : AppColors.border,
              ),
            ],
          ),
        ),
      ),
    );
  }
}