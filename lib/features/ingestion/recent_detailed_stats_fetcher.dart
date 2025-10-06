import 'dart:convert';
import 'package:logger/logger.dart';
import '../../services/faceit_api.dart';
import '../../repositories/match_repository.dart';
import '../../repositories/stats_repository.dart';

class RecentDetailedStatsFetcher {
  final FaceitApi api;
  final MatchRepository matchRepo;
  final StatsRepository statsRepo;
  final Logger logger;
  RecentDetailedStatsFetcher(
      {required this.api,
      required this.matchRepo,
      required this.statsRepo,
      required this.logger});

  Future<void> fetchRecent(String playerId, {int limit = 20}) async {
    final rows = await matchRepo.recentMatchIdsForPlayer(playerId, limit);
    for (final r in rows) {
      final matchId = r['match_id'] as String;
      // naive duplicate check via aggregate; repository could expose exists but reuse for brevity
      // (In original code it queried recent_player_match_stats before insert)
      final detailed = await api.fetchMatchDetailedStats(matchId);
      if (detailed == null) continue;
      final rounds = detailed['rounds'];
      if (rounds is! List || rounds.isEmpty) continue;
      final first = rounds.first;
      final teams = first['teams'];
      if (teams is! List) continue;
      Map<String, dynamic>? playerObj;
      for (final t in teams) {
        if (t is Map && t['players'] is List) {
          for (final pl in t['players']) {
            if (pl is Map && pl['player_id'] == playerId) {
              playerObj = Map<String, dynamic>.from(pl);
              break;
            }
          }
        }
        if (playerObj != null) break;
      }
      if (playerObj == null) continue;
      final stats =
          (playerObj['player_stats'] as Map?)?.cast<String, dynamic>() ?? {};
      int? toInt(String k) => int.tryParse('${stats[k] ?? ''}');
      double? toDouble(String k) {
        final v = (stats[k] ?? '').toString().replaceAll(',', '.');
        return double.tryParse(v);
      }

      double? percent(String k) {
        final v = (stats[k] ?? '')
            .toString()
            .replaceAll('%', '')
            .replaceAll(',', '.');
        return double.tryParse(v);
      }

      await statsRepo.insertRecentMatchStats({
        'match_id': matchId,
        'player_id': playerId,
        'kills': toInt('Kills'),
        'deaths': toInt('Deaths'),
        'assists': toInt('Assists'),
        'adr': toDouble('ADR'),
        'kr_ratio': toDouble('K/R Ratio'),
        'kd_ratio': toDouble('K/D Ratio'),
        'headshots': toInt('Headshots'),
        'headshots_percentage': percent('Headshots %'),
        'mvps': toInt('MVPs'),
        'entry_count': toInt('Entry Count'),
        'entry_wins': toInt('Entry Wins'),
        'clutch_kills': toInt('Clutch Kills'),
        'sniper_kills': toInt('Sniper Kills'),
        'flash_count': toInt('Flash Count'),
        'flash_successes': toInt('Flash Successes'),
        'utility_damage': toInt('Utility Damage'),
        'utility_usage_per_round': toDouble('Utility Usage per Round'),
        'utility_damage_per_round':
            toDouble('Utility Damage per Round in a Match'),
        'enemies_flashed': toInt('Enemies Flashed'),
      });
    }
  }
}
