/// Eventual connectivity: retry after the connection comes back.
///
/// Android reports Wi-Fi or mobile data as soon as the radio connects, but
/// for a second or two the network is often not usable yet (DNS, captive
/// portal, mobile data still attaching). A single reload at that moment fails
/// and the screen would stay offline until the student refreshes by hand.
///
/// So [attempt] runs after each wait in [waits] until it returns true (fresh
/// data arrived, or the screen no longer needs it) or the waits run out.
/// Returns true when an attempt succeeded.
///
/// [wait] is the clock; tests pass one that doesn't really wait.
Future<bool> retryAfterReconnect(
  Future<bool> Function() attempt, {
  List<Duration> waits = const [
    Duration(seconds: 1),
    Duration(seconds: 3),
    Duration(seconds: 6),
  ],
  Future<void> Function(Duration) wait = _delay,
}) async {
  for (final duration in waits) {
    await wait(duration);
    if (await attempt()) return true;
  }
  return false;
}

Future<void> _delay(Duration duration) => Future<void>.delayed(duration);
