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


def main(path: str) -> None:
    events = json.load(open(path, encoding='utf-8'))['traceEvents']
    builds = collections.Counter(e['name'] for e in events
                                 if e.get('ph') in ('B', 'X') and e.get('cat', '') != 'Embedder')
    taps = builds['_SelectedPlaceCard']
    widgets = sum(n for name, n in builds.items() if is_widget(name))
    print(f'taps in the trace: {taps}')
    print(f'widget builds per tap: {widgets / taps:.1f}')
    for name in TRACKED:
        print(f'  {name}: {builds[name] / taps:.2f} per tap')


if __name__ == '__main__':
    main(sys.argv[1])
