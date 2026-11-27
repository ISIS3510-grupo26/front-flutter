"""Before/after of the For You search micro-optimization (Sprint 4, Gabriela).

After every `flutter drive` of integration_test/for_you_search_perf_test.dart:

    python docs/profiling/for_you_search/profiling.py collect before 1     (or: after 2, ...)

copies the two summaries of build/ to <before|after>/run<N>/ and adds one row to <before|after>/results.csv.
When there are runs of both:

    python docs/profiling/for_you_search/profiling.py table

prints the table for the wiki (median of the runs).

What is counted, in for_you_search_builds.timeline.json (recorded with debugProfileBuildsEnabled):
- ForYouFeed: one event every time the feed (filters, match %, rain order) is calculated.
- widget builds: one event per widget built, named after the widget.
The search box changes 32 times in the test, so everything is divided by 32.
"""
import collections
import csv
import json
import shutil
import statistics
import sys
from pathlib import Path

HERE = Path(__file__).parent
BUILD = Path('build')
EDITS = 32
KEYS = ['for_you_search', 'for_you_search_builds']
TRACKED = ['ForYouScreen', 'SpotCard', 'SpotPhoto', 'Text']
ENGINE_PREFIXES = ('Dart_', 'Semantics', 'LAYOUT', 'PAINT', 'UPDATING', 'COMPOSITING', 'SEMANTICS', 'Animator',
                   'CreateGlyph', 'NotifyIdle', 'GPURasterizer', 'Rasterizer', 'Shell', 'Engine', 'Frame', 'Vsync',
                   'VSYNC', 'BUILD', 'FINALIZE', 'Pipeline', 'Layer', 'DisplayList', 'SceneDisplayLag', 'EntityPass',
                   'Canvas', 'ImageDecoder', 'Picture', 'Surface', 'Compositor', 'Paint', 'Raster', 'Flutter', 'POST',
                   'CommandBuffer', 'Scheduler', 'ForYouFeed')
COLUMNS = ['run', 'feed_per_edit', 'feed_ms_per_edit', 'widgets_per_edit'] + [f'{w}_per_edit' for w in TRACKED] + [
    'avg_build_ms', 'p90_build_ms', 'p99_build_ms', 'worst_build_ms', 'avg_build_ms_builds_on',
    'missed_budget_builds_on', 'gc_ms']


def is_widget(name: str) -> bool:
    return ((name[:1].isupper() or name.startswith('_')) and not name.startswith(ENGINE_PREFIXES)
            and ' ' not in name and '::' not in name and '.' not in name)


def feed_ms(events) -> float:
    """Total time inside ForYouFeed, pairing each begin with its end on the same thread."""
    total, open_ = 0.0, collections.defaultdict(list)
    for e in events:
        if e.get('name') != 'ForYouFeed':
            continue
        if e.get('ph') == 'X':
            total += e.get('dur', 0)
        elif e.get('ph') == 'B':
            open_[e.get('tid')].append(e['ts'])
        elif e.get('ph') == 'E' and open_[e.get('tid')]:
            total += e['ts'] - open_[e.get('tid')].pop()
    return total / 1000


def gc_ms(summary: dict) -> float:
    # The name changed between Flutter versions.
    for key in ('total_ui_gc_time', 'total_ui_gc_time_millis'):
        if key in summary:
            return summary[key]
    return float('nan')


def collect(phase: str, run: str) -> None:
    out = HERE / phase / f'run{run}'
    out.mkdir(parents=True, exist_ok=True)
    for key in KEYS:
        shutil.copy(BUILD / f'{key}.timeline_summary.json', out)
    plain = json.load(open(BUILD / 'for_you_search.timeline_summary.json', encoding='utf-8'))
    with_builds = json.load(open(BUILD / 'for_you_search_builds.timeline_summary.json', encoding='utf-8'))
    events = json.load(open(BUILD / 'for_you_search.timeline.json', encoding='utf-8'))['traceEvents']
    build_events = json.load(open(BUILD / 'for_you_search_builds.timeline.json', encoding='utf-8'))['traceEvents']

    builds = collections.Counter(e['name'] for e in build_events
                                 if e.get('ph') in ('B', 'X') and e.get('cat', '') != 'Embedder')
    row = {
        'run': run,
        'feed_per_edit': round(builds['ForYouFeed'] / EDITS, 2),
        # From the trace without build profiling, so the time is not inflated.
        'feed_ms_per_edit': round(feed_ms(events) / EDITS, 3),
        'widgets_per_edit': round(sum(n for name, n in builds.items() if is_widget(name)) / EDITS, 1),
        **{f'{w}_per_edit': round(builds[w] / EDITS, 2) for w in TRACKED},
        'avg_build_ms': round(plain['average_frame_build_time_millis'], 2),
        'p90_build_ms': round(plain['90th_percentile_frame_build_time_millis'], 2),
        'p99_build_ms': round(plain['99th_percentile_frame_build_time_millis'], 2),
        'worst_build_ms': round(plain['worst_frame_build_time_millis'], 2),
        'avg_build_ms_builds_on': round(with_builds['average_frame_build_time_millis'], 2),
        'missed_budget_builds_on': with_builds['missed_frame_build_budget_count'],
        'gc_ms': round(gc_ms(plain), 1),
    }
    csv_path = HERE / phase / 'results.csv'
    new = not csv_path.exists()
    with open(csv_path, 'a', newline='', encoding='utf-8') as f:
        writer = csv.DictWriter(f, fieldnames=COLUMNS)
        if new:
            writer.writeheader()
        writer.writerow(row)
    # The full timeline of the first run, to open in DevTools (Performance > Load data).
    if run == '1':
        for key in KEYS:
            shutil.copy(BUILD / f'{key}.timeline.json', out)
    for name, value in row.items():
        print(f'{name}: {value}')


def table() -> None:
    def read(phase):
        with open(HERE / phase / 'results.csv', encoding='utf-8') as f:
            return list(csv.DictReader(f))

    before, after = read('before'), read('after')
    print('| Metric | Before (median) | After (median) | Change | Before, runs | After, runs |')
    print('|---|---|---|---|---|---|')
    for column in COLUMNS[1:]:
        b = [float(r[column]) for r in before]
        a = [float(r[column]) for r in after]
        mb, ma = statistics.median(b), statistics.median(a)
        change = f'{(ma - mb) / mb * 100:+.0f}%' if mb else '—'
        runs = lambda values: ' / '.join(f'{v:g}' for v in values)
        print(f'| {column} | {mb:g} | {ma:g} | {change} | {runs(b)} | {runs(a)} |')


if __name__ == '__main__':
    if len(sys.argv) == 4 and sys.argv[1] == 'collect' and sys.argv[2] in ('before', 'after'):
        collect(sys.argv[2], sys.argv[3])
    elif len(sys.argv) == 2 and sys.argv[1] == 'table':
        table()
    else:
        print(__doc__)
        sys.exit(1)
