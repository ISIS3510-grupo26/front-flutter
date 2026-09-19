import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class TasteProfileScreen extends StatefulWidget {
  const TasteProfileScreen({super.key});

  @override
  State<TasteProfileScreen> createState() => _TasteProfileScreenState();
}

class _TasteProfileScreenState extends State<TasteProfileScreen> {
  String _mainCuisine = 'Colombian';
  String _mealStyle = 'Quick & casual';

  final Set<String> _flavors = {
    'Savory',
    'Sweet',
  };

  final Set<String> _interests = {
    'Something new',
  };

  static const _cuisines = [
    'Colombian',
    'Italian',
    'Mexican',
    'Asian',
    'American',
    'Mediterranean',
    'Bakery & desserts',
    'Fast food',
  ];

  static const _flavorOptions = [
    'Savory',
    'Sweet',
    'Spicy',
    'Sour',
    'Mild',
  ];

  static const _mealStyles = [
    'Quick & casual',
    'Comfort food',
    'Healthy options',
    'Trying something new',
  ];

  static const _interestOptions = [
    'Something familiar',
    'Something new',
    'Healthy options',
    'Comfort food',
    'Good value',
  ];

  void _toggleSelection(Set<String> values, String value) {
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
        centerTitle: false,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(
            Icons.arrow_back,
            color: AppColors.espresso,
          ),
        ),
        title: const Text(
          'Taste Profile',
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
                    const _IntroCard(
                      icon: Icons.restaurant_menu,
                      title: 'Tell us what you like',
                      description:
                          'Your answers help us show places and dishes that better match your taste.',
                    ),
                    const SizedBox(height: 24),

                    const _QuestionTitle(
                      number: '01',
                      title: 'What kind of cuisine do you usually enjoy?',
                      subtitle: 'Choose the one you would pick most often.',
                    ),
                    const SizedBox(height: 12),

                    ..._cuisines.map(
                      (cuisine) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _SingleChoiceTile(
                          title: cuisine,
                          selected: _mainCuisine == cuisine,
                          onTap: () {
                            setState(() {
                              _mainCuisine = cuisine;
                            });
                          },
                        ),
                      ),
                    ),

                    const SizedBox(height: 22),

                    const _QuestionTitle(
                      number: '02',
                      title: 'Which flavors do you usually prefer?',
                      subtitle: 'Select as many as you want.',
                    ),
                    const SizedBox(height: 12),

                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _flavorOptions.map((flavor) {
                        return _SelectionChip(
                          label: flavor,
                          selected: _flavors.contains(flavor),
                          onTap: () => _toggleSelection(_flavors, flavor),
                        );
                      }).toList(),
                    ),

                    const SizedBox(height: 22),

                    const _QuestionTitle(
                      number: '03',
                      title: 'What kind of meals do you usually look for?',
                      subtitle: 'Pick the option that best describes you.',
                    ),
                    const SizedBox(height: 12),

                    ..._mealStyles.map(
                      (style) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _SingleChoiceTile(
                          title: style,
                          selected: _mealStyle == style,
                          onTap: () {
                            setState(() {
                              _mealStyle = style;
                            });
                          },
                        ),
                      ),
                    ),

                    const SizedBox(height: 22),

                    const _QuestionTitle(
                      number: '04',
                      title: 'What are you usually looking for?',
                      subtitle: 'These preferences can help personalize your recommendations.',
                    ),
                    const SizedBox(height: 12),

                    ..._interestOptions.map(
                      (interest) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _MultiChoiceTile(
                          title: interest,
                          selected: _interests.contains(interest),
                          onTap: () =>
                              _toggleSelection(_interests, interest),
                        ),
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

class _IntroCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;

  const _IntroCard({
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cream,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.tomatoLight,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.tomatoLight,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.restaurant_menu,
              color: AppColors.tomato,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontFamily: 'DMSans',
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.espresso,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: const TextStyle(
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

class _QuestionTitle extends StatelessWidget {
  final String number;
  final String title;
  final String subtitle;

  const _QuestionTitle({
    required this.number,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.tomato,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Text(
            number,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontFamily: 'DMSans',
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppColors.espresso,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 10.5,
                  color: AppColors.muted,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SingleChoiceTile extends StatelessWidget {
  final String title;
  final bool selected;
  final VoidCallback onTap;

  const _SingleChoiceTile({
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
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
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

class _MultiChoiceTile extends StatelessWidget {
  final String title;
  final bool selected;
  final VoidCallback onTap;

  const _MultiChoiceTile({
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

class _SelectionChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SelectionChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 13,
          vertical: 9,
        ),
        decoration: BoxDecoration(
          color: selected ? AppColors.tomato : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? AppColors.tomato
                : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: selected
                ? Colors.white
                : AppColors.espresso,
          ),
        ),
      ),
    );
  }
}