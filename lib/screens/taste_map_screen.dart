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

  const TasteMapScreen({
    super.key,
    required this.loader,
    required this.telemetry,
    required this.currentUserId,
    this.onOpenSpot,
    this.outbox = const MapEventOutbox(),
  });

  @override
  State<TasteMapScreen> createState() => _TasteMapScreenState();
}

class _TasteMapScreenState extends State<TasteMapScreen> {
  TasteMapState _state = const TasteMapLoading();
  int _selected = 0;
  late final StreamSubscription<List<ConnectivityResult>> _connectivity;
  bool _online = true;

  /// Measures the current load, for the BQ14 events.
  final _loadWatch = Stopwatch();

  /// At most one 'tiles_failed' event per load (and none for cached loads).
  bool _tilesFailedReported = false;

  @override
  void initState() {
    super.initState();
    _connectivity = Connectivity().onConnectivityChanged.listen(_onConnectivityChanged);
    Connectivity()
        .checkConnectivity()
        .then((results) {
          _online = _isOnline(results);
        })
        .catchError((Object e) => debugPrint("Couldn't check connectivity: $e"));
    _forwardSavedEvents();
    _load();
  }

  @override
  void dispose() {
    _connectivity.cancel();
    super.dispose();
  }

  /// Multithreading strategy: Stream. Eventual connectivity: the screen
  /// listens to connectivity changes and, when the connection comes back
  /// while it shows offline picks or a network error, reloads by itself.
  void _onConnectivityChanged(List<ConnectivityResult> results) {
    final online = _isOnline(results);
    _online = online;
    if (online) _forwardSavedEvents();
    final showingOffline = switch (_state) {
      TasteMapLoaded(:final offlineSavedAt) => offlineSavedAt != null,
      TasteMapFailed(reason: TasteMapFailure.network) => true,
      _ => false,
    };
    if (online && showingOffline) _load(forceRefresh: true);
  }

  static bool _isOnline(List<ConnectivityResult> results) =>
      results.any((r) => r != ConnectivityResult.none);

  Future<void> _load({bool forceRefresh = false}) async {
    setState(() => _state = const TasteMapLoading());
    _loadWatch
      ..reset()
      ..start();
    final state = await widget.loader.load(forceRefresh: forceRefresh);
    if (!mounted) return;
    _reportMapDisplay(state);
    setState(() {
      _state = state;
      _selected = 0;
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
    _send(TelemetryEvent.mapDisplay(
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
    _send(TelemetryEvent.mapDisplay(
      userId: widget.currentUserId(),
      success: false,
      errorType: 'tiles_failed',
      durationMs: _loadWatch.elapsedMilliseconds,
    ));
  }

  /// Online, the event goes to the TelemetryQueue. Offline, it is appended to
  /// the file outbox. Future with handler: the write is fire-and-forget with
  /// .then()/.catchError(), so the map never waits for the disk; if the write
  /// fails the event still goes to the in-memory queue.
  void _send(TelemetryEvent event) {
    if (_online) return widget.telemetry.enqueue(event);
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
                :final userLat,
                :final userLng,
                :final usedFallback,
                :final offlineSavedAt,
              ) =>
                Stack(
                  children: [
                    FlutterMap(
                      options: MapOptions(
                        initialCenter: LatLng(userLat, userLng),
                        initialZoom: 17,
                      ),
                      children: [
                        TileLayer(
                          urlTemplate:
                              'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.example.campus_bites',
                          tileProvider: CachedTileProvider(),
                          errorTileCallback: (_, _, _) => _reportTilesFailed(),
                        ),
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: LatLng(userLat, userLng),
                              width: 18,
                              height: 18,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: AppColors.tomato,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 3),
                                ),
                              ),
                            ),
                            for (var i = 0; i < picks.length; i++)
                              // A pin with impossible coordinates is not
                              // drawn (BQ14 reports it as invalid_coordinates).
                              if (hasValidCoordinates(picks[i], userLat, userLng))
                                Marker(
                                  point: LatLng(
                                    picks[i].latitude,
                                    picks[i].longitude,
                                  ),
                                  // Tall enough for the selected pin, which adds
                                  // a 3px white border on top of the base size.
                                  width: 110,
                                  height: 52,
                                  alignment: Alignment.topCenter,
                                  child: _Pin(
                                    pick: picks[i],
                                    selected: i == _selected,
                                    onTap: () => setState(() => _selected = i),
                                  ),
                                ),
                          ],
                        ),
                      ],
                    ),
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
                    if (offlineSavedAt != null)
                      Positioned(
                        left: 16,
                        top: 16,
                        right: 72,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: OfflineBanner(
                            message: 'Offline · showing your last picks from ${hourMinute(offlineSavedAt)}',
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
                            _SelectedPlaceCard(
                              pick: picks[_selected],
                              rank: _selected + 1,
                              onOpen: widget.onOpenSpot == null
                                  ? null
                                  : () => widget.onOpenSpot!(picks[_selected].id),
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
        "Couldn't reach CampusBites. Check your connection and try again.",
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
