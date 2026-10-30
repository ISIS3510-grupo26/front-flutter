import 'package:http/http.dart' as http;

import '../repositories/api_exception.dart';

/// Current weather on campus, from Open-Meteo.
class WeatherNow {
  final double temperatureC;
  final double precipitationMm;

  /// WMO weather interpretation code (0 clear, 61 rain, 95 storm...).
  final int weatherCode;

  const WeatherNow({
    required this.temperatureC,
    required this.precipitationMm,
    required this.weatherCode,
  });

  factory WeatherNow.fromOpenMeteo(Map<String, dynamic> json) {
    final current = json['current'] as Map<String, dynamic>;
    return WeatherNow(
      temperatureC: (current['temperature_2m'] as num).toDouble(),
      precipitationMm: (current['precipitation'] as num?)?.toDouble() ?? 0,
      weatherCode: current['weather_code'] as int,
    );
  }

  /// Drizzle (51-57), rain (61-67), showers (80-82) and storms (95-99) in the WMO table, or any measured precipitation.
  bool get isRaining =>
      precipitationMm > 0.1 ||
      (weatherCode >= 51 && weatherCode <= 67) ||
      (weatherCode >= 80 && weatherCode <= 82) ||
      weatherCode >= 95;

  String get description => switch (weatherCode) {
        0 => 'Clear',
        1 || 2 => 'Partly cloudy',
        45 || 48 => 'Foggy',
        >= 51 && <= 57 => 'Drizzle',
        >= 61 && <= 67 || >= 80 && <= 82 => 'Rain',
        >= 95 => 'Storm',
        _ => 'Cloudy',
      };

  String get emoji => isRaining
      ? '🌧️'
      : switch (weatherCode) {
          0 => '☀️',
          1 || 2 => '⛅',
          _ => '☁️',
        };

  String get label => '${temperatureC.round()}° · $description';
}

/// External service
/// Asks Open-Meteo (free, no API key) for the weather at campus. It uses its own plain http.Client, never the 
/// AuthClient, the student's token must not be sent to a third party. It also does not use the GPS, the campus 
/// point is enough and needs no permission.
class WeatherService {
  static const campusLat = 4.6015;
  static const campusLng = -74.0660;
  static const cacheFor = Duration(minutes: 10);
  static const timeout = Duration(seconds: 5);

  /// Demo only: `--dart-define=DEMO_WEATHER=rain` pretends it is raining, 
  /// to show the rain mode in the Viva Voce.
  static const _demo = String.fromEnvironment('DEMO_WEATHER');

  final http.Client _client;
  final String _baseUrl;
  final DateTime Function() _now;
  WeatherNow? _cached;
  DateTime? _cachedAt;

  WeatherService({
    required this._client,
    this._baseUrl = 'https://api.open-meteo.com/v1/forecast',
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// Null when the weather is unknown (no connection, service down).
  Future<WeatherNow?> current() async {
    if (_demo == 'rain') {
      return const WeatherNow(temperatureC: 14, precipitationMm: 1.2, weatherCode: 63);
    }
    final cachedAt = _cachedAt;
    if (_cached != null && cachedAt != null && _now().difference(cachedAt) < cacheFor) return _cached;
    try {
      final uri = Uri.parse(_baseUrl).replace(queryParameters: {
        'latitude': '$campusLat',
        'longitude': '$campusLng',
        'current': 'temperature_2m,precipitation,weather_code',
      });
      final response = await _client.get(uri).timeout(timeout);
      expectStatus(response, 200);
      _cached = WeatherNow.fromOpenMeteo(decodeJson(response) as Map<String, dynamic>);
      _cachedAt = _now();
    } on Object {
      // Keep the last known weather, if any, instead of failing the feed.
    }
    return _cached;
  }
}
