import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'taste_profile_screen.dart';
import 'dietary_preferences_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  static const _tasteTags = [
    'Burgers',
    'Vegetarian Friendly',
    'Medium Price',
    'Quick Bites',
    'Under 18.000 COP',
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ProfileHeader(onSettingsTap: () {}),
                  const SizedBox(height: 16),
                  const _ProfileIdentity(),
                  const SizedBox(height: 22),

                  _SectionTitle(
                    title: 'Taste Profile',
                    action: 'Edit',
                    onActionTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const TasteProfileScreen(),
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 10),

                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _tasteTags
                        .map((tag) => _TasteTag(label: tag))
                        .toList(),
                  ),

                  const SizedBox(height: 24),
                  const _StatsRow(),
                  const SizedBox(height: 24),
                  const _AchievementsSection(),
                  const SizedBox(height: 24),

                  _SettingsCard(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  final VoidCallback onSettingsTap;

  const _ProfileHeader({
    required this.onSettingsTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(
          child: Text(
            'Profile',
            style: TextStyle(
              fontFamily: 'DMSans',
              fontSize: 28,
              fontWeight: FontWeight.w900,
              color: AppColors.espresso,
              letterSpacing: -0.6,
            ),
          ),
        ),
        IconButton(
          onPressed: onSettingsTap,
          tooltip: 'Settings',
          icon: const Icon(
            Icons.settings_outlined,
            color: AppColors.espresso,
            size: 25,
          ),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(
            minWidth: 40,
            minHeight: 40,
          ),
        ),
      ],
    );
  }
}

class _ProfileIdentity extends StatelessWidget {
  const _ProfileIdentity();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Center(
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 86,
                height: 86,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.surface,
                  border: Border.all(
                    color: Colors.white,
                    width: 4,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x143A2A22),
                      blurRadius: 10,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.person,
                  size: 46,
                  color: Color(0xFF9D958F),
                ),
              ),
              Positioned(
                right: -1,
                bottom: 1,
                child: Container(
                  width: 23,
                  height: 23,
                  decoration: const BoxDecoration(
                    color: AppColors.mint,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check,
                    size: 15,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Julian Bierez',
          style: TextStyle(
            fontFamily: 'DMSans',
            fontSize: 20,
            fontWeight: FontWeight.w900,
            color: AppColors.espresso,
          ),
        ),
        const SizedBox(height: 3),
        const Text(
          'Universidad de los Andes',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: AppColors.muted,
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final String? action;
  final VoidCallback? onActionTap;

  const _SectionTitle({
    required this.title,
    this.action,
    this.onActionTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontFamily: 'DMSans',
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppColors.espresso,
            ),
          ),
        ),
        if (action != null)
          GestureDetector(
            onTap: onActionTap,
            child: Text(
              action!,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.tomato,
              ),
            ),
          ),
      ],
    );
  }
}

class _TasteTag extends StatelessWidget {
  final String label;

  const _TasteTag({
    required this.label,
  });

  bool get _isPrimary =>
      label == 'Burgers' ||
      label == 'Vegetarian Friendly' ||
      label == 'Medium Price';

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 7,
      ),
      decoration: BoxDecoration(
        color: _isPrimary ? AppColors.tomato : Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: _isPrimary
              ? AppColors.tomato
              : AppColors.border,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: _isPrimary
              ? Colors.white
              : AppColors.espresso,
        ),
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow();

  @override
  Widget build(BuildContext context) {
    const stats = [
      ('13', 'Places Tasted'),
      ('30', 'Saved Spots'),
      ('#3', 'Campus\nBadges'),
    ];

    return Row(
      children: [
        for (var i = 0; i < stats.length; i++) ...[
          Expanded(
            child: _StatCard(
              value: stats[i].$1,
              label: stats[i].$2,
              accent: i == 2,
            ),
          ),
          if (i < stats.length - 1)
            const SizedBox(width: 12),
        ],
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String value;
  final String label;
  final bool accent;

  const _StatCard({
    required this.value,
    required this.label,
    this.accent = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 80,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D3A2A22),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            value,
            style: TextStyle(
              fontFamily: 'DMSans',
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: accent
                  ? AppColors.tomato
                  : AppColors.espresso,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 9.5,
              height: 1.15,
              color: AppColors.muted,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _AchievementsSection extends StatelessWidget {
  const _AchievementsSection();

  @override
  Widget build(BuildContext context) {
    const badges = [
      _BadgeData(
        Icons.lunch_dining,
        'Burger Scout',
        true,
      ),
      _BadgeData(
        Icons.check,
        'Verified Diner',
        true,
      ),
      _BadgeData(
        Icons.emoji_events_outlined,
        'Budget Master',
        true,
      ),
      _BadgeData(
        Icons.lock_outline,
        'Night Owl',
        false,
      ),
      _BadgeData(
        Icons.lock_outline,
        'Coffee Fan',
        false,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Expanded(
              child: Text(
                'Achievements & Badges',
                style: TextStyle(
                  fontFamily: 'DMSans',
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.espresso,
                ),
              ),
            ),
            Text(
              '3 of 8 Unlocked',
              style: TextStyle(
                fontSize: 10,
                color: AppColors.muted,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 86,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: badges.length,
            separatorBuilder: (_, __) =>
                const SizedBox(width: 14),
            itemBuilder: (context, index) =>
                _BadgeItem(data: badges[index]),
          ),
        ),
      ],
    );
  }
}

class _BadgeData {
  final IconData icon;
  final String label;
  final bool unlocked;

  const _BadgeData(
    this.icon,
    this.label,
    this.unlocked,
  );
}

class _BadgeItem extends StatelessWidget {
  final _BadgeData data;

  const _BadgeItem({
    required this.data,
  });

  @override
  Widget build(BuildContext context) {
    final color = data.unlocked
        ? AppColors.tomato
        : AppColors.border;

    final iconColor = data.unlocked
        ? AppColors.espresso
        : AppColors.border;

    return SizedBox(
      width: 62,
      child: Column(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: data.unlocked
                  ? AppColors.cream
                  : Colors.white,
              border: Border.all(
                color: color,
                width: 1.5,
              ),
            ),
            child: Icon(
              data.icon,
              size: 23,
              color: iconColor,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            data.label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 9,
              height: 1.05,
              color: data.unlocked
                  ? AppColors.espresso
                  : AppColors.muted,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D3A2A22),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          _ProfileMenuRow(
            icon: Icons.tune,
            iconBackground: AppColors.tomatoLight,
            title: 'Dietary Preferences',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      const DietaryPreferencesScreen(),
                ),
              );
            },
          ),
          const Divider(
            height: 1,
            color: AppColors.border,
          ),
          const _ProfileMenuRow(
            icon: Icons.credit_card_outlined,
            iconBackground: AppColors.mintLight,
            title: 'Campus Dining Card (UniCard)',
            subtitle: 'Connected',
          ),
          const Divider(
            height: 1,
            color: AppColors.border,
          ),
          const _ProfileMenuRow(
            icon: Icons.notifications_none,
            iconBackground: AppColors.surface,
            title: 'Notifications',
          ),
        ],
      ),
    );
  }
}

class _ProfileMenuRow extends StatelessWidget {
  final IconData icon;
  final Color iconBackground;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  const _ProfileMenuRow({
    required this.icon,
    required this.iconBackground,
    required this.title,
    this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 13,
          ),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: iconBackground,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  icon,
                  size: 17,
                  color: AppColors.tomato,
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
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.espresso,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppColors.mint,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right,
                size: 20,
                color: AppColors.muted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}