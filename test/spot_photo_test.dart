import 'package:cached_network_image/cached_network_image.dart';
import 'package:campus_bites/data/spots_data.dart';
import 'package:campus_bites/models/best_for_you.dart';
import 'package:campus_bites/services/best_for_you_loader.dart';
import 'package:campus_bites/services/restaurant_photos.dart';
import 'package:campus_bites/widgets/best_for_you_section.dart';
import 'package:campus_bites/widgets/for_you_section.dart';
import 'package:campus_bites/widgets/spot_photo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget child) => MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  test('the catalog gives the photo of a ranked spot by its id', () {
    expect(catalogImageUrl('nitro-coffee'), 'fotos/nitro-coffee.jpg');
    expect(catalogImageUrl('not-a-spot'), isNull);
  });

  testWidgets('without photos (tests, no network plugin) it shows the emoji', (tester) async {
    await tester.pumpWidget(_app(
      const SpotPhoto.place(imageUrl: 'fotos/nitro-coffee.jpg', emoji: '☕', size: 44),
    ));

    expect(find.text('☕'), findsOneWidget);
    expect(find.byType(CachedNetworkImage), findsNothing);
  });

  testWidgets('a place without a photo shows its emoji', (tester) async {
    RestaurantPhotos.enabled = true;
    addTearDown(() => RestaurantPhotos.enabled = false);

    await tester.pumpWidget(_app(const SpotPhoto.place(imageUrl: null, emoji: '🍔', size: 44)));

    expect(find.text('🍔'), findsOneWidget);
    expect(find.byType(CachedNetworkImage), findsNothing);
  });

  testWidgets("with a photo it uses Gabriela's cache and the emoji while it loads", (tester) async {
    RestaurantPhotos.enabled = true;
    addTearDown(() => RestaurantPhotos.enabled = false);

    await tester.pumpWidget(_app(
      const SpotPhoto.place(imageUrl: 'fotos/nitro-coffee.jpg', emoji: '☕', size: 44),
    ));

    final image = tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage));
    expect(image.imageUrl, RestaurantPhotos.url('fotos/nitro-coffee.jpg'));
    expect(image.cacheManager, same(RestaurantPhotos.cacheManager));
    expect(find.text('☕'), findsOneWidget);
  });

  testWidgets('Best for you cards show the photo of each spot from the catalog', (tester) async {
    const ranking = BestForYouRanking(personalized: false, spots: [
      BestForYouSpot(
        spotId: 'nitro-coffee',
        name: 'Nitro Coffee & Brew',
        emoji: '☕',
        cuisine: 'Café & Bakery',
        rating: 5,
        waitMinutes: 8,
        minutesAgo: 2,
        isRecent: true,
        tasteMatch: null,
      ),
    ]);

    await tester.pumpWidget(_app(
      BestForYouSection(state: const BestForYouLoaded(ranking), onRetry: () {}),
    ));

    final photo = tester.widget<SpotPhoto>(find.byType(SpotPhoto));
    expect(photo.imageUrl, 'fotos/nitro-coffee.jpg');
    expect(photo.emoji, '☕');
    expect(find.byType(RankedSpotCard), findsOneWidget);
  });
}
