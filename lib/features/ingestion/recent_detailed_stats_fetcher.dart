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
    // New fast path: single endpoint returns recent match stats list
    final items = await api.fetchRecentPlayerGameStats(playerId, limit: limit);
    if (items.isNotEmpty) {
      for (final it in items) {
        if (it['stats'] is! Map) continue;
        final stats = (it['stats'] as Map).cast<String, dynamic>();
        String? mid() => stats['Match Id']?.toString();
        final matchId = mid();
        if (matchId == null || matchId.isEmpty) continue;
        // Ensure the match exists in matches table to satisfy FK constraint
        // Some recent matches might not yet be ingested through history endpoint.
        try {
          final exists = await matchRepo.exists(matchId);
          if (!exists) {
            int? toIntScorePart(String s) => int.tryParse(s.trim());
            int? parseScorePart(String part) => toIntScorePart(part);
            int? score1;
            int? score2;
            final scoreStr =
                stats['Score']?.toString() ?? stats['Final Score']?.toString();
            if (scoreStr != null && scoreStr.contains('/')) {
              final parts = scoreStr.split('/');
              if (parts.length == 2) {
                score1 = parseScorePart(parts[0]);
                score2 = parseScorePart(parts[1]);
              }
            }
            // Finished at might be ms; normalize to seconds
            int? finishedAt;
            final faRaw = stats['Match Finished At'];
            if (faRaw != null) {
              final faNum = int.tryParse(faRaw.toString());
              if (faNum != null) {
                finishedAt =
                    faNum > 1000000000000 ? (faNum ~/ 1000) : faNum; // ms vs s
              }
            }
            // Use finishedAt also as date if no separate start timestamp.
            final dateVal = finishedAt ?? 0;
            await matchRepo.insertMatch({
              'match_id': matchId,
              'game_mode': stats['Game Mode']?.toString(),
              'map': stats['Map']?.toString(),
              'region': stats['Region']?.toString(),
              'date': dateVal,
              'finished_at': finishedAt ?? dateVal,
              'score_faction1': score1,
              'score_faction2': score2,
              'competition_type': 'matchmaking',
            });
          }
        } catch (e) {
          logger.w('Failed ensuring match row for $matchId: $e');
        }
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
          'double_kills': toInt('Double Kills'),
          'triple_kills': toInt('Triple Kills'),
          'quadro_kills': toInt('Quadro Kills'),
          'penta_kills': toInt('Penta Kills'),
          'rounds': toInt('Rounds'),
          'first_half_score': toInt('First Half Score'),
          'second_half_score': toInt('Second Half Score'),
          'overtime_score': toInt('Overtime score'),
          'result': toInt('Result'),
          'map': stats['Map']?.toString(),
          'team': stats['Team']?.toString(),
          'winner': stats['Winner']?.toString(),
          'score_for': () {
            final s = stats['Score']?.toString();
            if (s != null && s.contains('/')) {
              return int.tryParse(s.split('/')[0].trim());
            }
            return null;
          }(),
          'score_against': () {
            final s = stats['Score']?.toString();
            if (s != null && s.contains('/')) {
              return int.tryParse(s.split('/')[1].trim());
            }
            return null;
          }(),
          'match_finished_at': () {
            final v = stats['Match Finished At'];
            if (v == null) return null;
            final n = int.tryParse(v.toString());
            if (n == null) return null;
            return n > 1000000000000 ? (n ~/ 1000) : n;
          }(),
        });
        // Ensure player_matches link exists (ignore errors on duplicate)
        try {
          await matchRepo.linkPlayerToMatch({
            'match_id': matchId,
            'player_id': playerId,
            'team': null,
            'result': null,
            'nickname': null,
            'country': null,
            'skill_level': null,
            'faceit_elo': null,
          });
        } catch (_) {}
      }
      return; // success path complete
    }
    // No legacy fallback anymore: we rely solely on the new endpoint per requirements.
  }
}
