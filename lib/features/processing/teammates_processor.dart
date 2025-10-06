import 'package:logger/logger.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../repositories/teammate_repository.dart';
import '../../repositories/player_repository.dart';
import '../../repositories/stats_repository.dart';
import '../ingestion/player_stats_fetcher.dart';
import '../../services/faceit_api.dart';

class TeammatesProcessor {
  final TeammateRepository teammateRepo;
  final PlayerRepository playerRepo;
  final StatsRepository statsRepo;
  final PlayerStatsFetcher statsFetcher;
  final FaceitApi api;
  final Logger logger;

  TeammatesProcessor({
    required this.teammateRepo,
    required this.playerRepo,
    required this.statsRepo,
    required this.statsFetcher,
    required this.api,
    required this.logger,
  });

  Future<void> process(Database db, String playerId,
      {int minMatches = 5, bool fetchMissingStats = true}) async {
    final playerMatches = await db
        .query('player_matches', where: 'player_id = ?', whereArgs: [playerId]);
    if (playerMatches.isEmpty) {
      logger.d('No matches for $playerId -> skip teammates');
      return;
    }

    final counts = <String, Map<String, int>>{}; // teammateId -> stats
    for (final pm in playerMatches) {
      final matchId = pm['match_id'] as String;
      final team = pm['team'] as String?;
      final result = pm['result'] as int? ?? 0;
      if (team == null) continue;
      final teammatesInMatch = await db.query('player_matches',
          where: 'match_id = ? AND team = ? AND player_id != ?',
          whereArgs: [matchId, team, playerId]);
      for (final t in teammatesInMatch) {
        final tid = t['player_id'] as String;
        final entry = counts.putIfAbsent(tid, () => {'matches': 0, 'wins': 0});
        entry['matches'] = (entry['matches'] ?? 0) + 1;
        if (result == 1) entry['wins'] = (entry['wins'] ?? 0) + 1;
      }
    }

    final filtered = counts.entries
        .where((e) => (e.value['matches'] ?? 0) >= minMatches)
        .toList();
    if (filtered.isEmpty) {
      logger.d('No teammates meeting threshold ($minMatches) for $playerId');
      return;
    }

    for (final e in filtered) {
      final teammateId = e.key;
      await teammateRepo.upsertTeammate(
          playerId, teammateId, e.value['matches'] ?? 0, e.value['wins'] ?? 0);
      if (fetchMissingStats) {
        try {
          await statsFetcher.fetchIfNeeded(teammateId);
        } catch (err) {
          logger.w('Failed to fetch stats for teammate $teammateId: $err');
        }
        // Backfill profile info (elo, country, skill level) if missing
        final profile = await api.fetchPlayerProfile(teammateId);
        if (profile != null) {
          final games = profile['games'];
          int? elo;
          int? skillLevel;
          if (games is Map && games['cs2'] is Map) {
            final cs2 = games['cs2'] as Map;
            elo = cs2['faceit_elo'] is int
                ? cs2['faceit_elo'] as int
                : int.tryParse('${cs2['faceit_elo']}');
            skillLevel = cs2['skill_level'] is int
                ? cs2['skill_level'] as int
                : int.tryParse('${cs2['skill_level']}');
          }
          final country = profile['country'];
          final nickname = profile['nickname'];
          final upsert = <String, Object?>{
            'player_id': teammateId,
            if (nickname != null) 'nickname': nickname,
            if (country != null) 'country': country,
            if (skillLevel != null) 'skill_level': skillLevel,
            if (elo != null) 'faceit_elo': elo,
            'source': 'discovered'
          };
          await playerRepo.upsertDiscovered(upsert);
        }
      }
    }
  }
}
