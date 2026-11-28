import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

import '../models/wait_time.dart';
import '../repositories/api_exception.dart';
import '../repositories/wait_times_repository.dart';
import '../services/wait_times_store.dart';
import '../theme/app_colors.dart';
import '../widgets/offline_banner.dart';

/// BQ4 (type 2): "What is the last reported waiting time for each restaurant?"
class WaitTimesScreen extends StatefulWidget {
  final WaitTimesRepository repository;
  final WaitTimesStore store;
  final ValueChanged<String> onOpenSpot;

  final Stream<List<ConnectivityResult>>? connectionChanges;

  /// Opens "Best time to go" (BQ15, Sprint 4). Null hides the button.
  final VoidCallback? onOpenBestTime;

  const WaitTimesScreen({
    super.key,
    required this.repository,
    required this.store,
    required this.onOpenSpot,
    this.connectionChanges,
    this.onOpenBestTime,
  });

  @override
  State<WaitTimesScreen> createState() => _WaitTimesScreenState();
}

class _WaitTimesScreenState extends State<WaitTimesScreen> {
  static const _options = [0, 5, 10, 15, 20, 30, 45, 60];

  List<LastWaitTime>? _waits;

  /// spotId -> minutes the student reported offline, still waiting to be sent.
  Map<String, int> _pending = {};

  /// Set when the list on screen is the saved one because there is no connection: when it was saved.
  DateTime? _offlineSince;

  /// Nothing to show: no connection and nothing saved, or a server error.
  String? _error;

  late final StreamSubscription<List<ConnectivityResult>> _connectionChanges;

  @override
  void initState() {
    super.initState();
    _connectionChanges =
        (widget.connectionChanges ?? Connectivity().onConnectivityChanged).listen(_onConnectivity);
    _load();
  }

  @override
  void dispose() {
    _connectionChanges.cancel();
    super.dispose();
  }

  /// When the signal comes back: send what was reported offline, then reload.
  Future<void> _onConnectivity(List<ConnectivityResult> results) async {
    if (results.every((r) => r == ConnectivityResult.none)) return;
    try {
      await widget.store.flush(widget.repository);
    } on Exception {
      // They stay saved for the next try.
    }
    await _load();
  }

  Future<void> _load() async {
    // 1. What is saved goes on screen right away, so it is never empty while waiting.
    final saved = await widget.store.loadSaved();
    if (!mounted) return;
    if (_waits == null && saved != null) {
      setState(() {
        _waits = sortForDecision(saved.waits);
        _pending = saved.pending;
      });
    }
    // 2. Then the backend.
    try {
      final waits = await widget.repository.fetchLatest();
      // Future with handler: saving to disk doesn't make the screen wait, and
      // if it fails the screen still shows the fresh list.
      widget.store
          .saveLatest(waits, DateTime.now())
          .catchError((Object e) => debugPrint("Couldn't save the wait times offline: $e"));
      final pending = await widget.store.pendingBySpot();
      if (!mounted) return;
      setState(() {
        _waits = sortForDecision(waits);
        _pending = pending;
        _offlineSince = null;
        _error = null;
      });
      // The backend answered but there are reports saved from before (for
      // example the signal was weak, not off, so the phone never "came back"):
      // they are sent now and the list is asked again with them included.
      if (pending.isNotEmpty) {
        widget.store
            .flush(widget.repository)
            .then((sent) {
              if (sent > 0) _load();
            })
            .catchError((Object e) => debugPrint("Couldn't send the saved wait times: $e"));
      }
    } on Exception catch (e) {
      if (!mounted) return;
      if (!isNetworkError(e) && _waits != null) {
        _message("Couldn't refresh the wait times, something went wrong on our side.", retry: _load);
      }
      setState(() {
        if (!isNetworkError(e)) {
          // A server error is a real problem: it is not hidden behind old data.
          _error = 'Something went wrong on our side. Pull down or tap Try again.';
        } else if (saved != null) {
          _offlineSince = saved.savedAt;
        } else {
          _error = "You're offline and there are no saved wait times yet. They will load when you're back online.";
        }
      });
    }
  }

