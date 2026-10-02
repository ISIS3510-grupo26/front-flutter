import 'dart:convert';

import 'package:http/http.dart' as http;

class ApiException implements Exception {
  final int statusCode;

  const ApiException(this.statusCode);

  @override
  String toString() => 'ApiException($statusCode)';
}

const apiTimeout = Duration(seconds: 10);

void expectStatus(http.Response response, int expected) {
  if (response.statusCode != expected) throw ApiException(response.statusCode);
}

dynamic decodeJson(http.Response response) =>
    jsonDecode(utf8.decode(response.bodyBytes));
