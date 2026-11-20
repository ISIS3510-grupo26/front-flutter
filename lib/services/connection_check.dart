import 'package:connectivity_plus/connectivity_plus.dart';

/// Answers whether the phone has no network right now. Screens receive it as a parameter so tests can say 
/// "offline" without turning off the computer.
typedef OfflineCheck = Future<bool> Function();

/// If the plugin can't answer, the screen acts as online: a request that fails afterwards still tells the 
/// student what happened.
Future<bool> phoneIsOffline() async {
  try {
    final results = await Connectivity().checkConnectivity();
    return results.every((r) => r == ConnectivityResult.none);
  } on Exception {
    return false;
  }
}
