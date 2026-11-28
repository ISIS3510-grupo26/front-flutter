# Reviews on the restaurant page: profiling before and after

Sprint 4, micro-optimization. Issue front-flutter #39. Code: `lib/screens/place_detail_screen.dart`.

## What changed

- **Before:** every review of the page was a child of one `SliverList.list`, so each `build()` of the page
  created all of them (200 `_ReviewCard` and 200 spacers), even though only 2 or 3 fit on screen.
- **After:** the page shows the first 5 reviews in their own `SliverList.builder`, followed by a
  "See all reviews (N)" button that opens All reviews (paged by the backend). Like the "Student Reviews (N)"
  title, the button passes the visit's tracker, so All reviews sends `open_all` for BQ8.

## What was measured

The integration test `integration_test/place_detail_perf_test.dart` opens a restaurant with 200 reviews (fake
backend, so every run sees the same data) and records, with `binding.traceAction`:

1. `reviews_load`: the page opened 5 times (request, JSON, first frames).
2. `reviews_rebuild`: the page rebuilt 30 times by its parent, which runs the same `build()` as a `setState`.
3. `reviews_scroll`: 4 rounds of 10 drags of 300 px down and 10 back up.
4. `reviews_rebuild_builds` and `reviews_scroll_builds`: 2 and 3 again with `debugProfileBuildsEnabled`, to count
   which widgets are built (`docs/profiling/count_rebuilds.py`). That flag slows every build down, so these traces
   are only used for the counts. The timeline buffer fills up before the 30 rebuilds end (23 fit before, 21
   after), so the counts are divided by the rebuilds that fit.

Tool: Flutter timeline recorded by `integration_test` in **profile mode**, summarized by `flutter_driver`'s
`TimelineSummary`. Device: Samsung SM-S906U1 (Galaxy S22+), Android, over USB. 3 runs before and 3 after.

```
flutter drive --profile --no-dds --driver=test_driver/perf_driver.dart --target=integration_test/place_detail_perf_test.dart
python docs/profiling/count_rebuilds.py build/reviews_rebuild_builds.timeline.json PlaceDetailScreen _ReviewCard,_Avatar,_ReviewsHeader
python docs/profiling/count_rebuilds.py build/reviews_scroll_builds.timeline.json PlaceDetailScreen _ReviewCard,_Avatar
```

## Results

Mean of 3 runs. Every run is in `before/frame_times.csv`, `after/frame_times.csv` and `*/run*/rebuilds.txt`.

| Scenario | Metric | Before | After | Change | Before, runs 1/2/3 | After, runs 1/2/3 |
|---|---|---|---|---|---|---|
| Load (x5) | Average frame build (ms) | 4.06 | 4.07 | +0.2% | 4.48 / 4.23 / 3.48 | 4.03 / 4.35 / 3.83 |
| Load (x5) | 90th percentile frame build (ms) | 11.04 | 9.26 | -16% | 12.82 / 11.17 / 9.12 | 9.88 / 9.27 / 8.62 |
| Load (x5) | 99th percentile frame build (ms) | 14.48 | 16.93 | +17% | 16.36 / 12.76 / 14.32 | 18.23 / 19.96 / 12.59 |
| Rebuild (x30) | Average frame build (ms) | 3.32 | 3.19 | -4% | 4.03 / 3.89 / 2.04 | 3.22 / 3.21 / 3.13 |
| Rebuild (x30) | 90th percentile frame build (ms) | 7.20 | 6.44 | -11% | 9.89 / 6.76 / 4.94 | 6.62 / 6.49 / 6.20 |
| Rebuild (x30) | 99th percentile frame build (ms) | 13.34 | 9.73 | -27% | 18.15 / 16.61 / 5.26 | 14.58 / 7.67 / 6.95 |
| Rebuild (x30) | Worst frame build (ms) | 13.58 | 17.09 | +26% | 18.18 / 16.88 / 5.68 | 16.01 / 19.23 / 16.05 |
| Rebuild (x30) | Frames over the 16 ms build budget | 1.67 | 1.00 | -40% | 3 / 2 / 0 | 1 / 1 / 1 |
| Rebuild (x30) | Widgets built per rebuild | 556 | 617 | +11% | 556.8 / 555.8 / 556.2 | 615.1 / 617.4 / 618.6 |
| Rebuild (x30) | `_ReviewCard` built per rebuild | 2.00 | 2.10 | +5% | 2.00 / 2.00 / 2.00 | 2.10 / 2.10 / 2.10 |
| Scroll | `_ReviewCard` built during the scroll | 41 | 9 | -78% | 41 / 41 / 41 | 9 / 9 / 9 |
| Scroll | Average frame build (ms) | 5.68 | 2.45 | not comparable | 6.18 / 4.57 / 6.30 | 2.50 / 2.33 / 2.52 |

### Reading the numbers

- **The old list was already lazy where it matters.** `SliverList.list` uses a `SliverChildListDelegate`, which
  only creates elements for the children on screen and wraps each one in a `RepaintBoundary`. That is why only 2
  `_ReviewCard` were built per rebuild before, and 2 after. What the change removes is creating the list of 400
  child widgets on every `build()`, which is cheap: the average rebuild frame goes down 4% and the 90th and 99th
  percentiles go down 11% and 27%, but the worst frame and the load's 99th percentile go up, and the runs vary a
  lot between themselves (rebuild average before: 4.03 / 3.89 / 2.04 ms). With 3 runs these differences are
  within the noise.
- **More widgets per rebuild, not fewer** (556 to 617): the button and the two extra slivers add their own
  widgets, and the reviews were not built off screen before either.
- **The scroll is not the same scenario after the change.** The page is now short, so the 80 fixed drags reach the
  end and Android draws its overscroll effect: 155 frames after against 73 before, many of them almost empty,
  which lowers the average. What can be compared is how many review cards the scroll built: 41 before, 9 after.
- The real gain is in what the page asks of the phone: it no longer lays out and keeps up to 200 reviews in a
  scroll that nobody reaches; the rest of the reviews come from All reviews, which pages them from the backend
  (`ListView.builder`, LRU cache and offline copy).

Raster times are in every `*.timeline_summary.json`. The change only touches what is built on the UI thread.

## DevTools screenshots

Taken with the same scenario in DevTools mode, which runs the same gestures without `traceAction` (it would take
the timeline away from DevTools) and waits for a signal from the PC before starting:

```
flutter run --profile --dart-define=PERF_WAIT_FOR_START=true --dart-define=PERF_DEVTOOLS=true \
  -t integration_test/place_detail_perf_test.dart
# DevTools: Performance > Enhance Tracing > "Trace widget builds"; CPU Profiler > Start recording. Then:
curl "http://127.0.0.1:<port>/<token>=/ext.campus_bites.startPerf?isolateId=isolates/<id>"
```

The isolate id is the one whose `getIsolate` lists `ext.campus_bites.startPerf`.

- `before/devtools_performance_rebuilds.png`, `after/devtools_performance_rebuilds.png`: Performance, one build
  frame selected.
- `before/devtools_cpu_bottom_up.png`, `after/devtools_cpu_bottom_up.png`: CPU Profiler, bottom up.

## Files

- `before/run1..3`, `after/run1..3`: the `TimelineSummary` of every trace of every run, and `rebuilds.txt`.
- `before/frame_times.csv`, `after/frame_times.csv`: frame metrics of every run and their mean.
- `before/timelines_run1.zip`, `after/timelines_run1.zip`: the full timelines of run 1. Open a `*.timeline.json`
  in Flutter DevTools (Performance, Load data) or in Perfetto to see every frame.
