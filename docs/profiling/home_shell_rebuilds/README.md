# HomeShell: what a heart tap rebuilds, before and after

Sprint 4, micro-optimization. Issue front-flutter #39. Code: `lib/screens/home_shell.dart`.

## What changed

- **Before:** one `ListenableBuilder` over the whole `IndexedStack` listened to the saved places and the
  preferences, so every `notifyListeners` (one per heart tap) rebuilt the four tabs, hidden ones included:
  For You, Taste Map, Saved and Profile.
- **After:** each tab listens only to what it shows. For You listens to the saved places and the preferences
  (its cards and what "Best for you" asks for), Saved to the saved places, Taste Map to neither, and Profile
  already listened to the preferences itself. Nothing visible changes. The memoization of the For You feed
  (it reuses its cards while `spots` is the same list) is untouched.

## What was measured

The integration test `integration_test/home_shell_perf_test.dart` opens the real HomeShell with a development user
and fresh Hive boxes, waits 10 s for the first loads, scrolls to the first For You card, waits 10 s more and taps its
heart 20 times (save, unsave, ...), waiting for each save to reach the backend before the next tap. The Flutter
timeline is recorded twice with `binding.traceAction`:

1. `home_shell_heart_taps`: the taps as they are, for frame times.
2. `home_shell_heart_taps_builds`: the same taps with `debugProfileBuildsEnabled`, to count which widgets each tap
   rebuilds (`docs/profiling/count_rebuilds.py`, with `ForYouScreen` as the widget built once per tap). Each tap
   builds about 1,500 to 1,750 widgets, so the normal ring buffer only kept 4 or 5 taps; the runs use
   `--endless-trace-buffer` so all 20 are in the trace.

Tool: Flutter timeline recorded by `integration_test` in **profile mode**, summarized by `flutter_driver`'s
`TimelineSummary`. Device: Samsung SM-S906U1 (Galaxy S22+), Android, over USB. 3 runs before and 3 after.

Two things every run needs, so the taps always do the same:

- **The local backend**, reachable from the phone with `adb reverse`, so every save gets an answer in a few ms.
  Without it the save is queued offline and the tap fires a second `notifyListeners`.
- **The location permission granted with adb** while the test runs. HomeShell builds the hidden Taste Map tab,
  which asks for the location when it is built; `flutter drive` reinstalls the app on every run, which resets the
  permission, and the system dialog on top of the app made the first trial runs slower (99th percentile around
  40 ms). Those runs are not used.

```
adb reverse tcp:8000 tcp:8000
# in another terminal, for as long as the run takes:
while true; do adb shell pm grant --user 0 com.example.campus_bites android.permission.ACCESS_FINE_LOCATION; \
  adb shell pm grant --user 0 com.example.campus_bites android.permission.ACCESS_COARSE_LOCATION; sleep 0.5; done
flutter drive --profile --no-dds --endless-trace-buffer --driver=test_driver/perf_driver.dart \
  --target=integration_test/home_shell_perf_test.dart --dart-define=API_BASE_URL=http://127.0.0.1:8000/api/v1
python docs/profiling/count_rebuilds.py build/home_shell_heart_taps_builds.timeline.json ForYouScreen \
  ForYouScreen,TasteMapScreen,SavedPlacesScreen,ProfileScreen,SpotCard,IndexedStack,CampusBottomNavBar
```

## Results

Mean of 3 runs. Every run is in `before/frame_times.csv`, `after/frame_times.csv` and `*/run*/rebuilds.txt`.

