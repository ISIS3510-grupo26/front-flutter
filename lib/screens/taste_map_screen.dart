import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/nearby_pick.dart';
import '../models/telemetry_event.dart';
import '../services/cached_tile_provider.dart';
import '../services/map_display_event.dart';
import '../services/map_event_outbox.dart';
import '../services/reconnect_retry.dart';
import '../services/taste_map_loader.dart';
import '../services/telemetry_queue.dart';
import '../theme/app_colors.dart';
import '../widgets/offline_banner.dart';

class TasteMapScreen extends StatefulWidget {
  final TasteMapLoader loader;

  final ValueChanged<String>? onOpenSpot;

  /// BQ14 map_display events go here while online.
  final TelemetryQueue telemetry;
  final String? Function() currentUserId;

  /// BQ14 map_display events go here while offline.
  final MapEventOutbox outbox;

  /// Saves the pages of these spots on the phone, so they open offline.
  /// Called in the background after every fresh load; returns how many were
  /// saved.
  final Future<int> Function(List<String> spotIds)? prefetchDetails;

  const TasteMapScreen({
    super.key,
    required this.loader,
    required this.telemetry,
    required this.currentUserId,
    this.onOpenSpot,
    this.outbox = const MapEventOutbox(),
    this.prefetchDetails,
  });

  @override
  State<TasteMapScreen> createState() => _TasteMapScreenState();
}

class _TasteMapScreenState extends State<TasteMapScreen> {
  TasteMapState _state = const TasteMapLoading();

  /// Micro-optimization: the selected pin lives in a ValueNotifier instead of
  /// the screen's state. Tapping a pin rebuilds only the two pins whose look
  /// changes and the place card, never the map, its tiles or the other pins.
  final _selection = ValueNotifier<int>(0);

  /// Micro-optimization: the map is built once per load (see [_buildMap]) and
  /// the same widget instance is returned on every rebuild of the screen, so
  /// Flutter skips its whole subtree when the connectivity banner or anything
  /// else outside the map changes.
  Widget? _map;
  late final StreamSubscription<List<ConnectivityResult>> _connectivity;
  bool _online = true;

  /// Measures the current load, for the BQ14 events.
  final _loadWatch = Stopwatch();

  /// At most one 'tiles_failed' event per load (and none for cached loads).
  bool _tilesFailedReported = false;

  /// Increases with every load; a result is shown only if no newer load
  /// started meanwhile (e.g. refresh tapped while it was reconnecting).
  int _loadId = 0;

  /// True while the reloads after a reconnection are running.
  bool _reconnecting = false;

  @override
  void initState() {
    super.initState();
    _connectivity = Connectivity().onConnectivityChanged.listen(_onConnectivityChanged);
    Connectivity()
        .checkConnectivity()
        .then((results) {
          if (mounted) setState(() => _online = _isOnline(results));
        })
        .catchError((Object e) => debugPrint("Couldn't check connectivity: $e"));
    _forwardSavedEvents();
    _load();
  }

  @override
  void dispose() {
    _connectivity.cancel();
    _selection.dispose();
    super.dispose();
  }

  /// Multithreading strategy: Stream. Eventual connectivity: the screen
  /// listens to connectivity changes and, when the connection comes back
  /// while it shows offline picks or a network error, reloads by itself.
  void _onConnectivityChanged(List<ConnectivityResult> results) {
    final online = _isOnline(results);
    if (mounted) setState(() => _online = online);
    if (!online) return;
    _forwardSavedEvents();
    if (_showsOfflineData(_state)) _reloadAfterReconnect();
  }

  static bool _isOnline(List<ConnectivityResult> results) =>
      results.any((r) => r != ConnectivityResult.none);

  /// True when the screen shows the copy saved on the phone or the "no
  /// connection" error.
  static bool _showsOfflineData(TasteMapState state) => switch (state) {
        TasteMapLoaded(:final offlineSavedAt) => offlineSavedAt != null,
        TasteMapFailed(reason: TasteMapFailure.network) => true,
        _ => false,
      };

