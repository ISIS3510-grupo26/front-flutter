import 'package:campus_bites/services/reconnect_retry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final waited = <Duration>[];
  Future<void> fakeWait(Duration d) async => waited.add(d);

  setUp(waited.clear);

  test('stops as soon as an attempt gets fresh data', () async {
    var attempts = 0;
    final ok = await retryAfterReconnect(() async => ++attempts == 2, wait: fakeWait);

    expect(ok, isTrue);
    expect(attempts, 2);
    expect(waited, [const Duration(seconds: 1), const Duration(seconds: 3)]);
  });

  test('gives up after the last wait when the network never works', () async {
    var attempts = 0;
    final ok = await retryAfterReconnect(() async {
      attempts++;
      return false;
    }, wait: fakeWait);

    expect(ok, isFalse);
    expect(attempts, 3);
    expect(waited, [
      const Duration(seconds: 1),
      const Duration(seconds: 3),
      const Duration(seconds: 6),
    ]);
  });
}
