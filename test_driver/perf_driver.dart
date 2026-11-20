import 'package:flutter_driver/flutter_driver.dart' as driver;
import 'package:integration_test/integration_test_driver.dart';

/// Writes `build/<key>.timeline.json` (open it in DevTools or Perfetto) and
/// `build/<key>.timeline_summary.json` (frame build and raster times) for
/// every traceAction of the integration test.
Future<void> main() => integrationDriver(
      responseDataCallback: (data) async {
        if (data == null) return;
        for (final entry in data.entries) {
          final timeline = driver.Timeline.fromJson(entry.value as Map<String, dynamic>);
          await driver.TimelineSummary.summarize(timeline)
              .writeTimelineToFile(entry.key, pretty: true, includeSummary: true);
        }
      },
    );
