import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/spot.dart';
import '../services/restaurant_photos.dart';

/// The square at the left of a spot card: the photo of the place, or its emoji while it loads, if it fails 
/// (no internet and never downloaded) or if the spot has no photo.
class SpotPhoto extends StatelessWidget {
  final Spot spot;
  final double size;

  const SpotPhoto({super.key, required this.spot, this.size = 64});

  @override
  Widget build(BuildContext context) {
    final imageUrl = spot.imageUrl;
    final emoji = Center(child: Text(spot.emoji, style: TextStyle(fontSize: size * 0.44)));
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: spot.emojiBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: spot.emojiBorder),
      ),
      child: imageUrl == null || !RestaurantPhotos.enabled
          ? emoji
          : CachedNetworkImage(
              imageUrl: RestaurantPhotos.url(imageUrl),
              cacheManager: RestaurantPhotos.cacheManager,
              fit: BoxFit.cover,
              // Decoded at the size it is shown, not at the size of the file,
              // so each photo takes little space in the memory cache.
              memCacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
              fadeInDuration: const Duration(milliseconds: 200),
              placeholder: (_, _) => emoji,
              errorWidget: (_, _, _) => emoji,
            ),
    );
  }
}
