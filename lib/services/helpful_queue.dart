import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import '../repositories/api_exception.dart';
import 'reviews_local_store.dart';
import 'reviews_service.dart';

/// The Helpful votes of the signed-in user, sent to the server one at a time.
///
/// Every tap is saved first in Hive (`helpful_pending`, one entry per review
/// with the last state) and then sent. Without network it stays there,
/// marked on screen, and goes out when the connection comes back. It lives in
/// HomeShell, not in the screen, so a vote made offline is still sent after
/// leaving "All reviews".
class HelpfulQueue extends ChangeNotifier {
  final ReviewsService _service;
  final ReviewsLocalStore _local;
  final String? Function() _currentUserId;
  StreamSubscription<List<ConnectivityResult>>? _connectivity;

  /// Votes this session that the server already has. The pages in the memory
  /// cache and in Hive were saved before them, so they still go on top.
  final _sent = <int, bool>{};

  Future<void>? _sending;

  /// [connectivity] is `Connectivity().onConnectivityChanged`; tests pass
  /// their own stream.
  HelpfulQueue({
    required this._service,
    required this._local,
    required this._currentUserId,
    Stream<List<ConnectivityResult>>? connectivity,
  }) {
    _connectivity = connectivity?.listen(_onConnectivityChanged);
  }

  /// Multithreading strategy: Stream. Eventual connectivity: the votes made
  /// offline go out as soon as the connection comes back.
  void _onConnectivityChanged(List<ConnectivityResult> results) {
    if (results.any((r) => r != ConnectivityResult.none)) flush();
  }

  /// Whether the user marked [reviewId], given what the server said
  /// ([serverVotes]): what is pending wins, then what was sent this session.
  bool isMarked(int reviewId, Set<int> serverVotes) =>
      _local.pendingVotes[reviewId] ?? _sent[reviewId] ?? serverVotes.contains(reviewId);

  /// The count to show: the server's, corrected by the user's own vote if it
  /// changed after the page was loaded.
  int count(int reviewId, int serverCount, Set<int> serverVotes) {
    final before = serverVotes.contains(reviewId);
    final now = isMarked(reviewId, serverVotes);
    if (before == now) return serverCount;
    return now ? serverCount + 1 : (serverCount - 1).clamp(0, serverCount);
  }

  bool isPending(int reviewId) => _local.pendingVotes.containsKey(reviewId);

  /// Saves the tap and tries to send it. Never throws: a failure stays
  /// pending (network, 5xx) or is dropped (other 4xx) inside [flush].
  Future<void> toggle(String spotId, int reviewId, Set<int> serverVotes) async {
    final desired = !isMarked(reviewId, serverVotes);
    await _local.queue(spotId, reviewId, desired: desired);
    notifyListeners();
    await flush();
  }

  /// Sends the pending votes in series and forgets each one only after the
  /// server got it. One send at a time: a call while another runs gets that
  /// same run. Stops at the first network error (still offline).
  Future<void> flush() {
    if (_sending case final running?) return running;
    final run = _flush();
    // With nothing to send, _flush finishes before this line, so it is only
    // kept while it is still running.
    _sending = run;
    run.whenComplete(() {
      if (identical(_sending, run)) _sending = null;
    });
    return run;
  }

  Future<void> _flush() async {
    var changed = false;
    try {
      final userId = _currentUserId();
      if (userId == null) return;
      // A tap made while sending is picked up by the next loop.
      for (var batch = _local.pending; batch.isNotEmpty; batch = _local.pending) {
        for (final change in batch) {
          try {
            await _service.setHelpful(change.spotId, change.reviewId, userId, helpful: change.desired);
            _sent[change.reviewId] = change.desired;
            await _local.markSent(change);
            changed = true;
          } on Exception catch (e) {
            if (isNetworkError(e)) return;
            if (e is ApiException && e.statusCode < 500) {
              // The review is gone or the vote is invalid: retrying won't help.
              await _local.markSent(change);
              changed = true;
            } else {
              return; // 5xx: it waits for the next reconnection or tap
            }
          }
        }
      }
    } finally {
      // Cleared here, right after the last look at the queue, not when the
      // future completes: a tap that arrives after that look starts a new run
      // instead of joining one that is already done.
      _sending = null;
      if (changed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _connectivity?.cancel();
    super.dispose();
  }
}
