import 'dart:async';

import 'package:campus_bites/services/restaurant_photos.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  RestaurantPhotos.enabled = false;
  await testMain();
}
