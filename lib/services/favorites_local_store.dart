import 'package:hive/hive.dart';

import '../models/spot.dart';

/// A save or unsave the server hasn't received yet.
class PendingFavorite {
  final String spotId;

  /// true = saved, false = unsaved: the last thing the student did.
  final bool desired;
  final DateTime updatedAt;

  const PendingFavorite({required this.spotId, required this.desired, required this.updatedAt});
}

/// Local storage strategy for favorites: Hive (key-value), the same database
/// as [HiveStore], with two boxes of plain maps (no TypeAdapters):
///
/// - `favorites`: spotId -> what the Saved card shows, plus `savedAt`. It is
///   the copy of the student's saved places that Saved shows without network.
/// - `favorites_pending`: spotId -> {desired, updatedAt}. The key is the spot,
///   so saving and unsaving the same spot offline leave one entry with the
///   last state (the last tap wins, and sending it twice changes nothing).
///
/// Hive must already be initialized: main() opens [HiveStore] first, which
/// calls Hive.init once for the whole app.
class FavoritesLocalStore {
  static const favoritesBox = 'favorites';
  static const pendingBox = 'favorites_pending';

  /// When the server last sent the whole list. Spot ids never start with '_'.
  static const _syncedAtKey = '_syncedAt';

  final Box<Map> _favorites;
  final Box<Map> _pending;

  FavoritesLocalStore._(this._favorites, this._pending);

  static Future<FavoritesLocalStore> open() async {
    final boxes = await Future.wait([
      Hive.openBox<Map>(favoritesBox),
      Hive.openBox<Map>(pendingBox),
    ]);
    return FavoritesLocalStore._(boxes[0], boxes[1]);
  }

  // ---------- Saved places (the copy) ----------

  /// Ids of the spots saved on this phone, including changes not sent yet.
  Set<String> get savedIds => {
        for (final key in _favorites.keys)
          if (key != _syncedAtKey) key as String,
      };

  /// When the server last answered with the full list; null if it never did.
  DateTime? get syncedAt {
    final map = _favorites.get(_syncedAtKey);
    return map == null ? null : DateTime.parse(map['at'] as String);
  }

  /// The card of a saved spot, as stored ('name', 'emoji', ..., 'savedAt').
  Map<String, dynamic>? card(String spotId) {
    final map = _favorites.get(spotId);
    return map == null ? null : Map<String, dynamic>.from(map);
  }

  /// Optimistic write: the heart changes here before the server answers.
  Future<void> setSaved(Spot spot, bool saved, {DateTime? now}) => saved
      ? _favorites.put(spot.id, _cardOf(spot, now ?? DateTime.now()))
      : _favorites.delete(spot.id);

  /// The server answered: its list replaces the whole copy.
  Future<void> replaceAll(Iterable<Spot> saved, {DateTime? now}) async {
    final at = now ?? DateTime.now();
    await _favorites.clear();
    await _favorites.putAll({
      for (final spot in saved) spot.id: _cardOf(spot, at),
      _syncedAtKey: {'at': at.toUtc().toIso8601String()},
    });
  }

  // ---------- Pending changes ----------

  List<PendingFavorite> get pending => [
        for (final key in _pending.keys)
          PendingFavorite(
            spotId: key as String,
            desired: _pending.get(key)!['desired'] as bool,
            updatedAt: DateTime.parse(_pending.get(key)!['updatedAt'] as String),
          ),
      ];

  Set<String> get pendingIds => {for (final key in _pending.keys) key as String};

  /// Collapses by spot: a second change of the same spot overwrites the first.
  Future<void> queue(String spotId, {required bool desired, DateTime? now}) => _pending.put(spotId, {
        'desired': desired,
        'updatedAt': (now ?? DateTime.now()).toUtc().toIso8601String(),
      });

  /// Forgets [change] after the server got it, unless the student changed
  /// that spot again in the meantime (then the newer change stays pending).
  Future<void> markSent(PendingFavorite change) async {
    final current = _pending.get(change.spotId);
    if (current != null &&
        DateTime.parse(current['updatedAt'] as String).isAtSameMomentAs(change.updatedAt)) {
      await _pending.delete(change.spotId);
    }
  }

  /// An online change of [spotId] reached the server, so an older pending one is stale.
  Future<void> dropPending(String spotId) => _pending.delete(spotId);

  /// Sign out: both boxes belong to the user who is leaving.
  Future<void> clear() => Future.wait([_favorites.clear(), _pending.clear()]);

  static Map<String, dynamic> _cardOf(Spot spot, DateTime savedAt) => {
        'name': spot.name,
        'emoji': spot.emoji,
        'subtitle': spot.subtitle,
        'rating': spot.rating,
        'price': spot.price,
        'category': spot.category.name,
        'imageUrl': spot.imageUrl,
        'savedAt': savedAt.toUtc().toIso8601String(),
      };
}
