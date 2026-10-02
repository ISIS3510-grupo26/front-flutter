class ApiConfig {
  // 10.0.2.2 is the Android emulator's alias for the host machine.
  static const baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000/api/v1',
  );

  // TEMPORARY until auth exists: supply with --dart-define=DEV_USER_ID=<id>.
  // Empty means no signed-in user.
  static const devUserId = String.fromEnvironment('DEV_USER_ID');
}
