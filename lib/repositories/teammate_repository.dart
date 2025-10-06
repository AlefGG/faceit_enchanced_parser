import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class TeammateRepository {
  final Database db;
  TeammateRepository(this.db);

  Future<void> upsertTeammate(
      String playerId, String teammateId, int matches, int wins) async {
    final existing = await db.query('teammates',
        where: 'player_id = ? AND teammate_id = ?',
        whereArgs: [playerId, teammateId]);
    if (existing.isEmpty) {
      await db.insert('teammates', {
        'player_id': playerId,
        'teammate_id': teammateId,
        'matches_together': matches,
        'wins_together': wins
      });
    } else {
      await db.update(
          'teammates', {'matches_together': matches, 'wins_together': wins},
          where: 'player_id = ? AND teammate_id = ?',
          whereArgs: [playerId, teammateId]);
    }
  }

  Future<List<Map<String, dynamic>>> teammatesForPlayer(String playerId) async {
    return db.rawQuery('''
      SELECT t.*, p.nickname as teammate_nickname, p.skill_level as teammate_skill_level, p.faceit_elo as teammate_faceit_elo, p.country as teammate_country,
             (t.wins_together * 1.0 / t.matches_together) as win_rate
      FROM teammates t JOIN players p ON t.teammate_id = p.player_id
      WHERE t.player_id = ?
      ORDER BY win_rate DESC
    ''', [playerId]);
  }

  Future<List<Map<String, dynamic>>> playersMissingEloFromTeammates() async {
    return db.rawQuery('''
      SELECT DISTINCT t.player_id, t.teammate_id
      FROM teammates t JOIN players p ON p.player_id = t.teammate_id
      WHERE p.faceit_elo IS NULL
    ''');
  }

  Future<Map<String, dynamic>?> latestMutualSnapshot(
      String teammateId, String playerId) async {
    final rows = await db.rawQuery('''
      SELECT pm2.faceit_elo, pm2.skill_level, pm2.country, pm2.nickname, m.date
      FROM player_matches pm1
      JOIN player_matches pm2 ON pm1.match_id = pm2.match_id AND pm2.player_id = ?
      JOIN matches m ON m.match_id = pm1.match_id
      WHERE pm1.player_id = ?
      ORDER BY m.date DESC
      LIMIT 1
    ''', [teammateId, playerId]);
    if (rows.isEmpty) return null;
    return rows.first;
  }
}
