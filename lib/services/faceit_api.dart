import 'dart:convert';
import 'package:logger/logger.dart';
import '../utils/http_client.dart';

class FaceitApi {
  final HttpClientWrapper http;
  final Logger logger;
  FaceitApi({required this.http, required this.logger});

  Future<List<Map<String, dynamic>>> fetchTopPlayers(
      {required int offset, required int limit}) async {
    final url = Uri.parse(
        'https://open.faceit.com/data/v4/rankings/games/cs2/regions/EU?offset=$offset&limit=$limit');
    final resp = await http.get(url);
    if (resp.statusCode != 200) {
      logger.w('Top players request failed ${resp.statusCode} ${resp.body}');
      return [];
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(data['items'] ?? []);
  }

  Future<List<Map<String, dynamic>>> fetchPlayerMatchesPage(String playerId,
      {required int offset, required int limit}) async {
    final url = Uri.parse(
        'https://open.faceit.com/data/v4/players/$playerId/history?game=cs2&offset=$offset&limit=$limit');
    final resp = await http.get(url);
    if (resp.statusCode != 200) {
      logger.w('History request failed ${resp.statusCode} ${resp.body}');
      return [];
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(data['items'] ?? []);
  }

  Future<Map<String, dynamic>?> fetchPlayerStats(String playerId) async {
    final url = Uri.parse(
        'https://open.faceit.com/data/v4/players/$playerId/stats/cs2');
    final resp = await http.get(url);
    if (resp.statusCode == 404) {
      logger.i('Stats 404 for $playerId');
      return null;
    }
    if (resp.statusCode != 200) {
      logger.w('Stats request failed ${resp.statusCode} ${resp.body}');
      return null;
    }
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>?> fetchMatchDetailedStats(String matchId) async {
    final url =
        Uri.parse('https://open.faceit.com/data/v4/matches/$matchId/stats');
    final resp = await http.get(url);
    if (resp.statusCode != 200) {
      logger.w('Detailed stats request failed $matchId ${resp.statusCode}');
      return null;
    }
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  /// Fetch recent per-match stats for a player (single aggregated endpoint).
  /// Example: /players/{id}/games/cs2/stats?offset=0&limit=20
  /// Returns list of objects each containing a 'stats' map with keys like:
  ///  'Match Id', 'Kills', 'Deaths', 'Assists', 'ADR', 'K/R Ratio', 'K/D Ratio', 'Headshots', 'Headshots %', 'MVPs', etc.
  Future<List<Map<String, dynamic>>> fetchRecentPlayerGameStats(String playerId,
      {int offset = 0, int limit = 20}) async {
    final url = Uri.parse(
        'https://open.faceit.com/data/v4/players/$playerId/games/cs2/stats?offset=$offset&limit=$limit');
    final resp = await http.get(url);
    if (resp.statusCode != 200) {
      logger.w(
          'Recent game stats request failed ${resp.statusCode} ${resp.body}');
      return [];
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(data['items'] ?? []);
  }

  /// Basic player profile (country, nickname, games.cs2.faceit_elo, skill_level)
  Future<Map<String, dynamic>?> fetchPlayerProfile(String playerId) async {
    final url = Uri.parse('https://open.faceit.com/data/v4/players/$playerId');
    final resp = await http.get(url);
    if (resp.statusCode == 404) {
      logger.i('Profile 404 for $playerId');
      return null;
    }
    if (resp.statusCode != 200) {
      logger.w('Profile request failed ${resp.statusCode} ${resp.body}');
      return null;
    }
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }
}
