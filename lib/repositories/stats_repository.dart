import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class StatsRepository {
  final Database db;
  StatsRepository(this.db);

  Future<bool> hasPlayerStats(String playerId) async {
    final r = await db.query('player_stats',
        columns: ['player_id'], where: 'player_id = ?', whereArgs: [playerId]);
    return r.isNotEmpty;
  }

  Future<void> insertPlayerStats(Map<String, Object?> data) async {
    await db.insert('player_stats', data,
        conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<bool> hasMapStats(String playerId, String mapName) async {
    final r = await db.query('player_map_stats',
        columns: ['id'],
        where: 'player_id = ? AND map_name = ?',
        whereArgs: [playerId, mapName]);
    return r.isNotEmpty;
  }

  Future<void> insertMapStats(Map<String, Object?> data) async {
    await db.insert('player_map_stats', data,
        conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> insertRecentMatchStats(Map<String, Object?> data) async {
    await db.insert('recent_player_match_stats', data,
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateRecentMatchStats(
      String matchId, String playerId, Map<String, Object?> update) async {
    if (update.isEmpty) return;
    await db.update('recent_player_match_stats', update,
        where: 'match_id = ? AND player_id = ?',
        whereArgs: [matchId, playerId]);
  }

  Future<Map<String, dynamic>?> aggregateRecent(
      String playerId, int limit) async {
    final rows = await db.rawQuery('''
      SELECT 
        COUNT(*) as matches,
        AVG(kills) as avg_kills,
        AVG(deaths) as avg_deaths,
        AVG(assists) as avg_assists,
        AVG(adr) as avg_adr,
        AVG(kr_ratio) as avg_kr_ratio,
        AVG(kd_ratio) as avg_kd_ratio,
        AVG(headshots) as avg_headshots,
        AVG(headshots_percentage) as avg_headshots_percentage,
        AVG(mvps) as avg_mvps,
        AVG(entry_count) as avg_entry_count,
        AVG(entry_wins) as avg_entry_wins,
        AVG(clutch_kills) as avg_clutch_kills,
        AVG(sniper_kills) as avg_sniper_kills,
        AVG(flash_count) as avg_flash_count,
        AVG(flash_successes) as avg_flash_successes,
        AVG(utility_damage) as avg_utility_damage,
        AVG(utility_usage_per_round) as avg_utility_usage_per_round,
        AVG(utility_damage_per_round) as avg_utility_damage_per_round,
        AVG(enemies_flashed) as avg_enemies_flashed
      FROM recent_player_match_stats
      WHERE player_id = ?
      ORDER BY created_at DESC
      LIMIT ?
    ''', [playerId, limit]);
    if (rows.isEmpty) return null;
    final row = rows.first;
    final matches = row['matches'] as int? ?? 0;
    if (matches == 0) return null;
    return row;
  }
}
