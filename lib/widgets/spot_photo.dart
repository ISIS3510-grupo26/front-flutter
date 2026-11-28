import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/spot.dart';
import '../services/restaurant_photos.dart';
import '../theme/app_colors.dart';

/// The square with the photo of a place, or its emoji while it loads, if it
/// fails (no internet and never downloaded) or if the place has no photo.
class SpotPhoto extends StatelessWidget {
  final String? imageUrl;
  final String emoji;
  final double size;
  final double radius;
  final Color background;
  final Color border;

  /// The square at the left of a spot card.
  SpotPhoto({super.key, required Spot spot, this.size = 64})
      : imageUrl = spot.imageUrl,
        emoji = spot.emoji,
        radius = 16,
        background = spot.emojiBackground,
        border = spot.emojiBorder;

  /// For rankings that only know the place's id, emoji and photo (Best for
  /// you, Popular right now, By hour).
  const SpotPhoto.place({
    super.key,
    required this.imageUrl,
    required this.emoji,
    required this.size,
    this.radius = 12,
    this.background = AppColors.surface,
    this.border = AppColors.border,
  });

  @override
  Widget build(BuildContext context) {
    final imageUrl = this.imageUrl;
    final fallback = Center(child: Text(emoji, style: TextStyle(fontSize: size * 0.44)));
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: border),
      ),
      child: imageUrl == null || !RestaurantPhotos.enabled
          ? fallback
          : CachedNetworkImage(
              imageUrl: RestaurantPhotos.url(imageUrl),
              cacheManager: RestaurantPhotos.cacheManager,
              fit: BoxFit.cover,
              // Decoded at the size it is shown, not at the size of the file,
              // so each photo takes little space in the memory cache.
              memCacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
              fadeInDuration: const Duration(milliseconds: 200),
              placeholder: (_, _) => fallback,
              errorWidget: (_, _, _) => fallback,
            ),
    );
  }
}
