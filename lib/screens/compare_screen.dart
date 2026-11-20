import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

import '../models/spot.dart';
import '../models/spot_comparison.dart';
import '../services/compare_loader.dart';
import '../services/reconnect_retry.dart';
import '../theme/app_colors.dart';
import '../widgets/offline_banner.dart';

/// Compare two restaurants side by side (functional scenario 10, Sprint 4).
class CompareScreen extends StatefulWidget {
  final String firstId;
  final String secondId;
  final CompareLoader loader;

  /// The catalog on the phone: names for a side that isn't saved offline.
  final List<Spot> catalog;

  /// The student's compatibility per spot (smart feature), if loaded.
  final Map<String, int>? matchScores;

  final ValueChanged<String>? onOpenSpot;

  /// `Connectivity().onConnectivityChanged`; tests leave it null.
  final Stream<List<ConnectivityResult>>? connectivity;

  const CompareScreen({
    super.key,
    required this.firstId,
    required this.secondId,
    required this.loader,
    this.catalog = const [],
    this.matchScores,
    this.onOpenSpot,
    this.connectivity,
  });

  @override
  State<CompareScreen> createState() => _CompareScreenState();
}

class _CompareScreenState extends State<CompareScreen> {
  CompareState _state = const CompareLoading();
  StreamSubscription<List<ConnectivityResult>>? _connectivity;

  /// A load is running: a second one (reconnect + Retry) waits for it.
  Future<void>? _loading;
  bool _reconnecting = false;

  @override
  void initState() {
    super.initState();
    _connectivity = widget.connectivity?.listen(_onConnectivityChanged);
    _load();
  }

  @override
  void dispose() {
    _connectivity?.cancel();
    super.dispose();
  }

  bool get _needsNetwork => switch (_state) {
        CompareLoaded(:final needsNetwork) => needsNetwork,
        CompareFailed(reason: CompareFailure.network) => true,
        _ => false,
      };

  /// Eventual connectivity: when the connection comes back while the screen
  /// shows saved pages, a missing page or the offline error, it reloads by
  /// itself (1, 3 and 6 s, because the network is often not usable right
  /// after the radio connects).
  void _onConnectivityChanged(List<ConnectivityResult> results) {
    final online = results.any((r) => r != ConnectivityResult.none);
    if (!online || !_needsNetwork || _reconnecting) return;
    _reconnecting = true;
    retryAfterReconnect(() async {
      if (!mounted || !_needsNetwork) return true;
      await _load(forceRefresh: true, silent: true);
      return !mounted || !_needsNetwork;
    }).whenComplete(() => _reconnecting = false);
  }

  Future<void> _load({bool forceRefresh = false, bool silent = false}) =>
      _loading ??= _run(forceRefresh, silent).whenComplete(() => _loading = null);

  Future<void> _run(bool forceRefresh, bool silent) async {
    if (!silent) setState(() => _state = const CompareLoading());
    final state = await widget.loader.load(
      widget.firstId,
      widget.secondId,
      matchScores: widget.matchScores,
      catalog: widget.catalog,
      forceRefresh: forceRefresh,
    );
    if (!mounted) return;
    // A silent reload that is still offline keeps what is on screen.
    if (silent && (state is CompareFailed || (state is CompareLoaded && state.needsNetwork))) return;
    setState(() => _state = state);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: AppBar(
        backgroundColor: AppColors.cream,
        foregroundColor: AppColors.espresso,
        elevation: 0,
        title: const Text('Compare', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: switch (_state) {
        CompareLoading() => const Center(child: CircularProgressIndicator(color: AppColors.tomato)),
        CompareFailed(:final reason) => _Failed(
            offline: reason == CompareFailure.network,
            onRetry: () => _load(forceRefresh: true),
          ),
        final CompareLoaded loaded => _Table(
            state: loaded,
            onOpenSpot: widget.onOpenSpot,
            onRetry: () => _load(forceRefresh: true),
          ),
      },
    );
  }
}

class _Failed extends StatelessWidget {
  final bool offline;
  final VoidCallback onRetry;

