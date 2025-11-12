import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';

import '../core/config.dart';

class HttpClientWrapper {
  final Logger logger;
  final Map<String, String> defaultHeaders;
  final Duration timeout;
  final Duration requestDelay;
  final Duration rateLimitBackoff;
  final int maxRateLimitRetries;
  final List<String> _bearerTokens;
  int _tokenIndex = 0;

  HttpClientWrapper({
    required this.logger,
    Map<String, String>? defaultHeaders,
    List<String>? bearerTokens,
    this.timeout = const Duration(seconds: 30),
    Duration? requestDelay,
    Duration? rateLimitBackoff,
    int? maxRateLimitRetries,
  })  : defaultHeaders = Map.unmodifiable(defaultHeaders ?? const {}),
        _bearerTokens =
            bearerTokens?.where((t) => t.trim().isNotEmpty).toList() ??
                const [],
        requestDelay =
            requestDelay ?? Duration(milliseconds: AppConfig.requestDelayMs),
        rateLimitBackoff = rateLimitBackoff ??
            Duration(seconds: AppConfig.rateLimitBackoffSeconds),
        maxRateLimitRetries =
            maxRateLimitRetries ?? AppConfig.maxRateLimitRetries;

  Future<http.Response> get(Uri url, {Map<String, String>? headers}) async {
    http.Response? lastResponse;
    try {
      for (var attempt = 0; attempt <= maxRateLimitRetries; attempt++) {
        if (requestDelay > Duration.zero) {
          await Future.delayed(requestDelay);
        }

        final merged = <String, String>{
          ...defaultHeaders,
          if (headers != null) ...headers,
        };
        final token = _nextTokenOrNull();
        if (token != null) {
          merged['Authorization'] = 'Bearer $token';
        }

        final response = await http.get(url, headers: merged).timeout(timeout,
            onTimeout: () => throw TimeoutException('GET $url timed out'));

        if (response.statusCode != 429) {
          return response;
        }

        lastResponse = response;

        if (attempt == maxRateLimitRetries) {
          logger.w(
              'HTTP 429 persisted after $maxRateLimitRetries retries for $url');
          return response;
        }

        final retryAfter =
            _parseRetryAfterSeconds(response.headers['retry-after']);
        final wait = retryAfter ?? rateLimitBackoff.inSeconds;
        logger.w(
            'HTTP 429 from $url. Waiting ${wait}s before retry ${attempt + 1}/$maxRateLimitRetries.');
        await Future.delayed(Duration(seconds: wait));
      }
    } catch (e) {
      logger.e('HTTP GET failed $url: $e');
      rethrow;
    }
    // Should not reach here, but return lastResponse if available.
    if (lastResponse != null) return lastResponse;
    throw StateError(
        'HTTP GET $url failed without response and without exception');
  }

  String? _nextTokenOrNull() {
    if (_bearerTokens.isEmpty) return null;
    final token = _bearerTokens[_tokenIndex];
    _tokenIndex = (_tokenIndex + 1) % _bearerTokens.length;
    return token;
  }

  int? _parseRetryAfterSeconds(String? header) {
    if (header == null) return null;
    final trimmed = header.trim();
    if (trimmed.isEmpty) return null;
    final seconds = int.tryParse(trimmed);
    if (seconds != null) return seconds;
    // HTTP-date format fallback is not expected from Faceit; ignore if parsing fails.
    return null;
  }
}