  Future<void> _report(LastWaitTime place) async {
    final minutes = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: AppColors.cream,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'How long is the line at ${place.name}?',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.espresso),
              ),
              const SizedBox(height: 4),
              const Text(
                'Other students will see it for the next 2 hours.',
                style: TextStyle(fontSize: 12, color: AppColors.muted),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final option in _options)
                    ActionChip(
                      label: Text(option == 0 ? 'No line' : '$option min'),
                      onPressed: () => Navigator.pop(sheetContext, option),
                      backgroundColor: AppColors.card,
                      side: const BorderSide(color: AppColors.border),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (minutes == null) return;
    // The report is created once (id and time), so a retry or a later send
    // from the saved queue is the same report for the backend.
    await _send(WaitReport(spotId: place.spotId, minutes: minutes));
  }

  Future<void> _send(WaitReport report) async {
    try {
      await widget.repository.send(report);
      _message('Thanks! Other students can see it now.');
      _load();
    } on Exception catch (e) {
      if (!isNetworkError(e)) {
        _message("Couldn't send your report.", retry: () => _send(report));
        return;
      }
      // Offline: it is saved on the phone and sent when the signal comes back.
      await widget.store.addPending(report);
      if (!mounted) return;
      setState(() => _pending = {..._pending, report.spotId: report.minutes});
      _message("You're offline. Your report is saved and will be sent when you're back online.");
    }
  }

  void _message(String text, {VoidCallback? retry}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(text),
        action: retry == null ? null : SnackBarAction(label: 'Retry', onPressed: retry),
      ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: AppBar(
        backgroundColor: AppColors.cream,
        foregroundColor: AppColors.espresso,
        elevation: 0,
        title: const Text('Wait times now', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
        actions: [
          if (widget.onOpenBestTime case final open?)
            TextButton.icon(
              onPressed: open,
              icon: const Icon(Icons.schedule, size: 18, color: AppColors.tomato),
              label: const Text(
                'Best time',
                style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.tomato),
              ),
            ),
        ],
      ),
      body: SafeArea(child: _body()),
    );
  }

  Widget _body() {
    final waits = _waits;
    if (waits == null) {
      final error = _error;
      return Center(
        child: error != null
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(error, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted)),
                    TextButton(onPressed: _load, child: const Text('Try again')),
                  ],
                ),
              )
            : const CircularProgressIndicator(color: AppColors.tomato),
      );
    }
    final best = waits.where((w) => w.hasReport && w.isRecent).firstOrNull;
    final offlineSince = _offlineSince;
    return RefreshIndicator(
      color: AppColors.tomato,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        children: [
          if (offlineSince != null) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: OfflineBanner(message: 'Offline · wait times from ${hourMinute(offlineSince)}'),
            ),
            const SizedBox(height: 12),
          ],
          _Summary(best: best),
          const SizedBox(height: 14),
          for (final place in waits) ...[
            _WaitRow(
              place: place,
              pendingMinutes: _pending[place.spotId],
              onTap: () => widget.onOpenSpot(place.spotId),
              onReport: () => _report(place),
            ),
            const SizedBox(height: 10),
          ],
          const Text(
            'Reports older than 2 hours are shown as old. Pull down to refresh.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  final LastWaitTime? best;

  const _Summary({required this.best});

  @override
  Widget build(BuildContext context) {
    final place = best;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.tomatoLight, borderRadius: BorderRadius.circular(18)),
      child: Text(
        place == null
            ? 'Nobody has reported a wait in the last 2 hours. Are you in a line? Report it below.'
            : 'Shortest wait right now: ${place.emoji} ${place.name}, ~${place.minutes} min.',
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.espresso),
      ),
    );
  }
}

class _WaitRow extends StatelessWidget {
  final LastWaitTime place;

  /// Minutes the student reported here while offline, not sent yet.
  final int? pendingMinutes;
  final VoidCallback onTap;
  final VoidCallback onReport;

  const _WaitRow({required this.place, required this.onTap, required this.onReport, this.pendingMinutes});

  @override
  Widget build(BuildContext context) {
    final fresh = place.hasReport && place.isRecent;
    final pending = pendingMinutes;
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Text(place.emoji, style: const TextStyle(fontSize: 26)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      place.name,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.espresso),
                    ),
                    const SizedBox(height: 2),
                    Text(place.detail, style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                    if (pending != null)
                      Text(
                        'Your report: ${pending == 0 ? 'no line' : '$pending min'} · waiting to send',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.tomato),
                      ),
                  ],
                ),
              ),
              Text(
                place.hasReport ? '~${place.minutes} min' : '—',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  // Only a recent report gets the color, an old one is a hint, not a fact.
                  color: fresh ? AppColors.tomato : AppColors.muted,
                ),
              ),
              IconButton(
                onPressed: onReport,
                tooltip: 'Report the wait here',
                icon: const Icon(Icons.add_comment_outlined, color: AppColors.tomato),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
