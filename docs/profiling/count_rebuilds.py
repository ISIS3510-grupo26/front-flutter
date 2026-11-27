"""Counts which widgets rebuild on each pin tap in a *_builds.timeline.json.

The integration test records that trace with debugProfileBuildsEnabled, so
every widget build is one timeline event named after the widget. The place
card (_SelectedPlaceCard) rebuilds exactly once per tap in both versions, so
it is used to count the taps that fit in the trace.

    python docs/profiling/count_rebuilds.py build/taste_map_pin_taps_builds.timeline.json
"""
import collections
import json
import sys

ENGINE_PREFIXES = ('Dart_', 'Semantics', 'LAYOUT', 'PAINT', 'UPDATING', 'COMPOSITING', 'SEMANTICS', 'Animator',
                   'CreateGlyph', 'NotifyIdle', 'GPURasterizer', 'Rasterizer', 'Shell', 'Engine', 'Frame', 'Vsync',
                   'VSYNC', 'BUILD', 'FINALIZE', 'Pipeline', 'Layer', 'DisplayList', 'SceneDisplayLag', 'EntityPass',
                   'Canvas', 'ImageDecoder', 'Picture', 'Surface', 'Compositor', 'Paint', 'Raster', 'Flutter', 'POST',
                   'CommandBuffer', 'Scheduler')
TRACKED = ['FlutterMap', 'TileLayer', 'MarkerLayer', 'Tile', '_Pin', '_PinSlot', '_SelectedPlaceCard']


def is_widget(name: str) -> bool:
    return ((name[:1].isupper() or name.startswith('_')) and not name.startswith(ENGINE_PREFIXES)
            and ' ' not in name and '::' not in name and '.' not in name)


def main(path: str, per: str = '_SelectedPlaceCard', tracked: list[str] = TRACKED, unit: str = 'tap') -> None:
    events = json.load(open(path, encoding='utf-8'))['traceEvents']
    builds = collections.Counter(e['name'] for e in events
                                 if e.get('ph') in ('B', 'X') and e.get('cat', '') != 'Embedder')
    taps = builds[per]
    widgets = sum(n for name, n in builds.items() if is_widget(name))
    if taps == 0:  # nothing is built once per action (a scroll): totals for the whole trace
        print(f'widget builds in the trace: {widgets}')
        for name in tracked:
            print(f'  {name}: {builds[name]} in total')
        return
    print(f'{unit}s in the trace: {taps}')
    print(f'widget builds per {unit}: {widgets / taps:.1f}')
    for name in tracked:
        print(f'  {name}: {builds[name] / taps:.2f} per {unit}')


if __name__ == '__main__':
    # Taste Map (default):  count_rebuilds.py <timeline.json>
    # Any other screen:     count_rebuilds.py <timeline.json> <widget built once per action> <tracked,widgets>
    #   e.g. count_rebuilds.py build/reviews_rebuild_builds.timeline.json PlaceDetailScreen _ReviewCard,_Avatar
    if len(sys.argv) > 2:
        main(sys.argv[1], sys.argv[2], sys.argv[3].split(',') if len(sys.argv) > 3 else [], unit='action')
    else:
        main(sys.argv[1])