  /// Right after reconnecting the network is often not usable yet, so one
  /// reload is not enough: it retries a few times (1 s, 3 s, 6 s). The reloads
  /// are silent: the saved picks stay on screen until fresh ones arrive.
  void _reloadAfterReconnect() {
    if (_reconnecting) return;
    _reconnecting = true;
    retryAfterReconnect(() async {
      if (!mounted || !_showsOfflineData(_state)) return true;
      await _load(forceRefresh: true, silent: true);
      return !mounted || !_showsOfflineData(_state);
    }).whenComplete(() => _reconnecting = false);
  }

  /// [silent]: no spinner, and a result that is still offline is dropped so
  /// the screen keeps what it shows and no repeated BQ14 events are sent.
  Future<void> _load({bool forceRefresh = false, bool silent = false}) async {
    final id = ++_loadId;
    if (!silent) setState(() => _state = const TasteMapLoading());
    _loadWatch
      ..reset()
      ..start();
    final state = await widget.loader.load(forceRefresh: forceRefresh);
    if (!mounted || id != _loadId) return;
    if (silent && _showsOfflineData(state)) return;
    _reportMapDisplay(state);
    _selection.value = 0;
    setState(() {
      _state = state;
      _map = state is TasteMapLoaded ? _buildMap(state) : null;
    });
    _prefetchDetails(state);
  }

  /// Eventual connectivity: after fresh picks arrive, their pages are saved
  /// on the phone in the background (Future with handler, fire-and-forget),
  /// so opening a pin offline still works.
  void _prefetchDetails(TasteMapState state) {
    final prefetch = widget.prefetchDetails;
    if (prefetch == null || state is! TasteMapLoaded) return;
    if (state.fromCache || state.offlineSavedAt != null || state.picks.isEmpty) return;
    prefetch([for (final pick in state.picks.take(8)) pick.id])
        .then((saved) => debugPrint('Saved $saved Taste Map pages for offline use'))
        .catchError((Object e) {
      debugPrint("Couldn't save the Taste Map pages offline: $e");
      return 0;
    });
  }

  /// BQ14: one map_display event per load. Loads served from the LRU cache
  /// send nothing: they were already reported when they came from the network.
  void _reportMapDisplay(TasteMapState state) {
    if (state is TasteMapLoaded && state.fromCache) {
      _tilesFailedReported = true;
      return;
    }
    _tilesFailedReported = false;
    final errorType = mapDisplayErrorType(state);
    _send(state, TelemetryEvent.mapDisplay(
      userId: widget.currentUserId(),
      success: errorType == null,
      errorType: errorType,
      durationMs: _loadWatch.elapsedMilliseconds,
    ));
  }

  /// TileLayer.errorTileCallback: the map images failed (at most once per load).
  void _reportTilesFailed() {
    if (_tilesFailedReported) return;
    _tilesFailedReported = true;
    _send(_state, TelemetryEvent.mapDisplay(
      userId: widget.currentUserId(),
      success: false,
      errorType: 'tiles_failed',
      durationMs: _loadWatch.elapsedMilliseconds,
    ));
  }

  /// Online, the event goes to the TelemetryQueue. Offline, it is appended to
  /// the file outbox. "Offline" is either what the phone reports or a load
  /// that just failed for lack of network (Wi-Fi without internet, or the
  /// first load before the connectivity check answered). Future with handler:
  /// the write is fire-and-forget with .then()/.catchError(), so the map never
  /// waits for the disk; if the write fails the event still goes to the queue.
  void _send(TasteMapState state, TelemetryEvent event) {
    if (_online && !_showsOfflineData(state)) return widget.telemetry.enqueue(event);
    widget.outbox
        .append(event)
        .then((_) => debugPrint('BQ14 event saved offline'))
        .catchError((Object e) {
      debugPrint("Couldn't save the BQ14 event offline: $e");
      widget.telemetry.enqueue(event);
    });
  }

  /// Store and forward: moves the events saved offline to the TelemetryQueue.
  /// Future with handler, fire-and-forget.
  void _forwardSavedEvents() {
    widget.outbox
        .forwardTo(widget.telemetry)
        .then((count) {
      if (count > 0) debugPrint('Forwarded $count BQ14 events saved offline');
    }).catchError((Object e) => debugPrint("Couldn't forward BQ14 events: $e"));
  }

