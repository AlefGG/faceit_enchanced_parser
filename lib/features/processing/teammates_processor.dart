import 'package:logger/logger.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../repositories/teammate_repository.dart';
import '../ingestion/player_stats_fetcher.dart';

class TeammatesProcessor {
  final TeammateRepository teammateRepo;
  final PlayerStatsFetcher statsFetcher;
  final Logger logger;

  TeammatesProcessor({
    required this.teammateRepo,
    required this.statsFetcher,
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
      await teammateRepo.upsertTeammate(
          playerId, e.key, e.value['matches'] ?? 0, e.value['wins'] ?? 0);
      if (fetchMissingStats) {
        try {
          await statsFetcher.fetchIfNeeded(e.key);
        } catch (err) {
          logger.w('Failed to fetch stats for teammate ${e.key}: $err');
        }
      }
    }
  }
}
