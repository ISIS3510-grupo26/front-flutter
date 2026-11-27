import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

import '../models/best_time.dart';
import '../services/best_time_loader.dart';
import '../theme/app_colors.dart';
import '../widgets/filter_chip_pill.dart';
import '../widgets/offline_banner.dart';

/// View BQ15 (type 2): "At what time of the day is the reported waiting time at each restaurant the shortest?"

/// "Wait times now" (BQ4) answers how long the line is right now. This screen answers when to go: with the same 
/// reports, the calmest hour on campus and the best and worst hour of each restaurant.
class BestTimeScreen extends StatefulWidget {
  final BestTimeLoader loader;
  final ValueChanged<String> onOpenSpot;

  /// `Connectivity().onConnectivityChanged`; tests pass their own.
  final Stream<List<ConnectivityResult>>? connectionChanges;

  /// The phone's clock, to mark the current hour. Tests pass a fixed one.
  final DateTime Function()? now;

  const BestTimeScreen({
    super.key,
    required this.loader,
    required this.onOpenSpot,
    this.connectionChanges,
    this.now,
  });

  @override
  State<BestTimeScreen> createState() => _BestTimeScreenState();
}

class _BestTimeScreenState extends State<BestTimeScreen> {
  /// The two windows the student can pick; this week, or a month to have more reports when the week has few.
  static const _windows = {7: 'Last 7 days', 28: 'Last 4 weeks'};

  int _days = 7;
  BestTimeState _state = const BestTimeLoading();

  /// Each load gets a number; an answer that arrives after the student changed the window is from an old load and is ignored.
  int _loadId = 0;

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

  /// Eventual connectivity: if the screen is showing the phone copy (or nothing because there was no signal), 
  /// it asks the backend again by itself when the connection comes back. Online it does nothing, so it doesn't
  /// reload while the student is reading.
  void _onConnectivity(List<ConnectivityResult> results) {
    if (results.every((r) => r == ConnectivityResult.none)) return;
    final state = _state;
    final waitingForNetwork = (state is BestTimeLoaded && state.offlineSavedAt != null) ||
        (state is BestTimeFailed && state.reason == BestTimeFailure.network);
    if (waitingForNetwork) _load(forceRefresh: true);
  }

  Future<void> _load({bool forceRefresh = false}) async {
    final id = ++_loadId;
    // Pull to refresh keeps the list on screen; changing the window or Try again shows the spinner.
    final keepList = forceRefresh && _state is BestTimeLoaded;
    if (!keepList && _state is! BestTimeLoading) setState(() => _state = const BestTimeLoading());
    final state = await widget.loader.load(days: _days, forceRefresh: forceRefresh);
    if (!mounted || id != _loadId) return;
    setState(() => _state = state);
  }

  void _pickWindow(int days) {
    if (days == _days) return;
    _days = days;
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: AppBar(
        backgroundColor: AppColors.cream,
        foregroundColor: AppColors.espresso,
        elevation: 0,
        title: const Text('Best time to go', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
      ),
      body: SafeArea(child: _body()),
    );
  }

  Widget _body() {
    return switch (_state) {
      BestTimeLoading() => const Center(child: CircularProgressIndicator(color: AppColors.tomato)),
      BestTimeFailed(:final reason) => Center(
          child: _Message(
            text: reason == BestTimeFailure.network
                ? "You're offline and there's no saved copy yet. It will load when you're back online."
                : 'Something went wrong on our side. Try again in a moment.',
            onRetry: () => _load(forceRefresh: true),
          ),
        ),
      BestTimeLoaded(:final report, :final offlineSavedAt) => _report(report, offlineSavedAt),
    };
  }

  Widget _report(BestTimeReport report, DateTime? offlineSavedAt) {
    final nowHour = (widget.now ?? DateTime.now)().hour;
    final spots = report.spotsForDecision;
    return RefreshIndicator(
      color: AppColors.tomato,
      onRefresh: () => _load(forceRefresh: true),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        children: [
          if (offlineSavedAt != null) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: OfflineBanner(message: 'Offline · saved at ${hourMinute(offlineSavedAt)}'),
            ),
            const SizedBox(height: 12),
          ],
          Wrap(
            spacing: 8,
            children: [
              for (final MapEntry(key: days, value: label) in _windows.entries)
                FilterChipPill(label: label, active: _days == days, onTap: () => _pickWindow(days)),
            ],
          ),
          const SizedBox(height: 14),
          if (report.isEmpty)
            const _Message(
              text: 'Nobody has reported a wait in these days yet. Report your line in "Wait times now" '
                  'and the best hours will show up here.',
            )
          else ...[
            _CampusCard(report: report, nowHour: nowHour),
            const SizedBox(height: 20),
            const Text(
              'By restaurant',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.espresso),
            ),
            const SizedBox(height: 10),
            for (final spot in spots) ...[
              _SpotCard(spot: spot, nowHour: nowHour, onTap: () => widget.onOpenSpot(spot.spotId)),
              const SizedBox(height: 10),
            ],
          ],
          Text(
            'Average of the waits students reported in the last ${report.days} days, by the hour on your phone. '
            'An hour needs ${report.minReports} or more reports to be the best or the worst.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11, color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}

/// The calmest hour on campus, all restaurants together.
class _CampusCard extends StatelessWidget {
  final BestTimeReport report;
  final int nowHour;

  const _CampusCard({required this.report, required this.nowHour});

  @override
  Widget build(BuildContext context) {
    final calmest = report.calmestHour;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.mintLight, borderRadius: BorderRadius.circular(18)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            calmest == null
                ? 'There are not enough reports to pick the calmest hour yet.'
                : 'Calmest hour on campus: ${hourLabel(calmest.hour)}, ~${calmest.minutes} min of line on average.',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.espresso),
          ),
          const SizedBox(height: 4),
          Text(
            '${report.totalReports} report${report.totalReports == 1 ? '' : 's'} from students',
            style: const TextStyle(fontSize: 11, color: AppColors.muted),
          ),
          if (report.campusByHour.isNotEmpty) ...[
            const SizedBox(height: 14),
            HourBars(hours: report.campusByHour, best: calmest?.hour, nowHour: nowHour, height: 64),
          ],
        ],
      ),
    );
  }
}

