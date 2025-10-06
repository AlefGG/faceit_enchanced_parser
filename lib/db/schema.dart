import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Ensures database schema (tables + idempotent column additions)
Future<void> createOrMigrate(Database db) async {
  Future<void> ensureColumn(String table, String column, String typeDef) async {
    final info = await db.rawQuery('PRAGMA table_info($table)');
    final exists = info.any((r) => r['name'] == column);
    if (!exists) {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $typeDef');
    }
  }

  await db.execute('''
    CREATE TABLE IF NOT EXISTS players (
      player_id TEXT PRIMARY KEY,
      nickname TEXT,
      country TEXT,
      skill_level INTEGER,
      faceit_elo INTEGER,
      processed INTEGER NOT NULL DEFAULT 0,
      source TEXT NOT NULL DEFAULT 'top',
      rank_order INTEGER,
      created_at TEXT DEFAULT CURRENT_TIMESTAMP
    )
  ''');

  await db.execute('''
    CREATE TABLE IF NOT EXISTS player_stats (
      player_id TEXT PRIMARY KEY,
      kd_ratio REAL,
      kr_ratio REAL,
      adr REAL,
      sniper_kill_rate_per_round REAL,
      sniper_kill_rate_per_match REAL,
      v1_count INTEGER,
      v2_count INTEGER,
      match_1v1_win_rate REAL,
      match_1v2_win_rate REAL,
      utility_damage_success_rate REAL,
      utility_damage_per_round REAL,
      utility_damage INTEGER,
      utility_usage_per_round REAL,
      enemies_flashed_per_round REAL,
      flashes_per_round REAL,
      flash_success_rate REAL,
      flash_successes INTEGER,
      flash_count INTEGER,
      entry_wins INTEGER,
      match_entry_rate REAL,
      match_entry_success_rate REAL,
      entry_count INTEGER,
      current_win_streak INTEGER,
      total_damage INTEGER,
      total_utility_successes INTEGER,
      total_headshots_percentage INTEGER,
      average_headshots_percentage REAL,
      matches INTEGER,
      wins INTEGER,
      total_rounds INTEGER,
      win_rate_percentage INTEGER,
      total_matches INTEGER,
      longest_win_streak INTEGER,
      total_1v1_wins INTEGER,
      total_1v2_wins INTEGER,
      total_utility_count INTEGER,
      total_kills INTEGER,
      total_sniper_kills INTEGER,
      utility_success_rate REAL,
      total_enemies_flashed INTEGER,
      FOREIGN KEY (player_id) REFERENCES players (player_id) ON DELETE CASCADE
    )
  ''');

  await db.execute('''
    CREATE TABLE IF NOT EXISTS player_map_stats (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      player_id TEXT,
      map_name TEXT,
      kd_ratio REAL,
      kr_ratio REAL,
      adr REAL,
      sniper_kill_rate_per_round REAL,
      sniper_kill_rate_per_match REAL,
      total_sniper_kills INTEGER,
      v1_count INTEGER,
      v2_count INTEGER,
      match_1v1_win_rate REAL,
      match_1v2_win_rate REAL,
      total_1v1_wins INTEGER,
      total_1v2_wins INTEGER,
      utility_damage_success_rate REAL,
      utility_damage_per_round REAL,
      utility_damage INTEGER,
      utility_usage_per_round REAL,
      utility_success_rate REAL,
      total_utility_successes INTEGER,
      total_utility_count INTEGER,
      enemies_flashed_per_round REAL,
      flashes_per_round REAL,
      flash_success_rate REAL,
      flash_successes INTEGER,
      flash_count INTEGER,
      total_enemies_flashed INTEGER,
      entry_wins INTEGER,
      match_entry_rate REAL,
      match_entry_success_rate REAL,
      entry_count INTEGER,
      total_damage INTEGER,
      total_headshots_percentage INTEGER,
      average_headshots_percentage REAL,
      matches INTEGER,
      wins INTEGER,
      total_rounds INTEGER,
      win_rate_percentage INTEGER,
      total_kills INTEGER,
      average_kills REAL,
      average_deaths REAL,
      average_assists REAL,
      headshots INTEGER,
      assists INTEGER,
      deaths INTEGER,
      kills INTEGER,
      rounds INTEGER,
      triple_kills INTEGER,
      quadro_kills INTEGER,
      penta_kills INTEGER,
      average_triple_kills REAL,
      average_quadro_kills REAL,
      average_penta_kills REAL,
      mvps INTEGER,
      average_mvps REAL,
      headshots_per_match REAL,
      FOREIGN KEY (player_id) REFERENCES players (player_id) ON DELETE CASCADE
    )
  ''');

  await db.execute('''
    CREATE TABLE IF NOT EXISTS matches (
      match_id TEXT PRIMARY KEY,
      game_mode TEXT,
      map TEXT,
      region TEXT,
      date INTEGER,
      finished_at INTEGER,
      score_faction1 INTEGER,
      score_faction2 INTEGER,
      competition_type TEXT
    )
  ''');

  await db.execute('''
    CREATE TABLE IF NOT EXISTS player_matches (
      match_id TEXT NOT NULL,
      player_id TEXT NOT NULL,
      team TEXT,
      result INTEGER,
      nickname TEXT,
      country TEXT,
      skill_level INTEGER,
      faceit_elo INTEGER,
      PRIMARY KEY (match_id, player_id),
      FOREIGN KEY (match_id) REFERENCES matches (match_id) ON DELETE CASCADE,
      FOREIGN KEY (player_id) REFERENCES players (player_id) ON DELETE CASCADE
    )
  ''');

  await db.execute('''
    CREATE TABLE IF NOT EXISTS teammates (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      player_id TEXT NOT NULL,
      teammate_id TEXT NOT NULL,
      matches_together INTEGER NOT NULL,
      wins_together INTEGER NOT NULL,
      last_match_at TEXT,
      FOREIGN KEY (player_id) REFERENCES players (player_id) ON DELETE CASCADE,
      FOREIGN KEY (teammate_id) REFERENCES players (player_id) ON DELETE CASCADE
    )
  ''');

  await db.execute('''
    CREATE TABLE IF NOT EXISTS player_activity_hours (
      player_id TEXT NOT NULL,
      hour INTEGER NOT NULL,
      matches_count INTEGER NOT NULL,
      window_size INTEGER,
      PRIMARY KEY (player_id, hour),
      FOREIGN KEY (player_id) REFERENCES players(player_id) ON DELETE CASCADE
    )
  ''');

  await db.execute('''
    CREATE TABLE IF NOT EXISTS player_activity_weekdays (
      player_id TEXT NOT NULL,
      weekday INTEGER NOT NULL,
      matches_count INTEGER NOT NULL,
      window_size INTEGER,
      PRIMARY KEY (player_id, weekday),
      FOREIGN KEY (player_id) REFERENCES players(player_id) ON DELETE CASCADE
    )
  ''');

  await db.execute('''
    CREATE TABLE IF NOT EXISTS recent_player_match_stats (
      match_id TEXT NOT NULL,
      player_id TEXT NOT NULL,
      kills INTEGER,
      deaths INTEGER,
      assists INTEGER,
      adr REAL,
      kr_ratio REAL,
      kd_ratio REAL,
      headshots INTEGER,
      headshots_percentage REAL,
      mvps INTEGER,
      entry_count INTEGER,
      entry_wins INTEGER,
      clutch_kills INTEGER,
      sniper_kills INTEGER,
      flash_count INTEGER,
      flash_successes INTEGER,
      utility_damage INTEGER,
      utility_usage_per_round REAL,
      utility_damage_per_round REAL,
      enemies_flashed INTEGER,
      created_at TEXT DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (match_id, player_id),
      FOREIGN KEY (match_id) REFERENCES matches(match_id) ON DELETE CASCADE,
      FOREIGN KEY (player_id) REFERENCES players(player_id) ON DELETE CASCADE
    )
  ''');

  // Indexes
  await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_player_matches_player ON player_matches(player_id)');
  await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_player_matches_match ON player_matches(match_id)');
  await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_player_map_stats ON player_map_stats(player_id, map_name)');
  await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_teammates_player ON teammates(player_id)');
  await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS ux_teammates_pair ON teammates(player_id, teammate_id)');

  // Idempotent new columns (add here when schema evolves)
  await ensureColumn('matches', 'competition_type', 'TEXT');
  await ensureColumn('player_activity_hours', 'window_size', 'INTEGER');
  await ensureColumn('player_activity_weekdays', 'window_size', 'INTEGER');
}
