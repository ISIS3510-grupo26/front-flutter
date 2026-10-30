import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// One accelerometer reading in m/s² (x, y, z axes of the phone).
typedef AccelerationReading = ({double x, double y, double z});

/// Sensor: detects when the student shakes the phone, using the accelerometer without gravity 
/// (`userAccelerometer`), so a phone lying on the table reads ~0 and only real movement counts.
/// A shake = [peaksNeeded] strong movements (over [threshold]) within
/// [window]. After a shake it waits [cooldown] so one shake fires once.
class ShakeDetector {
  /// A normal hand movement stays under ~5 m/s²; a shake goes well over 13.
  static const threshold = 13.0;
  static const peaksNeeded = 2;
  static const window = Duration(milliseconds: 800);
  static const cooldown = Duration(seconds: 2);
  static const _samePeak = Duration(milliseconds: 120);

  final Stream<AccelerationReading> Function() _readings;
  final DateTime Function() _now;
  StreamSubscription<AccelerationReading>? _subscription;
  final _peaks = <DateTime>[];
  DateTime? _lastShake;

  ShakeDetector({Stream<AccelerationReading> Function()? readings, DateTime Function()? now})
      : _readings = readings ?? _phoneAccelerometer,
        _now = now ?? DateTime.now;

  static Stream<AccelerationReading> _phoneAccelerometer() =>
      userAccelerometerEventStream(samplingPeriod: SensorInterval.gameInterval)
          .map((e) => (x: e.x, y: e.y, z: e.z));

  bool get isListening => _subscription != null;

  /// Starts listening to the sensor. Only while For You is on screen and the
  /// app is open: an accelerometer that is always on drains the battery.
  void start(VoidCallback onShake) {
    stop();
    _subscription = _readings().listen(
      (reading) => _onReading(reading, onShake),
      // A phone without accelerometer: the shake just doesn't work, the app does.
      onError: (Object _) => stop(),
    );
  }

  void stop() {
    _subscription?.cancel();
    _subscription = null;
    _peaks.clear();
  }

  void _onReading(AccelerationReading r, VoidCallback onShake) {
    final strength = sqrt(r.x * r.x + r.y * r.y + r.z * r.z);
    if (strength < threshold) return;
    final now = _now();
    if (_peaks.isNotEmpty && now.difference(_peaks.last) < _samePeak) return;
    _peaks
      ..add(now)
      ..removeWhere((t) => now.difference(t) > window);
    final lastShake = _lastShake;
    final cooling = lastShake != null && now.difference(lastShake) < cooldown;
    if (_peaks.length >= peaksNeeded && !cooling) {
      _lastShake = now;
      _peaks.clear();
      onShake();
    }
  }
}
