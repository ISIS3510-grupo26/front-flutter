import 'package:flutter/painting.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import '../config/api_config.dart';

/// Caching strategy for the restaurant photos, in two levels.
/// 1. Disk: cached_network_image with its own [CacheManager]. A photo is
///    downloaded once and then read from the phone, also without internet.
/// 2. Memory: Flutter's [ImageCache], which is an LRU (least recently used)
///    cache. [configureImageMemoryCache] sets its two limits.
class RestaurantPhotos {
  /// Off only in tests (test/flutter_test_config.dart): there is no network
  /// or disk plugin there, so the cards show the emoji.
  static bool enabled = true;

  /// Disk level. Its own key, so it is a separate folder from the map tiles.
  /// - stalePeriod 7 days: a restaurant photo almost never changes, so after
  ///   a week it is downloaded again and a new photo shows up.
  /// - maxNrOfCacheObjects 30: the backend has 7 restaurant photos and 21 dish
  ///   photos. Above that, the photo used least recently is deleted first.
  static final cacheManager = CacheManager(
    Config(
      'restaurantPhotos',
      stalePeriod: const Duration(days: 7),
      maxNrOfCacheObjects: 30,
    ),
  );

  /// image_url comes relative to the backend ("fotos/nitro-coffee.jpg") and
  /// the photos are served from its root, not from /api/v1.
  static String url(String imageUrl) => Uri.parse(ApiConfig.baseUrl).resolve('/$imageUrl').toString();
}

/// Memory level: Flutter's [ImageCache] is an LRU cache.
///
/// Structure: a map that keeps its keys in the order they were used. When an
/// image is used it goes to the end; when the cache is over one of its two
/// limits, it removes images from the start (the least recently used) until
/// it is back under both. The images on screen right now are kept apart and
/// never removed.

void configureImageMemoryCache(ImageCache cache) {
  cache
    ..maximumSize = 120
    ..maximumSizeBytes = 40 << 20;
}
