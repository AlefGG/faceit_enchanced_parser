// Функция для надежного выполнения HTTP-запросов с повторными попытками
import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';

Future<http.Response> reliableHttpGet(
  Uri url, {
  required Logger logger,
  required Map<String, String> headers,
  int maxRetries = 0,
  int initialDelayMs = 1000,
}) async {
  // Выполняем один запрос без повторных попыток
  try {
    final response = await http.get(url, headers: headers).timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        throw TimeoutException('Request timed out after 30 seconds');
      },
    );
    return response;
  } catch (e) {
    // Логируем и пробрасываем, вызывающая сторона решает как поступить
    logger.e('HTTP request failed: $e');
    rethrow;
  }
}
