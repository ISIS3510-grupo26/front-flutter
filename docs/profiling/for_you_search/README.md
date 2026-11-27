# For You search micro-optimization: profiling before and after

Sprint 4, item 3 (Gabriela). Code: `lib/screens/for_you_screen.dart`.

## The problem

For You listened to the search box with `_search.addListener(() => setState(() {}))`. A `TextEditingController`
notifies its listeners on every change of its value, and the value is the text **and** the selection, so moving the
cursor, selecting a word or the keyboard updating its suggestion also called `setState`. Every `setState` ran the
whole `build()`, and `build()` calculated the feed again from zero: filter the spots, copy each one with its
match % (smart feature), sort them by match and order them again if it rains. Then every visible `SpotCard` was
built again, even when the feed was exactly the same as one frame before.

## The optimization

Two micro-optimizations, both in `_ForYouScreenState`:

1. **Only rebuild for a change the student can see.** `_onSearchChanged` keeps the trimmed query (`_query`) and
   whether the box is empty (for the clear button). If neither changed (cursor moved, text selected, space at the
   end) it returns without `setState`.
2. **Memoization of the feed and its cards.** `build()` puts everything the feed depends on in a record:
   `(spots, matchScores, query, filtersVersion, weather, openSpot, onToggleSaved)`. Records compare field by field,
   and lists and maps by identity, which is correct here because `HomeShell` always gives a new list or map when
   something changes (it never edits them in place). If the record is equal to the last one, `build()` reuses the
   same `_feed` and the same `SpotCard` objects. Flutter compares the old and new widget and, when it is the same
   instance, skips that whole subtree.

`_filtersVersion` exists because `_activeFilters` is a `Set` that changes in place: the same set object would look
"equal" after a change, so the number goes up on each toggle.

## What was measured

The integration test `integration_test/for_you_search_perf_test.dart` opens For You with 60 spots, each with a
different match %, while it rains, and edits the search 32 times: types "burger" letter by letter, moves the cursor
3 times after each letter, adds a space at the end and deletes letter by letter. The Flutter timeline is recorded
twice:

1. `for_you_search`: frame times as they are.
2. `for_you_search_builds`: the same edits with `debugProfileBuildsEnabled`, which adds one timeline event per
   widget build, to count what rebuilds.

`ForYouFeed` is a `Timeline.timeSync` event around the feed calculation (it is in both versions), so the timeline
shows how many times the feed was calculated and how long it took.

Tool: Flutter timeline recorded by `integration_test` (`binding.traceAction`) in **profile mode**, summarized by
`flutter_driver`'s `TimelineSummary`. Device: **(phone model, Android version)**. 3 runs before and 3 after.

```
flutter drive --profile --no-dds --driver=test_driver/perf_driver.dart --target=integration_test/for_you_search_perf_test.dart
python docs/profiling/for_you_search/profiling.py collect before 1
...
python docs/profiling/for_you_search/profiling.py table
```

"Before" is commit `Profiling: prueba de la búsqueda de For You...` and "after" is the next one,
`Micro-optimización: For You calcula el feed...`.

## Results

(table from `profiling.py table`)

What each row means:

- `feed_per_edit`: times the feed was calculated for each change of the search box.
- `feed_ms_per_edit`: milliseconds inside `ForYouFeed` for each change.
- `widgets_per_edit`, `SpotCard_per_edit`...: widgets built for each change.
- `avg_build_ms`, `p90_build_ms`, `p99_build_ms`, `worst_build_ms`: UI thread time per frame (budget: 16 ms at 60 Hz).
- `avg_build_ms_builds_on`, `missed_budget_builds_on`: the same with build profiling on (slower, only compared with
  each other).
- `gc_ms`: garbage collection time on the UI thread (fewer copies of spots and widgets, less garbage).

## Files

- `before/run1..3`, `after/run1..3`: the `TimelineSummary` of both traces of every run. Run 1 also has the full
  timelines (`*.timeline.json`): open them in Flutter DevTools (Performance, Load data) to see every frame and the
  `ForYouFeed` events.
- `before/results.csv`, `after/results.csv`: one row per run.
