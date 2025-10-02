// Функция для надежного выполнения HTTP-запросов с повторными попытками
import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';

Future<http.Response> reliableHttpGet(
  Uri url, {
  required Logger logger,
  required Map<String, String> headers,
  int maxRetries = 5,
  int initialDelayMs = 1000,
}) async {
  int retryCount = 0;
  int delayMs = initialDelayMs;

  while (true) {
    try {
      // Попытка выполнить запрос с увеличенным таймаутом
      final response = await http.get(url, headers: headers).timeout(
        const Duration(seconds: 30), // Увеличиваем таймаут до 30 секунд
        onTimeout: () {
          throw TimeoutException('Request timed out after 30 seconds');
        },
      );

      // Проверяем коды ответа для определения необходимости повторных попыток
      if (response.statusCode == 429) {
        // Too Many Requests
        logger.w('Rate limited by FACEIT API, will retry');
        throw Exception('Rate limited');
      }

      return response; // Успешный запрос
    } catch (e) {
      retryCount++;

      if (retryCount > maxRetries) {
        logger.e('Failed after $maxRetries retries: $e');
        rethrow; // Больше не пытаемся, пробрасываем ошибку
      }

      // Экспоненциальное увеличение задержки между попытками
      logger.w('Request failed (attempt $retryCount/$maxRetries): $e');
      logger.i('Retrying in ${delayMs}ms...');

      await Future.delayed(Duration(milliseconds: delayMs));
      delayMs *= 2; // Экспоненциальный рост задержки
    }
  }
}
