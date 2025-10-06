import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class ActivityRepository {
  final Database db;
  ActivityRepository(this.db);

  Future<void> replaceActivity(
      String playerId,
      List<Map<String, Object?>> hours,
      List<Map<String, Object?>> weekdays) async {
    await db.transaction((txn) async {
      await txn.delete('player_activity_hours',
          where: 'player_id = ?', whereArgs: [playerId]);
      await txn.delete('player_activity_weekdays',
          where: 'player_id = ?', whereArgs: [playerId]);
      final batch = txn.batch();
      for (final h in hours) {
        batch.insert('player_activity_hours', h,
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
      for (final d in weekdays) {
        batch.insert('player_activity_weekdays', d,
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    });
  }

  Future<List<Map<String, dynamic>>> recentMatchesTimestamps(
      String playerId, int limit) async {
    return db.rawQuery('''
      SELECT COALESCE(m.finished_at, m.date) AS ts
      FROM player_matches pm JOIN matches m ON m.match_id = pm.match_id
      WHERE pm.player_id = ?
      ORDER BY COALESCE(m.finished_at, m.date) DESC
      LIMIT ?
    ''', [playerId, limit]);
  }
}
