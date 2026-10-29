import 'package:campus_bites/services/lru_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DateTime now;
  late LruCache<String, int> cache;

  setUp(() {
    now = DateTime(2026, 10, 27, 12);
    cache = LruCache(capacity: 2, ttl: const Duration(minutes: 5), now: () => now);
  });

  test('a saved key is a hit', () {
    cache.put('library', 1);
    expect(cache.get('library'), 1);
  });

  test('an unknown key is a miss', () {
    expect(cache.get('library'), isNull);
  });

  test('an entry older than the ttl is a miss and is dropped', () {
    cache.put('library', 1);
    now = now.add(const Duration(minutes: 5));
    expect(cache.get('library'), 1);

    now = now.add(const Duration(seconds: 1));
    expect(cache.get('library'), isNull);
    expect(cache.length, 0);
  });

  test('going over capacity evicts the least recently used entry', () {
    cache.put('library', 1);
    cache.put('cafeteria', 2);
    cache.put('gym', 3);

    expect(cache.get('library'), isNull);
    expect(cache.get('cafeteria'), 2);
    expect(cache.get('gym'), 3);
    expect(cache.length, 2);
  });

  test('get() makes the entry the most recently used', () {
    cache.put('library', 1);
    cache.put('cafeteria', 2);
    expect(cache.get('library'), 1);

    cache.put('gym', 3);

    expect(cache.get('cafeteria'), isNull);
    expect(cache.get('library'), 1);
    expect(cache.get('gym'), 3);
  });

  test('put() on an existing key replaces the value and its age', () {
    cache.put('library', 1);
    now = now.add(const Duration(minutes: 4));
    cache.put('library', 10);
    now = now.add(const Duration(minutes: 4));

    expect(cache.get('library'), 10);
    expect(cache.length, 1);
  });
}
