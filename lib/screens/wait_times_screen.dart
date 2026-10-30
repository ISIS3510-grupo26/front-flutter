import 'package:flutter/material.dart';

import '../models/wait_time.dart';
import '../repositories/wait_times_repository.dart';
import '../theme/app_colors.dart';

/// BQ4 (type 2): "What is the last reported waiting time for each restaurant?"
class WaitTimesScreen extends StatefulWidget {
  final WaitTimesRepository repository;
  final ValueChanged<String> onOpenSpot;

  const WaitTimesScreen({super.key, required this.repository, required this.onOpenSpot});

  @override
  State<WaitTimesScreen> createState() => _WaitTimesScreenState();
}

class _WaitTimesScreenState extends State<WaitTimesScreen> {
  static const _options = [0, 5, 10, 15, 20, 30, 45, 60];

  List<LastWaitTime>? _waits;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final waits = await widget.repository.fetchLatest();
      if (mounted) {
        setState(() {
          _waits = sortForDecision(waits);
          _failed = false;
        });
      }
    } on Exception {
      if (mounted) setState(() => _failed = true);
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
    // The report is created once, a retry sends the same id and time.
    await _send(WaitReport(spotId: place.spotId, minutes: minutes));
  }

  Future<void> _send(WaitReport report) async {
    try {
      await widget.repository.send(report);
      _message('Thanks! Other students can see it now.');
      _load();
    } on Exception {
      _message("Couldn't send your report.", retry: () => _send(report));
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
      ),
      body: SafeArea(child: _body()),
    );
  }

  Widget _body() {
    final waits = _waits;
    if (waits == null) {
      return Center(
        child: _failed
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    "Couldn't reach CampusBites. Check your connection.",
                    style: TextStyle(color: AppColors.muted),
                  ),
                  TextButton(onPressed: _load, child: const Text('Try again')),
                ],
              )
            : const CircularProgressIndicator(color: AppColors.tomato),
      );
    }
    final best = waits.where((w) => w.hasReport && w.isRecent).firstOrNull;
    return RefreshIndicator(
      color: AppColors.tomato,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        children: [
          _Summary(best: best),
          const SizedBox(height: 14),
          for (final place in waits) ...[
            _WaitRow(
              place: place,
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
  final VoidCallback onTap;
  final VoidCallback onReport;

  const _WaitRow({required this.place, required this.onTap, required this.onReport});

  @override
  Widget build(BuildContext context) {
    final fresh = place.hasReport && place.isRecent;
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
