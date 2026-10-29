import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class ApiException implements Exception {
  final int statusCode;

  const ApiException(this.statusCode);

  @override
  String toString() => 'ApiException($statusCode)';
}

/// True when [error] means no HTTP response arrived: no connection, DNS
/// failure or timeout. Only then should a screen fall back to data saved on
/// the phone; an [ApiException] or a response the app can't parse is a real
/// failure and must not be hidden behind stale data.
bool isNetworkError(Object error) =>
    error is TimeoutException ||
    error is IOException ||
    error is http.ClientException;

const apiTimeout = Duration(seconds: 10);

void expectStatus(http.Response response, int expected) {
  if (response.statusCode != expected) throw ApiException(response.statusCode);
}

dynamic decodeJson(http.Response response) =>
    jsonDecode(utf8.decode(response.bodyBytes));
