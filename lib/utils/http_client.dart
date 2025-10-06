import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';

class HttpClientWrapper {
  final Logger logger;
  final Map<String, String> defaultHeaders;
  final Duration timeout;

  HttpClientWrapper({
    required this.logger,
    required this.defaultHeaders,
    this.timeout = const Duration(seconds: 30),
  });

  Future<http.Response> get(Uri url, {Map<String, String>? headers}) async {
    try {
      final merged = {...defaultHeaders, if (headers != null) ...headers};
      final resp = await http.get(url, headers: merged).timeout(timeout,
          onTimeout: () => throw TimeoutException('GET $url timed out'));
      return resp;
    } catch (e) {
      logger.e('HTTP GET failed $url: $e');
      rethrow;
    }
  }
}
