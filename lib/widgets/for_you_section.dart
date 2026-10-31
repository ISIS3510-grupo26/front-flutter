import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'offline_banner.dart';

/// The pieces every ranked section of For You is made of ("Best for you
/// right now", "Popular right now"), so both look and behave the same.

/// Thin bar while the section loads.
class SectionLoadingBar extends StatelessWidget {
  const SectionLoadingBar({super.key});

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.fromLTRB(20, 16, 20, 0),
        child: LinearProgressIndicator(
          minHeight: 2,
          color: AppColors.tomato,
          backgroundColor: AppColors.tomatoLight,
        ),
      );
}

/// Title, one line of context and, with [onLink], a link to see more.
class SectionHeader extends StatelessWidget {
  final String title;
  final String summary;
  final String? linkLabel;
  final VoidCallback? onLink;

  const SectionHeader({
    super.key,
    required this.title,
    required this.summary,
    this.linkLabel,
    this.onLink,
  });

  @override
  Widget build(BuildContext context) {
    final link = linkLabel;
    return InkWell(
      onTap: onLink,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: AppColors.espresso,
                    ),
                  ),
                  Text(
                    summary,
                    style: const TextStyle(fontSize: 12, color: AppColors.muted),
                  ),
                ],
              ),
            ),
            if (link != null && onLink != null) ...[
              Text(
                link,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppColors.tomato,
                ),
              ),
              const Icon(Icons.chevron_right, size: 18, color: AppColors.tomato),
            ],
          ],
        ),
      ),
    );
  }
}

/// "Offline · data from HH:mm" above a section showing data saved on the phone.
class SectionOfflineBanner extends StatelessWidget {
  final DateTime savedAt;

  const SectionOfflineBanner({super.key, required this.savedAt});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
        child: OfflineBanner(message: 'Offline · data from ${hourMinute(savedAt)}'),
      );
}

/// Ranked cards side by side. A section has five cards at most, so a Row is
/// enough, and IntrinsicHeight makes every card as tall as the tallest one.
class RankedSpotRow extends StatelessWidget {
  final List<RankedSpotCard> cards;

  const RankedSpotRow({super.key, required this.cards});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (index, card) in cards.indexed) ...[
              if (index > 0) const SizedBox(width: 10),
              card,
            ],
          ],
        ),
      ),
    );
  }
}

/// One place in a ranked section: its position, emoji and name, the line
/// that explains its position ([detail]), an optional smaller [note] and an
/// optional [tag] at the bottom.
class RankedSpotCard extends StatelessWidget {
  final int rank;
  final String emoji;
  final String name;
  final String detail;
  final String? note;
  final String? tag;
  final VoidCallback? onTap;

  const RankedSpotCard({
    super.key,
    required this.rank,
    required this.emoji,
    required this.name,
    required this.detail,
    this.note,
    this.tag,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(18);
    final tag = this.tag;
    return SizedBox(
      width: 150,
      child: Material(
        color: AppColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: const BorderSide(color: AppColors.border),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    RankBadge(rank: rank),
                    const Spacer(),
                    Text(emoji, style: const TextStyle(fontSize: 22)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AppColors.espresso,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  detail,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.espresso,
                  ),
                ),
                if (note case final note?)
                  Text(note, style: const TextStyle(fontSize: 10, color: AppColors.muted)),
                if (tag != null) ...[
                  const Spacer(),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.tomato,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      tag,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// '#1' in a circle: tomato for the first, espresso for the second, light
/// for the rest.
class RankBadge extends StatelessWidget {
  final int rank;
  final double size;

  const RankBadge({super.key, required this.rank, this.size = 26});

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = switch (rank) {
      1 => (AppColors.tomato, Colors.white),
      2 => (AppColors.espresso, Colors.white),
      _ => (AppColors.tomatoLight, AppColors.tomato),
    };
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: background, shape: BoxShape.circle),
      child: Text(
        '#$rank',
        style: TextStyle(
          fontSize: size * 0.42,
          fontWeight: FontWeight.w800,
          color: foreground,
        ),
      ),
    );
  }
}
