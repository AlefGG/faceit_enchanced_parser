import 'package:logger/logger.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../services/faceit_api.dart';
import '../../repositories/match_repository.dart';
import '../../repositories/player_repository.dart';

class PlayerMatchesIngestor {
  final FaceitApi api;
  final MatchRepository matchesRepo;
  final PlayerRepository playerRepo;
  final Logger logger;
  PlayerMatchesIngestor(
      {required this.api,
      required this.matchesRepo,
      required this.playerRepo,
      required this.logger});

  Future<int> ingestMatches(String playerId, String nickname,
      {int target = 300}) async {
    int offset = 0;
    const page = 100;
    int accepted = 0;
    int totalFetched = 0;
    while (accepted < target) {
      final limit =
          (target - totalFetched) > page ? page : (target - totalFetched);
      final items = await api.fetchPlayerMatchesPage(playerId,
          offset: offset, limit: limit);
      if (items.isEmpty) break;
      // Collect qualifying matches first
      final qualifying = <Map<String, dynamic>>[];
      for (final match in items) {
        final compType = (match['competition_type'] ?? '').toString();
        if (compType.isNotEmpty && compType != 'matchmaking') continue;
        final gameMode = (match['game_mode'] ?? '').toString();
        if (gameMode != '5v5') continue;
        qualifying.add(match);
      }
      if (qualifying.isEmpty) {
        totalFetched += items.length;
        offset += items.length;
        continue;
      }
      // Prefetch existing match IDs to avoid per-match exists queries
      final ids = qualifying.map((m) => "'${m['match_id']}'").join(',');
      final existingSet = <String>{};
      if (ids.isNotEmpty) {
        final existingRows = await matchesRepo.db
            .rawQuery('SELECT match_id FROM matches WHERE match_id IN ($ids)');
        for (final r in existingRows) {
          existingSet.add(r['match_id'] as String);
        }
      }
      // Batch transaction
      await matchesRepo.db.transaction((txn) async {
        final batch = txn.batch();
        for (final match in qualifying) {
          final matchId = match['match_id'];
          if (!existingSet.contains(matchId)) {
            batch.insert(
                'matches',
                {
                  'match_id': matchId,
                  'game_mode': match['game_mode'] ?? '',
                  'map': match['map'] ?? '',
                  'region': match['region'] ?? '',
                  'date': match['started_at'] ?? 0,
                  'finished_at': match['finished_at'] ?? 0,
                  'score_faction1': match['results'] != null &&
                          match['results']['score'] != null
                      ? int.tryParse(match['results']['score']['faction1']
                              .toString()) ??
                          0
                      : 0,
                  'score_faction2': match['results'] != null &&
                          match['results']['score'] != null
                      ? int.tryParse(match['results']['score']['faction2']
                              .toString()) ??
                          0
                      : 0,
                  'competition_type':
                      (match['competition_type'] ?? '').toString().isNotEmpty
                          ? (match['competition_type'] ?? '').toString()
                          : null,
                },
                conflictAlgorithm: ConflictAlgorithm.ignore);
          }
          for (final faction in ['faction1', 'faction2']) {
            if (match['teams'][faction] != null &&
                match['teams'][faction]['players'] != null) {
              final roster = List<Map<String, dynamic>>.from(
                  match['teams'][faction]['players']);
              for (final p in roster) {
                final thisId = p['player_id'];
                final winner = match['results'] != null
                    ? match['results']['winner']
                    : null;
                final result = winner == faction ? 1 : 0;
                final pNick = (p['nickname'] ?? '').toString();
                final country = (p['country'] ?? '').toString();
                int? skillLevel;
                int? faceitElo;
                final sl = p['skill_level'] ?? p['cs2_skill_level'];
                final fe = p['faceit_elo'] ?? p['cs2_faceit_elo'];
                if (sl is int)
                  skillLevel = sl;
                else if (sl != null) skillLevel = int.tryParse('$sl');
                if (fe is int)
                  faceitElo = fe;
                else if (fe != null) faceitElo = int.tryParse('$fe');
                final gp = p['game_profile'];
                if ((skillLevel == null || faceitElo == null) &&
                    gp is Map<String, dynamic>) {
                  final dsl = gp['skill_level'];
                  final dfe = gp['faceit_elo'];
                  if (skillLevel == null) {
                    if (dsl is int)
                      skillLevel = dsl;
                    else if (dsl != null) skillLevel = int.tryParse('$dsl');
                  }
                  if (faceitElo == null) {
                    if (dfe is int)
                      faceitElo = dfe;
                    else if (dfe != null) faceitElo = int.tryParse('$dfe');
                  }
                }
                batch.insert(
                    'players',
                    {
                      'player_id': thisId,
                      'nickname': pNick.isNotEmpty ? pNick : null,
                      'country': country.isNotEmpty ? country : null,
                      'skill_level': skillLevel,
                      'faceit_elo': faceitElo,
                      'processed': 0,
                      'source': 'discovered',
                    },
                    conflictAlgorithm: ConflictAlgorithm.ignore);
                batch.insert(
                    'player_matches',
                    {
                      'match_id': matchId,
                      'player_id': thisId,
                      'team': faction,
                      'result': result,
                      'nickname': pNick.isNotEmpty ? pNick : null,
                      'country': country.isNotEmpty ? country : null,
                      'skill_level': skillLevel,
                      'faceit_elo': faceitElo,
                    },
                    conflictAlgorithm: ConflictAlgorithm.ignore);
              }
            }
          }
          accepted++;
        }
        await batch.commit(noResult: true);
      });
      totalFetched += items.length;
      offset += items.length;
      if (items.length < limit) break;
    }
    logger.i('Ingested $accepted 5v5 matches for $playerId');
    return accepted;
  }
}
