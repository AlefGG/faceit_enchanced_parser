import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class MatchRepository {
  final Database db;
  MatchRepository(this.db);

  Future<bool> exists(String matchId) async {
    final r = await db.query('matches',
        columns: ['match_id'], where: 'match_id = ?', whereArgs: [matchId]);
    return r.isNotEmpty;
  }

  Future<void> insertMatch(Map<String, Object?> data) async {
    await db.insert('matches', data,
        conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> linkPlayerToMatch(Map<String, Object?> link) async {
    await db.insert('player_matches', link,
        conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> updatePlayerMatch(
      String playerId, String matchId, Map<String, Object?> update) async {
    await db.update('player_matches', update,
        where: 'player_id = ? AND match_id = ?',
        whereArgs: [playerId, matchId]);
  }

  Future<List<Map<String, dynamic>>> recentMatchIdsForPlayer(
      String playerId, int limit) async {
    return db.rawQuery('''
      SELECT m.match_id
      FROM matches m JOIN player_matches pm ON pm.match_id = m.match_id
      WHERE pm.player_id = ?
      ORDER BY COALESCE(m.finished_at, m.date) DESC
      LIMIT ?
    ''', [playerId, limit]);
  }
}
