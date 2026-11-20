import 'package:campus_bites/data/spots_data.dart';
import 'package:campus_bites/services/restaurant_photos.dart';
import 'package:campus_bites/widgets/spot_photo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the memory cache (LRU) gets its two limits', () {
    final cache = ImageCache();
    configureImageMemoryCache(cache);
    expect(cache.maximumSize, 120);
    expect(cache.maximumSizeBytes, 40 * 1024 * 1024);
  });

  test('the photo url goes to the backend root, not to /api/v1', () {
    expect(RestaurantPhotos.url('fotos/nitro-coffee.jpg'), 'http://10.0.2.2:8000/fotos/nitro-coffee.jpg');
  });

  test('every spot has the same photo the backend catalog has', () {
    for (final spot in sampleSpots) {
      expect(spot.imageUrl, 'fotos/${spot.id}.jpg');
      expect(spot.copyWith(isSaved: !spot.isSaved).imageUrl, spot.imageUrl);
    }
  });

  testWidgets('without photos (tests, or a spot with no image) the card shows the emoji', (tester) async {
    final spot = sampleSpots.first;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SpotPhoto(spot: spot))));
    expect(find.text(spot.emoji), findsOneWidget);
  });
}
