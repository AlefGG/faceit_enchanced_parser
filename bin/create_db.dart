// Создание структуры базы данных
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> createDb(Database db, int version) async {
  // Таблица для топ игроков
  await db.execute('''
    CREATE TABLE players (
      player_id TEXT PRIMARY KEY,
      nickname TEXT NOT NULL,
      skill_level INTEGER,
      faceit_elo INTEGER,
      country TEXT,
      processed BOOLEAN DEFAULT 0
    )
  ''');

  // Таблица для статистики игроков
  await db.execute('''
  CREATE TABLE player_stats (
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
    FOREIGN KEY (player_id) REFERENCES players (player_id)
  )
''');

// Таблица для статистики игроков по картам
  await db.execute('''
  CREATE TABLE player_map_stats (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    player_id TEXT,
    map_name TEXT,
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
    total_damage INTEGER,
    total_utility_successes INTEGER,
    total_headshots_percentage INTEGER,
    average_headshots_percentage REAL,
    matches INTEGER,
    wins INTEGER,
    total_rounds INTEGER,
    win_rate_percentage INTEGER,
    total_1v1_wins INTEGER,
    total_1v2_wins INTEGER,
    total_utility_count INTEGER,
    total_kills INTEGER,
    total_sniper_kills INTEGER,
    utility_success_rate REAL,
    total_enemies_flashed INTEGER,
    average_kills REAL,
    average_deaths REAL,
    headshots INTEGER,
    assists INTEGER,
    deaths INTEGER,
    average_assists REAL,
    average_triple_kills REAL,
    average_quadro_kills REAL,
    average_penta_kills REAL,
    average_mvps REAL,
    triple_kills INTEGER,
    quadro_kills INTEGER,
    penta_kills INTEGER,
    mvps INTEGER,
    headshots_per_match REAL,
    rounds INTEGER,
    kills INTEGER,
    FOREIGN KEY (player_id) REFERENCES players (player_id)
  )
''');

  // Таблица для матчей
  await db.execute('''
    CREATE TABLE matches (
      match_id TEXT PRIMARY KEY,
      game_mode TEXT,
      map TEXT,
      region TEXT,
      date INTEGER,
      score_faction1 INTEGER,
      score_faction2 INTEGER
    )
  ''');

  // Таблица для участия игроков в матчах
  await db.execute('''
    CREATE TABLE player_matches (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      player_id TEXT,
      match_id TEXT,
      team TEXT,
      result INTEGER, /* 1=win, 0=loss */
      FOREIGN KEY (player_id) REFERENCES players (player_id),
      FOREIGN KEY (match_id) REFERENCES matches (match_id)
    )
  ''');

  // Таблица для отношений между игроками (тиммейты)
  await db.execute('''
    CREATE TABLE teammates (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      player_id TEXT,
      teammate_id TEXT,
      matches_together INTEGER DEFAULT 0,
      wins_together INTEGER DEFAULT 0,
      FOREIGN KEY (player_id) REFERENCES players (player_id),
      FOREIGN KEY (teammate_id) REFERENCES players (player_id)
    )
  ''');

  // Индексы для ускорения запросов
  await db.execute(
      'CREATE INDEX idx_player_matches_player ON player_matches(player_id)');
  await db.execute(
      'CREATE INDEX idx_player_matches_match ON player_matches(match_id)');
  await db.execute(
      'CREATE INDEX idx_player_map_stats ON player_map_stats(player_id, map_name)');
  await db.execute('CREATE INDEX idx_teammates_player ON teammates(player_id)');
  await db
      .execute('CREATE INDEX idx_teammates_teammate ON teammates(teammate_id)');
}