  /// Builds the map of one load. Called once when the picks arrive, not on
  /// every frame, so these micro-optimizations apply:
  /// - The pins with impossible coordinates are filtered here, once: before,
  ///   `hasValidCoordinates` (a Vincenty distance per pick) ran on every
  ///   rebuild of the screen.
  /// - One tile provider per load instead of a new `CachedTileProvider` (and
  ///   its headers map) on every rebuild.
  /// - Each pin listens to [_selection] by itself (_PinSlot).
  Widget _buildMap(TasteMapLoaded state) {
    final TasteMapLoaded(:picks, :userLat, :userLng) = state;
    final validPins = [
      for (var i = 0; i < picks.length; i++)
        // A pin with impossible coordinates is not drawn (BQ14 reports it as
        // invalid_coordinates).
        if (hasValidCoordinates(picks[i], userLat, userLng)) i,
    ];
    return FlutterMap(
      options: MapOptions(
        initialCenter: LatLng(userLat, userLng),
        initialZoom: 17,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.campus_bites',
          tileProvider: CachedTileProvider(),
          errorTileCallback: (_, _, _) => _reportTilesFailed(),
          // A tile that failed offline is loaded again when it
          // is needed, instead of staying blank after reconnecting.
          evictErrorTileStrategy: EvictErrorTileStrategy.notVisibleRespectMargin,
        ),
        MarkerLayer(
          markers: [
            Marker(
              point: LatLng(userLat, userLng),
              width: 18,
              height: 18,
              child: const _UserDot(),
            ),
            for (final i in validPins)
              Marker(
                point: LatLng(picks[i].latitude, picks[i].longitude),
                // Tall enough for the selected pin, which adds
                // a 3px white border on top of the base size.
                width: 110,
                height: 52,
                alignment: Alignment.topCenter,
                child: _PinSlot(
                  index: i,
                  pick: picks[i],
                  selection: _selection,
                ),
              ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Taste Map',
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    color: AppColors.espresso,
                    letterSpacing: -0.5,
                  ),
                ),
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: AppColors.surface,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.tune, color: AppColors.espresso),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
            child: Container(
              height: 52,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  const Icon(Icons.search, color: AppColors.muted, size: 20),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: TextField(
                      readOnly: true,
                      style: TextStyle(fontSize: 14, color: AppColors.espresso),
                      decoration: InputDecoration.collapsed(
                        hintText: 'Search food stalls, trucks, campus spots...',
                        hintStyle: TextStyle(fontSize: 14, color: AppColors.muted),
                      ),
                    ),
                  ),
                  const Icon(Icons.mic_none, color: AppColors.muted, size: 20),
                ],
              ),
            ),
          ),
          Expanded(
            child: switch (_state) {
              TasteMapLoading() => const Center(
                  child: CircularProgressIndicator(color: AppColors.tomato),
                ),
              TasteMapFailed(:final reason) =>
                _FailedView(reason: reason, onRetry: () => _load(forceRefresh: true)),
              TasteMapLoaded(
                :final picks,
                :final usedFallback,
                :final offlineSavedAt,
              ) =>
                Stack(
                  children: [
                    _map!,
                    Positioned(
                      top: 16,
                      right: 16,
                      child: GestureDetector(
                        onTap: () => _load(forceRefresh: true),
                        child: Container(
                          width: 44,
                          height: 44,
                          alignment: Alignment.center,
                          decoration: const BoxDecoration(
                            color: AppColors.card,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.navigation_outlined, color: AppColors.espresso),
                        ),
                      ),
                    ),
                    if (offlineSavedAt != null || !_online)
                      Positioned(
                        left: 16,
                        top: 16,
                        right: 72,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: OfflineBanner(
                            message: offlineSavedAt != null
                                ? 'Offline · showing your last picks from ${hourMinute(offlineSavedAt)}'
                                : 'Offline · showing your recent picks',
                          ),
                        ),
                      )
                    else if (usedFallback)
                      const Positioned(
                        left: 16,
                        top: 16,
                        right: 72,
                        child: _FallbackBanner(),
                      ),
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 16,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const _Attribution(),
                          const SizedBox(height: 6),
                          if (picks.isEmpty)
                            const _NoPicksCard()
                          else
                            ValueListenableBuilder<int>(
                              valueListenable: _selection,
                              builder: (context, selected, _) => _SelectedPlaceCard(
                                pick: picks[selected],
                                rank: selected + 1,
                                onOpen: widget.onOpenSpot == null
                                    ? null
                                    : () => widget.onOpenSpot!(picks[selected].id),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
            },
          ),
        ],
      ),
    );
  }
}