  const _Failed({required this.offline, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              offline
                  ? "You're offline and these places aren't saved on your phone yet. "
                      "The comparison will load by itself when you're back online."
                  : "Couldn't load this comparison.",
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, color: AppColors.espresso),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(foregroundColor: AppColors.tomato),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Table extends StatelessWidget {
  final CompareLoaded state;
  final ValueChanged<String>? onOpenSpot;
  final VoidCallback onRetry;

  const _Table({required this.state, required this.onOpenSpot, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final c = state.comparison;
    final missing = [
      if (state.missingIds.contains(c.firstId)) c.firstName,
      if (state.missingIds.contains(c.secondId)) c.secondName,
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      children: [
        if (state.offlineSavedAt case final savedAt?) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: OfflineBanner(message: 'Offline · pages saved at ${hourMinute(savedAt)}'),
          ),
          const SizedBox(height: 8),
        ],
        if (missing.isNotEmpty) ...[
          Row(
            children: [
              Expanded(
                child: Text(
                  "${missing.join(' and ')} isn't saved on this phone yet. "
                  "It loads by itself when you're back online.",
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ),
              TextButton(
                onPressed: onRetry,
                style: TextButton.styleFrom(foregroundColor: AppColors.tomato),
                child: const Text('Retry'),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        Row(
          children: [
            Expanded(child: _Header(emoji: c.firstEmoji, name: c.firstName, wins: c.firstWins, complete: c.complete)),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Text('vs', style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.muted)),
            ),
            Expanded(child: _Header(emoji: c.secondEmoji, name: c.secondName, wins: c.secondWins, complete: c.complete)),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            children: [
              for (final (i, row) in c.rows.indexed) ...[
                if (i > 0) const Divider(height: 1, color: AppColors.border),
                _RowView(row: row),
              ],
            ],
          ),
        ),
        if (c.verdict case final verdict?) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.tomatoLight,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Text(
              verdict,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.tomato),
            ),
          ),
        ],
        if (onOpenSpot case final open?) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _OpenButton(label: 'Open ${c.firstName}', onPressed: () => open(c.firstId))),
              const SizedBox(width: 10),
              Expanded(child: _OpenButton(label: 'Open ${c.secondName}', onPressed: () => open(c.secondId))),
            ],
          ),
        ],
      ],
    );
  }
}

class _Header extends StatelessWidget {
  final String emoji;
  final String name;
  final int wins;
  final bool complete;

  const _Header({required this.emoji, required this.name, required this.wins, required this.complete});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 64,
          height: 64,
          alignment: Alignment.center,
          decoration: const BoxDecoration(color: AppColors.surface, shape: BoxShape.circle),
          child: Text(emoji, style: const TextStyle(fontSize: 30)),
        ),
        const SizedBox(height: 8),
        Text(
          name,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.espresso),
        ),
        if (complete)
          Text(
            '$wins ${wins == 1 ? 'win' : 'wins'}',
            style: const TextStyle(fontSize: 12, color: AppColors.muted),
          ),
      ],
    );
  }
}

class _RowView extends StatelessWidget {
  final CompareRow row;

  const _RowView({required this.row});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Column(
        children: [
          Text(
            row.label.toUpperCase(),
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: AppColors.muted),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(child: _Value(text: row.first, wins: row.winner == CompareSide.first)),
              const SizedBox(width: 12),
              Expanded(child: _Value(text: row.second, wins: row.winner == CompareSide.second)),
            ],
          ),
        ],
      ),
    );
  }
}

class _Value extends StatelessWidget {
  final String text;
  final bool wins;

  const _Value({required this.text, required this.wins});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: wins ? AppColors.mintLight : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (wins) ...[
            const Icon(Icons.check_circle, size: 14, color: AppColors.mint),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: wins ? FontWeight.w800 : FontWeight.w500,
                color: AppColors.espresso,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OpenButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  const _OpenButton({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.tomato,
        side: const BorderSide(color: AppColors.tomato),
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }
}