class _SpotCard extends StatelessWidget {
  final BestTimeSpot spot;
  final int nowHour;
  final VoidCallback onTap;

  const _SpotCard({required this.spot, required this.nowHour, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final now = spot.at(nowHour);
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(spot.emoji, style: const TextStyle(fontSize: 26)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          spot.name,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.espresso),
                        ),
                        Text(
                          '${spot.reports} report${spot.reports == 1 ? '' : 's'}',
                          style: const TextStyle(fontSize: 11, color: AppColors.muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (!spot.hasBestHour)
                const Text(
                  'Not enough reports yet to know its best hour.',
                  style: TextStyle(fontSize: 12, color: AppColors.muted),
                )
              else ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _Tag(
                      text: 'Go at ${hourLabel(spot.bestHour!)} · ~${spot.bestAvgMinutes!.round()} min',
                      color: AppColors.mint,
                      background: AppColors.mintLight,
                    ),
                    if (spot.hasWorstHour)
                      _Tag(
                        text: 'Avoid ${hourLabel(spot.worstHour!)} · ~${spot.worstAvgMinutes!.round()} min',
                        color: AppColors.tomato,
                        background: AppColors.tomatoLight,
                      ),
                  ],
                ),
                if (now != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Usually at this hour (${hourLabel(nowHour)}): ~${now.minutes} min',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.espresso),
                  ),
                ],
                const SizedBox(height: 10),
                HourBars(hours: spot.byHour, best: spot.bestHour, nowHour: nowHour, height: 40),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String text;
  final Color color;
  final Color background;

  const _Tag({required this.text, required this.color, required this.background});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(999)),
      child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
    );
  }
}

/// One bar per hour from the first to the last hour with reports. The height is the average wait; an hour in 
/// between without reports stays empty. The best hour is green and the current hour has a dark outline.
class HourBars extends StatelessWidget {
  final List<HourlyWait> hours;
  final int? best;
  final int nowHour;
  final double height;

  const HourBars({super.key, required this.hours, required this.best, required this.nowHour, required this.height});

  @override
  Widget build(BuildContext context) {
    final first = hours.first.hour;
    final last = hours.last.hour;
    var longest = 0.0;
    for (final wait in hours) {
      if (wait.avgMinutes > longest) longest = wait.avgMinutes;
    }
    final byHour = {for (final wait in hours) wait.hour: wait};
    return Column(
      children: [
        SizedBox(
          height: height,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var hour = first; hour <= last; hour++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1.5),
                    child: _Bar(
                      // At least a sliver, so "no line" (0 min) is still visible.
                      fraction: switch (byHour[hour]) {
                        final wait? => longest == 0 ? 0.06 : (wait.avgMinutes / longest).clamp(0.06, 1.0).toDouble(),
                        null => 0.0,
                      },
                      color: hour == best ? AppColors.mint : AppColors.tomato.withValues(alpha: 0.35),
                      isNow: hour == nowHour,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(hourLabel(first), style: const TextStyle(fontSize: 10, color: AppColors.muted)),
            if (last != first) Text(hourLabel(last), style: const TextStyle(fontSize: 10, color: AppColors.muted)),
          ],
        ),
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  final double fraction;
  final Color color;
  final bool isNow;

  const _Bar({required this.fraction, required this.color, required this.isNow});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: FractionallySizedBox(
        heightFactor: fraction,
        widthFactor: 1,
        child: Container(
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
            border: isNow ? Border.all(color: AppColors.espresso, width: 1.5) : null,
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  final String text;
  final VoidCallback? onRetry;

  const _Message({required this.text, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(text, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted)),
          if (onRetry case final retry?) TextButton(onPressed: retry, child: const Text('Try again')),
        ],
      ),
    );
  }
}
