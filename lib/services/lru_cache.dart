import 'dart:collection';

/// Caching strategy: LRU cache (least recently used) with a time to live.
///
/// Structure: a [LinkedHashMap] keeps its keys in insertion order, so the
/// first key is always the least recently used one and the last key the most
/// recent. A hit is removed and inserted again to move it to the end. Hash
/// lookup plus a linked list make get, put and eviction O(1).
///
/// Entries older than [ttl] count as a miss and are dropped. When [put] goes
/// over [capacity], the least recently used entry is evicted.
///
/// The Taste Map uses capacity = 8 and ttl = 5 minutes: a student moves
/// between a handful of campus spots (library, cafeteria, classrooms), and
/// ratings don't change that fast, so going back to a recent spot reuses its
/// picks without calling the backend.
class LruCache<K, V> {
  final int capacity;
  final Duration ttl;
  final DateTime Function() _now;
  final LinkedHashMap<K, ({V value, DateTime savedAt})> _entries = LinkedHashMap();

  /// [now] is the clock; tests inject a fake one.
  LruCache({required this.capacity, required this.ttl, DateTime Function()? now})
      : _now = now ?? DateTime.now;

  int get length => _entries.length;

  /// The value for [key], or null when it is missing or older than [ttl].
  /// A hit becomes the most recently used entry.
  V? get(K key) {
    final entry = _entries.remove(key);
    if (entry == null) return null;
    if (_now().difference(entry.savedAt) > ttl) return null;
    _entries[key] = entry;
    return entry.value;
  }

  /// Saves [value] as the most recent entry and evicts the least recently
  /// used one when the cache is over [capacity].
  void put(K key, V value) {
    _entries.remove(key);
    _entries[key] = (value: value, savedAt: _now());
    if (_entries.length > capacity) _entries.remove(_entries.keys.first);
  }
}