| Metric | Before | After | Change | Before, runs 1/2/3 | After, runs 1/2/3 |
|---|---|---|---|---|---|
| Widgets rebuilt per tap | 1,751 | 1,517 | -13% | 1751.1 / 1750.8 / 1750.1 | 1517.0 / 1516.0 / 1517.2 |
| `TasteMapScreen` rebuilt per tap | 1 | 0 | -100% | 1 / 1 / 1 | 0 / 0 / 0 |
| `ProfileScreen` rebuilt per tap | 1 | 0 | -100% | 1 / 1 / 1 | 0 / 0 / 0 |
| `IndexedStack` rebuilt per tap | 1 | 0 | -100% | 1 / 1 / 1 | 0 / 0 / 0 |
| `ForYouScreen` / `SavedPlacesScreen` rebuilt per tap | 1 / 1 | 1 / 1 | same | 1 / 1 each run | 1 / 1 each run |
| 99th percentile frame build time (ms) | 21.90 | 21.19 | -3% | 21.44 / 22.47 / 21.80 | 20.50 / 21.95 / 21.12 |
| Worst frame build time (ms) | 26.88 | 25.55 | -5% | 29.06 / 27.06 / 24.53 | 25.12 / 25.84 / 25.69 |
| Frames over the 16 ms build budget (20 taps) | 13.67 | 15.33 | +12% | 13 / 14 / 14 | 13 / 16 / 17 |
| Average frame build time (ms) | 3.10 | 3.18 | +3% | 3.28 / 3.08 / 2.95 | 3.04 / 3.20 / 3.31 |

### Reading the numbers

- **The hidden tabs stop rebuilding:** Taste Map, Profile and the `IndexedStack` go from once per tap to never,
  and a tap rebuilds 234 widgets fewer (-13%).
- **The tap frame barely changes.** Almost all of its cost is For You itself (about 1,500 of the 1,517 widgets),
  which has to rebuild because the heart on its card changes. The tabs that no longer rebuild were cheap: together
  with the `IndexedStack` they were the 234 widgets per tap that are gone. The 99th
  percentile and the worst frame go down 3% and 5%, and the frames over budget go up from 13.7 to 15.3, but the runs
  vary between 13 and 17 on their own, so with 3 runs these frame times are the same before and after.
- The average frame build time includes the idle frames between taps (about 418 frames for 20 taps), so it says
  little about the tap itself.
- What would make the tap frame cheaper is rebuilding only the card that changed inside For You, not the screen:
  that is a different change, inside `for_you_screen.dart`, not measured here.

Raster times are in every `*.timeline_summary.json`; the change only touches what is built on the UI thread.

## DevTools screenshots

Taken with the same scenario in DevTools mode (the same taps without `traceAction`, started from the PC):

```
flutter run --profile --dart-define=API_BASE_URL=http://127.0.0.1:8000/api/v1 \
  --dart-define=PERF_WAIT_FOR_START=true --dart-define=PERF_DEVTOOLS=true -t integration_test/home_shell_perf_test.dart
# DevTools: Performance > Enhance Tracing > "Trace widget builds"; CPU Profiler > Start recording. Then:
curl "http://127.0.0.1:<port>/<token>=/ext.campus_bites.startPerf?isolateId=isolates/<id>"
```

- `before/devtools_performance_rebuilds.png`, `after/devtools_performance_rebuilds.png`: Performance, the build
  frame of a tap selected.
- `before/devtools_cpu_bottom_up.png`, `after/devtools_cpu_bottom_up.png`: CPU Profiler, bottom up.
- `after/devtools_performance_frame_between_taps.png`: a frame between two taps, for comparison (no build).

One selected frame is not the measurement: the build frame in the before screenshot took 15.6 ms and the one after
26.8 ms, because each screenshot shows a different tap. The numbers are the 3 runs above.

## Files

- `before/run1..3`, `after/run1..3`: the `TimelineSummary` of both traces of every run, and `rebuilds.txt`.
- `before/frame_times.csv`, `after/frame_times.csv`: frame metrics of every run and their mean.
- `before/timelines_run1.zip`, `after/timelines_run1.zip`: the full timelines of run 1. Open a `*.timeline.json`
  in Flutter DevTools (Performance, Load data) or in Perfetto to see every frame.
