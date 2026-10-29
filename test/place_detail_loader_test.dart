import 'dart:io';

import 'package:campus_bites/models/spot_detail.dart';
import 'package:campus_bites/repositories/api_exception.dart';
import 'package:campus_bites/services/local_database.dart';
import 'package:campus_bites/services/place_detail_loader.dart';
import 'package:flutter_test/flutter_test.dart';

final _spot = SpotDetail.fromJson({
  'id': 'nitro-coffee',
  'emoji': '☕',
  'emojiBackground': '#FFFBEB',
  'name': 'Nitro Coffee & Brew',
  'subtitle': 'Coffee • Library',
  'rating': 4.6,
  'totalReviews': 52,
  'price': '\$5.000 - \$9.000 COP',
  'distance': '2 min walk',
  'walkMinutes': 2,
  'isVegetarian': true,
  'affinityPercent': 90,
  'note': 'Quiet place to study.',
  'uniCardPerk': null,
  'reviews': [
    {'authorName': 'maria', 'initials': 'MA', 'stars': 5, 'text': 'Buen cafe', 'dinedAgo': 'Dined today'},
  ],
});

class _MemorySpots implements SpotDetailStorage {
  final saved = <String, ({SpotDetail spot, DateTime savedAt})>{};

  @override
  Future<void> save(SpotDetail spot) async =>
      saved[spot.id] = (spot: spot, savedAt: DateTime(2026, 10, 27, 13, 5));

  @override
  Future<({SpotDetail spot, DateTime savedAt})?> read(String id) async => saved[id];
}

void main() {
  late _MemorySpots storage;

  setUp(() => storage = _MemorySpots());

  test('network works: fresh page, saved for later', () async {
    final result = await loadPlaceDetail(
      spotId: 'nitro-coffee',
      fetch: (_) async => _spot,
      storage: storage,
    );
    await pumpEventQueue();

    expect(result.spot!.name, 'Nitro Coffee & Brew');
    expect(result.offlineSavedAt, isNull);
    expect(result.error, isNull);
    expect(storage.saved.keys, ['nitro-coffee']);
  });

  test('network fails: the saved copy and when it was saved', () async {
    await storage.save(_spot);
    const error = SocketException('offline');

    final result = await loadPlaceDetail(
      spotId: 'nitro-coffee',
      fetch: (_) async => throw error,
      storage: storage,
    );

    expect(result.spot!.id, 'nitro-coffee');
    expect(result.offlineSavedAt, DateTime(2026, 10, 27, 13, 5));
    expect(result.error, error);
  });

  test('network fails and nothing is saved: no page, only the error', () async {
    final result = await loadPlaceDetail(
      spotId: 'nitro-coffee',
      fetch: (_) async => throw const SocketException('offline'),
      storage: storage,
    );

    expect(result.spot, isNull);
    expect(result.offlineSavedAt, isNull);
    expect(result.error, isA<SocketException>());
  });

  test('an HTTP error never shows the saved copy', () async {
    await storage.save(_spot);

    final result = await loadPlaceDetail(
      spotId: 'nitro-coffee',
      fetch: (_) async => throw const ApiException(500),
      storage: storage,
    );

    expect(result.spot, isNull);
    expect(result.offlineSavedAt, isNull);
    expect(result.error, isA<ApiException>());
  });

  test('toJson() reads back the same page with fromJson()', () {
    final copy = SpotDetail.fromJson(_spot.toJson());

    expect(copy.toJson(), _spot.toJson());
    expect(copy.emojiBackground.toARGB32(), 0xFFFFFBEB);
    expect(copy.reviews.single.text, 'Buen cafe');
  });
}
