import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';

/// Caching strategy: image cache library (cached_network_image).
///
/// A flutter_map [TileProvider] that loads each OpenStreetMap tile through
/// [CachedNetworkImageProvider]. Tiles are saved on disk, so map areas already
/// seen load without internet and the app makes fewer requests to
/// OpenStreetMap.
class CachedTileProvider extends TileProvider {
  CachedTileProvider({super.headers});

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      CachedNetworkImageProvider(
        getTileUrl(coordinates, options),
        headers: headers,
      );
}