class _FailedView extends StatelessWidget {
  final TasteMapFailure reason;
  final VoidCallback onRetry;

  const _FailedView({required this.reason, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final message = switch (reason) {
      TasteMapFailure.signedOut => 'Sign in to see top spots near you.',
      TasteMapFailure.network =>
        "You're offline and there are no saved picks yet. The map will load by itself when you're back online.",
      TasteMapFailure.server =>
        "CampusBites couldn't load top spots right now. Try again in a moment.",
    };

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.muted),
            ),
            const SizedBox(height: 8),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

class _FallbackBanner extends StatelessWidget {
  const _FallbackBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.border),
      ),
      child: const Text(
        'Location off - showing picks near campus',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppColors.espresso,
        ),
      ),
    );
  }
}

class _Attribution extends StatelessWidget {
  const _Attribution();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Text(
        '© OpenStreetMap contributors',
        style: TextStyle(fontSize: 9, color: AppColors.muted),
      ),
    );
  }
}

class _NoPicksCard extends StatelessWidget {
  const _NoPicksCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: const Text(
        "You've tried every top spot nearby",
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.muted),
      ),
    );
  }
}

class _UserDot extends StatelessWidget {
  const _UserDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.tomato,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
      ),
    );
  }
}

/// One pin that rebuilds only when it becomes selected or stops being
/// selected. With N pins, a tap rebuilds 2 of them instead of N.
class _PinSlot extends StatefulWidget {
  final int index;
  final NearbyPick pick;
  final ValueNotifier<int> selection;

  const _PinSlot({required this.index, required this.pick, required this.selection});

  @override
  State<_PinSlot> createState() => _PinSlotState();
}

class _PinSlotState extends State<_PinSlot> {
  late bool _selected = widget.selection.value == widget.index;

  @override
  void initState() {
    super.initState();
    widget.selection.addListener(_onSelectionChanged);
  }

  @override
  void dispose() {
    widget.selection.removeListener(_onSelectionChanged);
    super.dispose();
  }

  void _onSelectionChanged() {
    final selected = widget.selection.value == widget.index;
    if (selected != _selected) setState(() => _selected = selected);
  }

  @override
  Widget build(BuildContext context) => _Pin(
        pick: widget.pick,
        selected: _selected,
        onTap: () => widget.selection.value = widget.index,
      );
}

class _Pin extends StatelessWidget {
  final NearbyPick pick;
  final bool selected;
  final VoidCallback onTap;

  const _Pin({required this.pick, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.tomato : AppColors.espresso;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(999),
              border: selected ? Border.all(color: Colors.white, width: 3) : null,
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: AppColors.espresso.withValues(alpha: 0.25),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(pick.emoji, style: const TextStyle(fontSize: 14)),
                const SizedBox(width: 4),
                Text(
                  '★ ${pick.rating}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          Transform.translate(
            offset: const Offset(0, -3),
            child: Transform.rotate(
              angle: pi / 4,
              child: Container(width: 8, height: 8, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectedPlaceCard extends StatelessWidget {
  final NearbyPick pick;
  final int rank;
  final VoidCallback? onOpen;

  const _SelectedPlaceCard({required this.pick, required this.rank, this.onOpen});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 56,
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(pick.emoji, style: const TextStyle(fontSize: 28)),
              ),
              Positioned(
                top: -6,
                right: -6,
                child: Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: AppColors.tomato,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '$rank',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        pick.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: AppColors.espresso,
                        ),
                      ),
                    ),
                    const Icon(Icons.star, size: 14, color: AppColors.tomato),
                    const SizedBox(width: 2),
                    Text(
                      '${pick.rating}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.tomato,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${pick.walkMinutes} min walk',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
                const SizedBox(height: 8),
                const _MetaPill(
                  label: 'New for you',
                  background: AppColors.mintLight,
                  foreground: AppColors.mint,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onOpen,
            child: Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: AppColors.tomato,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.chevron_right, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  final String label;
  final Color background;
  final Color foreground;

  const _MetaPill({required this.label, required this.background, required this.foreground});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: foreground),
      ),
    );
  }
}
