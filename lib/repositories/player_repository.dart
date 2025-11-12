import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../models/player.dart';

class PlayerRepository {
  final Database db;
  PlayerRepository(this.db);

  Future<int> countTopPlayers() async {
    final r =
        await db.rawQuery("SELECT COUNT(*) c FROM players WHERE source='top'");
    return (r.first['c'] as int?) ?? 0;
  }

  Future<void> insertTopPlayers(List<Player> players) async {
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final p in players) {
        batch.insert('players', p.toMap(),
            conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      await batch.commit(noResult: true);
    });
  }

  Future<List<Map<String, dynamic>>> fetchUnprocessedTopSlice(
      int startRank, int endRank) async {
    return db.rawQuery('''
      SELECT *
      FROM players
      WHERE source = 'top'
        AND rank_order >= ?
        AND rank_order < ?
        AND processed = 0
      ORDER BY rank_order
    ''', [startRank, endRank]);
  }

  Future<void> markProcessed(String playerId) async {
    await db.update('players', {'processed': 1},
        where: 'player_id = ?', whereArgs: [playerId]);
  }

  Future<Map<String, dynamic>?> getPlayer(String playerId) async {
    final rows = await db.query('players',
        where: 'player_id = ?', whereArgs: [playerId], limit: 1);
    if (rows.isEmpty) return null;
    return rows.first;
  }

  Future<void> upsertDiscovered(Map<String, Object?> data) async {
    await db.insert('players', data,
        conflictAlgorithm: ConflictAlgorithm.ignore);
    // update missing fields
    final existing = await db.query('players',
        where: 'player_id = ?', whereArgs: [data['player_id']]);
    if (existing.isEmpty) return;
    final row = existing.first;
    final update = <String, Object?>{};
    for (final k in ['nickname', 'country', 'skill_level', 'faceit_elo']) {
      if ((row[k] == null ||
              (row[k] is String && (row[k] as String).isEmpty)) &&
          data[k] != null) {
        update[k] = data[k];
      }
    }
    if (update.isNotEmpty) {
      await db.update('players', update,
          where: 'player_id = ?', whereArgs: [data['player_id']]);
    }
  }
}
