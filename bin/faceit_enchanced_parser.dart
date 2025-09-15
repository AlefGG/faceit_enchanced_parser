import 'dart:async';
import 'dart:io';
import 'package:dotenv/dotenv.dart';
import 'package:logger/logger.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:args/args.dart';

// Глобальные переменные
String outputPrefix = 'faceit';
String dateTimeStamp = ''; // Будет заполняться при запуске
int startPlayerIndex = 0; // По умолчанию начинаем с начала
int endPlayerIndex = 1000; // По умолчанию обрабатываем 1000 игроков
late Database db;
late Logger logger;
late String apiKey;
int PLAYER_LIMIT = 1000; // Начнем с 1000 игроков
final int MATCHES_PER_PLAYER = 300;
final int REQUEST_DELAY = 150; // мс
final int DB_REQUEST_DELAY = 0; // мс

// Функция для сохранения прогресса
Future<void> saveProgress(int processedIndex) async {
  final progressFile = File('progress.txt');
  await progressFile.writeAsString('$processedIndex');
  logger.i('Progress saved: processed up to player $processedIndex');
}

// Функция для чтения сохраненного прогресса
Future<int> loadProgress() async {
  final progressFile = File('progress.txt');
  if (await progressFile.exists()) {
    final content = await progressFile.readAsString();
    try {
      return int.parse(content.trim());
    } catch (e) {
      logger.w('Invalid progress file content: $content');
      return 0;
    }
  }
  return 0;
}

void main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('start',
        abbr: 's', help: 'Starting player index (0-based)', defaultsTo: '0')
    ..addOption('end',
        abbr: 'e', help: 'Ending player index (exclusive)', defaultsTo: '1000')
    ..addOption('prefix',
        abbr: 'p', help: 'Output files prefix', defaultsTo: 'faceit')
    ..addFlag('continue',
        abbr: 'c', help: 'Continue from last saved progress', negatable: false)
    ..addFlag('timestamp',
        abbr: 't', help: 'Add timestamp to output files', defaultsTo: true)
    ..addFlag('help',
        abbr: 'h', help: 'Show this help message', negatable: false);

  // Парсим аргументы
  try {
    final results = parser.parse(arguments);

    // Если запрошена помощь, показываем и выходим
    if (results['help']) {
      print('FaceIT CS2 Data Collector\n');
      print('Usage: dart faceit_ecnhanced_parser.dart [options]\n');
      print(parser.usage);
      exit(0);
    }

    if (results['continue']) {
      startPlayerIndex = await loadProgress();
      logger.i(
          'Continuing from previously saved progress: starting at player $startPlayerIndex');
    }

    if (results.wasParsed('prefix')) {
      outputPrefix = results['prefix'];
    }

    // Добавляем временную метку, если требуется
    if (results['timestamp']) {
      final now = DateTime.now();
      dateTimeStamp =
          '_${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}-${now.minute.toString().padLeft(2, '0')}';
    }

    // Получаем параметры диапазона
    startPlayerIndex = int.parse(results['start']);
    endPlayerIndex = int.parse(results['end']);

    // Проверка валидности диапазона
    if (startPlayerIndex < 0 || endPlayerIndex <= startPlayerIndex) {
      throw ArgumentError(
          'Invalid range: start must be >= 0 and end must be > start');
    }

    // Корректируем PLAYER_LIMIT на основе диапазона
    PLAYER_LIMIT = endPlayerIndex - startPlayerIndex;
  } catch (e) {
    print('Error parsing arguments: $e\n');
    print('Usage: dart faceit_ecnhanced_parser.dart [options]\n');
    print(parser.usage);
    exit(1);
  }

  // Инициализация
  logger = Logger();
  logger.i(
      'Starting FACEIT CS2 data collection (players $startPlayerIndex-$endPlayerIndex)');

  // Загрузка переменных окружения
  var env = DotEnv()..load(['.env.faceit']);
  apiKey = env['FACEIT_API_KEY'] ?? '';

  if (apiKey.isEmpty) {
    logger.e(
        'FACEIT API key not found. Please set FACEIT_API_KEY in .env.faceit file');
    exit(1);
  }

  // Инициализация SQLite для Windows
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  try {
    // Открываем или создаем базу данных
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'faceit_stats.db');
    logger.i('Opening database at $path');
    db = await openDatabase(
      path,
      version: 1,
      onCreate: _createDb,
    );

    logger.i('Database initialized at $path');

    // Создаем имена файлов с учетом префикса, временной метки и диапазона игроков
    final rangeStamp = '_${startPlayerIndex}_$endPlayerIndex';

    final playerStatsFile =
        '${outputPrefix}_player_stats$dateTimeStamp$rangeStamp.csv';
    final mapStatsFile =
        '${outputPrefix}_map_stats$dateTimeStamp$rangeStamp.csv';
    final teammatesFile =
        '${outputPrefix}_teammates$dateTimeStamp$rangeStamp.csv';
    final completeDataFile =
        '${outputPrefix}_complete_data$dateTimeStamp$rangeStamp.json';

    // Вызываем функции экспорта с новыми именами файлов
    await exportDataForML(playerStatsFile);
    await exportMapStatsForML(mapStatsFile);
    await exportTeammatesWithStatsForML(teammatesFile);
    await exportCompleteDataToJson(completeDataFile);
    // Закрываем базу данных
    await db.close();
    logger.i('Data collection completed');
  } catch (e, stackTrace) {
    logger.e('Fatal error during execution', error: e, stackTrace: stackTrace);
    exit(1);
  }
}

// Функция для надежного выполнения HTTP-запросов с повторными попытками
Future<http.Response> reliableHttpGet(
  Uri url, {
  required Map<String, String> headers,
  int maxRetries = 5,
  int initialDelayMs = 1000,
}) async {
  int retryCount = 0;
  int delayMs = initialDelayMs;

  while (true) {
    try {
      // Попытка выполнить запрос с увеличенным таймаутом
      final response = await http.get(url, headers: headers).timeout(
        const Duration(seconds: 30), // Увеличиваем таймаут до 30 секунд
        onTimeout: () {
          throw TimeoutException('Request timed out after 30 seconds');
        },
      );

      // Проверяем коды ответа для определения необходимости повторных попыток
      if (response.statusCode == 429) {
        // Too Many Requests
        logger.w('Rate limited by FACEIT API, will retry');
        throw Exception('Rate limited');
      }

      return response; // Успешный запрос
    } catch (e) {
      retryCount++;

      if (retryCount > maxRetries) {
        logger.e('Failed after $maxRetries retries: $e');
        rethrow; // Больше не пытаемся, пробрасываем ошибку
      }

      // Экспоненциальное увеличение задержки между попытками
      logger.w('Request failed (attempt $retryCount/$maxRetries): $e');
      logger.i('Retrying in ${delayMs}ms...');

      await Future.delayed(Duration(milliseconds: delayMs));
      delayMs *= 2; // Экспоненциальный рост задержки
    }
  }
}

// Создание структуры базы данных
Future<void> _createDb(Database db, int version) async {
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

// Основной процесс сбора данных
Future<void> collectData() async {
  // Шаг 1: Получаем топ игроков
  await fetchTopPlayers();

  // Шаг 2: Обрабатываем игроков в указанном диапазоне
  final players = await db.rawQuery('''
    SELECT * FROM players 
    WHERE processed = 0 
    ORDER BY rowid 
    LIMIT ? 
    OFFSET ?
  ''', [PLAYER_LIMIT, startPlayerIndex]);

  logger.i(
      'Found ${players.length} players to process (range $startPlayerIndex-$endPlayerIndex)');

  int processedCount = 0;
  for (final player in players) {
    final playerId = player['player_id'] as String;
    final nickname = player['nickname'] as String;

    try {
      logger.i(
          'Processing player $nickname ($playerId) - ${processedCount + 1}/${players.length}');

      // Получаем матчи игрока
      final matchCount = await fetchPlayerMatches(playerId);
      if (matchCount > 0) {
        // Получаем статистику игрока
        await fetchPlayerStats(playerId);

        // Находим и обрабатываем тиммейтов
        await processTeammates(playerId);

        // Отмечаем игрока как обработанного
        await db.update('players', {'processed': 1},
            where: 'player_id = ?', whereArgs: [playerId]);
      }

      processedCount++;
      logger.i(
          'Completed processing for $nickname ($processedCount/${players.length})');
    } catch (e) {
      logger.e('Error processing player $nickname: $e');
      // Продолжаем со следующим игроком
    }

    // Добавляем задержку между обработкой игроков
    // await Future.delayed(Duration(seconds: DB_REQUEST_DELAY));
  }
}

// Получение топ игроков с пагинацией
Future<void> fetchTopPlayers() async {
  logger.i('Fetching top $PLAYER_LIMIT CS2 players in EU');

  // Проверяем, есть ли уже игроки в базе
  // final count =
  //     Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM players'));
  final countResult = await db.rawQuery('SELECT COUNT(*) FROM players');
  final count = countResult.first.values.first as int? ?? 0;

  if (count > 0) {
    logger.i('Found $count existing players in database, skipping fetch');
    return;
  }

  try {
    int offset = 0;
    final maxLimit = 100; // Максимальный лимит API
    int totalFetched = 0;
    final int targetCount = PLAYER_LIMIT;

    while (totalFetched < targetCount) {
      // Определяем количество записей для текущего запроса
      final currentLimit = (targetCount - totalFetched) > maxLimit
          ? maxLimit
          : (targetCount - totalFetched);

      logger.i(
          'Fetching players $offset to ${offset + currentLimit} (total: $totalFetched/$targetCount)');

      final url =
          'https://open.faceit.com/data/v4/rankings/games/cs2/regions/EU?offset=$offset&limit=$currentLimit';
      final response = await reliableHttpGet(Uri.parse(url), headers: {
        'Authorization': 'Bearer $apiKey',
      });

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final players = List<Map<String, dynamic>>.from(data['items']);

        if (players.isEmpty) {
          logger.w('No more players available from API');
          break;
        }

        // Начинаем транзакцию
        await db.transaction((txn) async {
          final batch = txn.batch();

          for (final player in players) {
            batch.insert('players', {
              'player_id': player['player_id'],
              'nickname': player['nickname'],
              'skill_level': player['skill_level'],
              'faceit_elo': player['faceit_elo'],
              'country': player['country'],
              'processed': 0
            });
          }

          await batch.commit();
        });

        totalFetched += players.length;
        offset += currentLimit;
        logger.i(
            'Saved batch of ${players.length} players, total: $totalFetched/$targetCount');

        // Добавляем задержку между запросами
        await Future.delayed(Duration(milliseconds: REQUEST_DELAY));
      } else {
        throw Exception(
            'Failed to load top players: ${response.statusCode} - ${response.body}');
      }
    }

    logger.i('Completed fetching $totalFetched players');
  } catch (e) {
    logger.e('Error fetching top players: $e');
    rethrow;
  }
}

// Получение матчей игрока с пагинацией
Future<int> fetchPlayerMatches(String playerId) async {
  logger.i('Fetching last $MATCHES_PER_PLAYER matches for player $playerId');

  // Проверяем, получали ли мы уже матчи для этого игрока
  final existingMatches = await db.rawQuery(
      'SELECT COUNT(*) FROM player_matches WHERE player_id = ?', [playerId]);
  final count = existingMatches.first.values.first as int? ?? 0;

  if (count >= MATCHES_PER_PLAYER) {
    logger.i('Player $playerId already has $count matches, skipping fetch');
    return count;
  }

  try {
    int offset = 0;
    final maxLimit = 100; // Максимальный лимит API
    int totalFetched = 0;
    final int targetCount = MATCHES_PER_PLAYER;

    while (totalFetched < targetCount) {
      // Определяем количество записей для текущего запроса
      final currentLimit = (targetCount - totalFetched) > maxLimit
          ? maxLimit
          : (targetCount - totalFetched);

      logger.i(
          'Fetching matches $offset to ${offset + currentLimit} for player $playerId');

      final url =
          'https://open.faceit.com/data/v4/players/$playerId/history?game=cs2&offset=$offset&limit=$currentLimit';
      final response = await reliableHttpGet(Uri.parse(url), headers: {
        'Authorization': 'Bearer $apiKey',
      });

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final matches = List<Map<String, dynamic>>.from(data['items']);

        if (matches.isEmpty) {
          logger.w('No more matches available for player $playerId');
          break;
        }

        // Начинаем транзакцию
        await db.transaction((txn) async {
          for (final match in matches) {
            final matchId = match['match_id'];

            // Проверяем, есть ли уже такой матч
            final existingMatch = await txn
                .query('matches', where: 'match_id = ?', whereArgs: [matchId]);

            if (existingMatch.isEmpty) {
              // Сохраняем информацию о матче
              await txn.insert('matches', {
                'match_id': matchId,
                'game_mode': match['game_mode'] ?? '',
                'map': match['map'] ?? '',
                'region': match['region'] ?? '',
                'date': match['started_at'] ??
                    0, // Используем started_at вместо date
                'score_faction1': match['results'] != null &&
                        match['results']['score'] != null
                    ? int.parse(
                        match['results']['score']['faction1'].toString())
                    : 0,
                'score_faction2': match['results'] != null &&
                        match['results']['score'] != null
                    ? int.parse(
                        match['results']['score']['faction2'].toString())
                    : 0,
              });

              // Сохраняем информацию об игроках в матче
              for (final faction in ['faction1', 'faction2']) {
                if (match['teams'][faction] != null &&
                    match['teams'][faction]['players'] != null) {
                  final roster = List<Map<String, dynamic>>.from(
                      match['teams'][faction]['players']);
                  for (final player in roster) {
                    final thisPlayerId = player['player_id'];
                    final result =
                        match['results']['winner'] == faction ? 1 : 0;

                    // Добавляем игрока, если его еще нет в базе
                    final existingPlayer = await txn.query('players',
                        where: 'player_id = ?', whereArgs: [thisPlayerId]);

                    if (existingPlayer.isEmpty) {
                      await txn.insert('players', {
                        'player_id': thisPlayerId,
                        'nickname': player['nickname'] ?? '',
                        'processed': 0
                      });
                    }

                    // Связываем игрока с матчем
                    await txn.insert('player_matches', {
                      'player_id': thisPlayerId,
                      'match_id': matchId,
                      'team': faction,
                      'result': result
                    });
                  }
                }
              }
            }
          }
        });

        totalFetched += matches.length;
        offset += currentLimit;
        logger.i(
            'Saved batch of ${matches.length} matches for player $playerId, total: $totalFetched/$targetCount');

        // Добавляем задержку между запросами
        await Future.delayed(Duration(milliseconds: REQUEST_DELAY));
      } else {
        logger.e(
            'Failed to load player matches: ${response.statusCode} - ${response.body}');
        break; // Прерываем цикл при ошибке
      }
    }

    logger.i('Completed fetching $totalFetched matches for player $playerId');
    return totalFetched;
  } catch (e) {
    logger.e('Error fetching player matches: $e');
    return 0;
  }
}

// Получение статистики игрока
Future<void> fetchPlayerStats(String playerId) async {
  logger.i('Fetching stats for player $playerId');

  // Проверяем, есть ли уже статистика для этого игрока
  final existingStats = await db
      .query('player_stats', where: 'player_id = ?', whereArgs: [playerId]);

  if (existingStats.isNotEmpty) {
    logger.i('Player $playerId already has stats, skipping fetch');
    return;
  }

  try {
    final url = 'https://open.faceit.com/data/v4/players/$playerId/stats/cs2';
    final response = await reliableHttpGet(Uri.parse(url), headers: {
      'Authorization': 'Bearer $apiKey',
    });

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);

      if (data['lifetime'] == null) {
        logger.w('No lifetime stats found for player $playerId');
        return;
      }

      // Извлекаем статистику из ответа API - используем 'lifetime'
      final stats = data['lifetime'];

      // Логирование для отладки
      logger.d('Raw lifetime stats for player $playerId: ${stats.toString()}');

      // Безопасное получение значений с учетом отличающихся названий полей
      double safeParseDouble(String? value) {
        if (value == null || value.isEmpty) return 0.0;
        try {
          return double.parse(value);
        } catch (e) {
          return 0.0;
        }
      }

      int safeParseInt(String? value) {
        if (value == null || value.isEmpty) return 0;
        try {
          return int.parse(value);
        } catch (e) {
          return 0;
        }
      }

      // Маппинг полей из API к полям в БД
      await db.insert('player_stats', {
        'player_id': playerId,
        // Основные показатели
        'kd_ratio': safeParseDouble(stats['K/D Ratio']),
        'kr_ratio': safeParseDouble(stats['Average K/R Ratio']),
        'adr': safeParseDouble(stats['ADR']),

        // Снайперские показатели
        'sniper_kill_rate_per_round':
            safeParseDouble(stats['Sniper Kill Rate per Round']),
        'sniper_kill_rate_per_match':
            safeParseDouble(stats['Sniper Kill Rate']),
        'total_sniper_kills': safeParseInt(stats['Total Sniper Kills']),

        // 1vX ситуации
        'v1_count': safeParseInt(stats['Total 1v1 Count']),
        'v2_count': safeParseInt(stats['Total 1v2 Count']),
        'match_1v1_win_rate': safeParseDouble(stats['1v1 Win Rate']),
        'match_1v2_win_rate': safeParseDouble(stats['1v2 Win Rate']),
        'total_1v1_wins': safeParseInt(stats['Total 1v1 Wins']),
        'total_1v2_wins': safeParseInt(stats['Total 1v2 Wins']),

        // Урон от гранат
        'utility_damage_success_rate':
            safeParseDouble(stats['Utility Damage Success Rate']),
        'utility_damage_per_round':
            safeParseDouble(stats['Utility Damage per Round']),
        'utility_damage': safeParseInt(stats['Total Utility Damage']),
        'utility_usage_per_round':
            safeParseDouble(stats['Utility Usage per Round']),
        'utility_success_rate': safeParseDouble(stats['Utility Success Rate']),
        'total_utility_successes':
            safeParseInt(stats['Total Utility Successes']),
        'total_utility_count': safeParseInt(stats['Total Utility Count']),

        // Флешки
        'enemies_flashed_per_round':
            safeParseDouble(stats['Enemies Flashed per Round']),
        'flashes_per_round': safeParseDouble(stats['Flashes per Round']),
        'flash_success_rate': safeParseDouble(stats['Flash Success Rate']),
        'flash_successes': safeParseInt(stats['Total Flash Successes']),
        'flash_count': safeParseInt(stats['Total Flash Count']),
        'total_enemies_flashed': safeParseInt(stats['Total Enemies Flashed']),

        // Энтри фраги
        'entry_wins': safeParseInt(stats['Total Entry Wins']),
        'match_entry_rate': safeParseDouble(stats['Entry Rate']),
        'match_entry_success_rate':
            safeParseDouble(stats['Entry Success Rate']),
        'entry_count': safeParseInt(stats['Total Entry Count']),

        // Общая статистика матчей
        'current_win_streak': safeParseInt(stats['Current Win Streak']),
        'total_damage': safeParseInt(stats['Total Damage']),
        'total_headshots_percentage': safeParseInt(stats['Total Headshots %']),
        'average_headshots_percentage':
            safeParseDouble(stats['Average Headshots %']),
        'matches': safeParseInt(stats['Matches']),
        'wins': safeParseInt(stats['Wins']),
        'total_rounds': safeParseInt(stats['Total Rounds with extended stats']),
        'win_rate_percentage': safeParseInt(stats['Win Rate %']),
        'total_matches': safeParseInt(stats['Total Matches']),
        'longest_win_streak': safeParseInt(stats['Longest Win Streak']),
        'total_kills': safeParseInt(stats['Total Kills with extended stats']),
      });

      logger.i('Saved complete stats for player $playerId');

// Обработка статистики по картам
      if (data['segments'] != null) {
        final segments = List<Map<String, dynamic>>.from(data['segments']);

        for (final segment in segments) {
          // Проверяем, что это статистика по карте в режиме 5v5
          if (segment['type'] == 'Map' &&
              segment['mode'] == '5v5' &&
              segment['stats'] != null &&
              segment['label'] != null) {
            final mapName = segment['label'] as String;
            final mapStats = segment['stats'] as Map<String, dynamic>;

            logger
                .i('Processing map stats for player $playerId on map $mapName');

            // Проверяем, есть ли уже статистика по этой карте
            final existingMapStats = await db.query('player_map_stats',
                where: 'player_id = ? AND map_name = ?',
                whereArgs: [playerId, mapName]);

            if (existingMapStats.isNotEmpty) {
              logger.i(
                  'Map stats for player $playerId on map $mapName already exist, skipping');
              continue;
            }

            // Вставляем статистику по карте
            await db.insert('player_map_stats', {
              'player_id': playerId,
              'map_name': mapName,

              // Основные показатели
              'kd_ratio': safeParseDouble(mapStats['K/D Ratio']),
              'kr_ratio': safeParseDouble(mapStats['K/R Ratio']),
              'adr': safeParseDouble(mapStats['ADR']),

              // Снайперские показатели
              'sniper_kill_rate_per_round':
                  safeParseDouble(mapStats['Sniper Kill Rate per Round']),
              'sniper_kill_rate_per_match':
                  safeParseDouble(mapStats['Sniper Kill Rate']),
              'total_sniper_kills':
                  safeParseInt(mapStats['Total Sniper Kills']),

              // 1vX ситуации
              'v1_count': safeParseInt(mapStats['Total 1v1 Count']),
              'v2_count': safeParseInt(mapStats['Total 1v2 Count']),
              'match_1v1_win_rate': safeParseDouble(mapStats['1v1 Win Rate']),
              'match_1v2_win_rate': safeParseDouble(mapStats['1v2 Win Rate']),
              'total_1v1_wins': safeParseInt(mapStats['Total 1v1 Wins']),
              'total_1v2_wins': safeParseInt(mapStats['Total 1v2 Wins']),

              // Урон от гранат
              'utility_damage_success_rate':
                  safeParseDouble(mapStats['Utility Damage Success Rate']),
              'utility_damage_per_round':
                  safeParseDouble(mapStats['Utility Damage per Round']),
              'utility_damage': safeParseInt(mapStats['Total Utility Damage']),
              'utility_usage_per_round':
                  safeParseDouble(mapStats['Utility Usage per Round']),
              'utility_success_rate':
                  safeParseDouble(mapStats['Utility Success Rate']),
              'total_utility_successes':
                  safeParseInt(mapStats['Total Utility Successes']),
              'total_utility_count':
                  safeParseInt(mapStats['Total Utility Count']),

              // Флешки
              'enemies_flashed_per_round':
                  safeParseDouble(mapStats['Enemies Flashed per Round']),
              'flashes_per_round':
                  safeParseDouble(mapStats['Flashes per Round']),
              'flash_success_rate':
                  safeParseDouble(mapStats['Flash Success Rate']),
              'flash_successes':
                  safeParseInt(mapStats['Total Flash Successes']),
              'flash_count': safeParseInt(mapStats['Total Flash Count']),
              'total_enemies_flashed':
                  safeParseInt(mapStats['Total Enemies Flashed']),

              // Энтри фраги
              'entry_wins': safeParseInt(mapStats['Total Entry Wins']),
              'match_entry_rate': safeParseDouble(mapStats['Entry Rate']),
              'match_entry_success_rate':
                  safeParseDouble(mapStats['Entry Success Rate']),
              'entry_count': safeParseInt(mapStats['Total Entry Count']),

              // Общая статистика матчей
              'total_damage': safeParseInt(mapStats['Total Damage']),
              'total_headshots_percentage':
                  safeParseInt(mapStats['Total Headshots %']),
              'average_headshots_percentage':
                  safeParseDouble(mapStats['Average Headshots %']),
              'matches': safeParseInt(mapStats['Matches']),
              'wins': safeParseInt(mapStats['Wins']),
              'total_rounds':
                  safeParseInt(mapStats['Total Rounds with extended stats']),
              'win_rate_percentage': safeParseInt(mapStats['Win Rate %']),
              'total_kills':
                  safeParseInt(mapStats['Total Kills with extended stats']),

              // Дополнительная статистика по сегментам
              'average_kills': safeParseDouble(mapStats['Average Kills']),
              'average_deaths': safeParseDouble(mapStats['Average Deaths']),
              'average_assists': safeParseDouble(mapStats['Average Assists']),
              'headshots': safeParseInt(mapStats['Headshots']),
              'assists': safeParseInt(mapStats['Assists']),
              'deaths': safeParseInt(mapStats['Deaths']),
              'kills': safeParseInt(mapStats['Kills']),
              'rounds': safeParseInt(mapStats['Rounds']),

              // Кратные фраги
              'triple_kills': safeParseInt(mapStats['Triple Kills']),
              'quadro_kills': safeParseInt(mapStats['Quadro Kills']),
              'penta_kills': safeParseInt(mapStats['Penta Kills']),
              'average_triple_kills':
                  safeParseDouble(mapStats['Average Triple Kills']),
              'average_quadro_kills':
                  safeParseDouble(mapStats['Average Quadro Kills']),
              'average_penta_kills':
                  safeParseDouble(mapStats['Average Penta Kills']),

              // MVP
              'mvps': safeParseInt(mapStats['MVPs']),
              'average_mvps': safeParseDouble(mapStats['Average MVPs']),

              // Прочие
              'headshots_per_match':
                  safeParseDouble(mapStats['Headshots per Match']),
            });

            logger.i('Saved map stats for player $playerId on map $mapName');
          }
        }
      }
    } else if (response.statusCode == 404) {
      logger.w('Player $playerId not found or has no CS2 stats (404)');
    } else {
      logger.e(
          'Failed to load player stats: ${response.statusCode} - ${response.body}');
    }
  } catch (e) {
    logger.e('Error fetching player stats: $e');
  }

  // Небольшая задержка, чтобы не превысить лимиты API
  await Future.delayed(Duration(milliseconds: REQUEST_DELAY));
}

// Обработка тиммейтов
Future<void> processTeammates(String playerId) async {
  logger.i('Processing teammates for player $playerId');

  // Находим все матчи игрока
  final playerMatches = await db
      .query('player_matches', where: 'player_id = ?', whereArgs: [playerId]);

  if (playerMatches.isEmpty) {
    logger.w('No matches found for player $playerId');
    return;
  }

  // Словарь для подсчета матчей и побед с каждым тиммейтом
  final teammates = <String, Map<String, dynamic>>{};

  // Перебираем все матчи
  for (final playerMatch in playerMatches) {
    final matchId = playerMatch['match_id'] as String;
    final team = playerMatch['team'] as String;
    final result = playerMatch['result'] as int;

    // Находим всех игроков в той же команде
    final teammatesInMatch = await db.query('player_matches',
        where: 'match_id = ? AND team = ? AND player_id != ?',
        whereArgs: [matchId, team, playerId]);

    // Считаем матчи и победы с каждым тиммейтом
    for (final teammate in teammatesInMatch) {
      final teammateId = teammate['player_id'] as String;

      if (!teammates.containsKey(teammateId)) {
        teammates[teammateId] = {
          'teammate_id': teammateId,
          'matches': 0,
          'wins': 0
        };
      }

      teammates[teammateId]!['matches'] = teammates[teammateId]!['matches'] + 1;
      if (result == 1) {
        teammates[teammateId]!['wins'] = teammates[teammateId]!['wins'] + 1;
      }
    }
  }

  // Фильтруем тиммейтов (минимум 5 матчей вместе)
  final filteredTeammates = teammates.values.where((teammate) {
    final matches = teammate['matches'] as int;
    return matches >= 5;
  }).toList();

  logger.i(
      'Found ${filteredTeammates.length} valid teammates for player $playerId');

  // Сохраняем информацию о тиммейтах
  for (final teammate in filteredTeammates) {
    final teammateId = teammate['teammate_id'] as String;
    final matches = teammate['matches'] as int;
    final wins = teammate['wins'] as int;

    // Проверяем, есть ли уже такая запись
    final existingRecord = await db.query('teammates',
        where: 'player_id = ? AND teammate_id = ?',
        whereArgs: [playerId, teammateId]);

    if (existingRecord.isEmpty) {
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

  // Получаем статистику для тиммейтов последовательно, а не в транзакции
  for (final teammate in filteredTeammates) {
    final teammateId = teammate['teammate_id'] as String;

    // Проверяем, есть ли уже статистика
    final hasStats = await db
        .query('player_stats', where: 'player_id = ?', whereArgs: [teammateId]);

    if (hasStats.isEmpty) {
      await fetchPlayerStats(teammateId);
      // Добавляем задержку между запросами API
    }
  }

  logger.i('Processed teammates for player $playerId');
}

Future<void> exportDataForML(String outputPath) async {
  logger
      .i('Exporting complete player data for machine learning to $outputPath');

  final file = File(outputPath);
  final sink = file.openWrite();

  // Полный заголовок CSV файла, включающий все поля
  sink.writeln('player_id,nickname,'
      'kd_ratio,kr_ratio,adr,'
      'sniper_kill_rate_per_round,sniper_kill_rate_per_match,total_sniper_kills,'
      'v1_count,v2_count,match_1v1_win_rate,match_1v2_win_rate,total_1v1_wins,total_1v2_wins,'
      'utility_damage_success_rate,utility_damage_per_round,utility_damage,utility_usage_per_round,'
      'utility_success_rate,total_utility_successes,total_utility_count,'
      'enemies_flashed_per_round,flashes_per_round,flash_success_rate,flash_successes,flash_count,total_enemies_flashed,'
      'entry_wins,match_entry_rate,match_entry_success_rate,entry_count,'
      'current_win_streak,total_damage,total_headshots_percentage,average_headshots_percentage,'
      'matches,wins,total_rounds,win_rate_percentage,total_matches,longest_win_streak,total_kills');

  // Получаем всех игроков со статистикой
  final results = await db.rawQuery('''
    SELECT p.player_id, p.nickname, s.*
    FROM players p
    JOIN player_stats s ON p.player_id = s.player_id
    WHERE p.processed = 1
  ''');

  for (final row in results) {
    sink.writeln('${row['player_id']},${row['nickname']},'
        '${row['kd_ratio']},${row['kr_ratio']},${row['adr']},'
        '${row['sniper_kill_rate_per_round']},${row['sniper_kill_rate_per_match']},${row['total_sniper_kills']},'
        '${row['v1_count']},${row['v2_count']},${row['match_1v1_win_rate']},${row['match_1v2_win_rate']},'
        '${row['total_1v1_wins']},${row['total_1v2_wins']},'
        '${row['utility_damage_success_rate']},${row['utility_damage_per_round']},${row['utility_damage']},'
        '${row['utility_usage_per_round']},${row['utility_success_rate']},${row['total_utility_successes']},'
        '${row['total_utility_count']},'
        '${row['enemies_flashed_per_round']},${row['flashes_per_round']},${row['flash_success_rate']},'
        '${row['flash_successes']},${row['flash_count']},${row['total_enemies_flashed']},'
        '${row['entry_wins']},${row['match_entry_rate']},${row['match_entry_success_rate']},${row['entry_count']},'
        '${row['current_win_streak']},${row['total_damage']},${row['total_headshots_percentage']},'
        '${row['average_headshots_percentage']},${row['matches']},${row['wins']},${row['total_rounds']},'
        '${row['win_rate_percentage']},${row['total_matches']},${row['longest_win_streak']},${row['total_kills']}');
  }

  await sink.close();
  logger.i('Exported ${results.length} complete player records to $outputPath');
}

Future<void> exportTeammatesWithStatsForML(String outputPath) async {
  logger.i('Exporting complete teammates data to $outputPath');

  final file = File(outputPath);
  final sink = file.openWrite();

  // Полный заголовок CSV файла, включающий все поля статистики тиммейтов
  sink.writeln(
      'player_id,player_nickname,teammate_id,teammate_nickname,matches_together,wins_together,win_rate,'
      'teammate_kd_ratio,teammate_kr_ratio,teammate_adr,'
      'teammate_sniper_kill_rate_per_round,teammate_sniper_kill_rate_per_match,teammate_total_sniper_kills,'
      'teammate_v1_count,teammate_v2_count,teammate_match_1v1_win_rate,teammate_match_1v2_win_rate,'
      'teammate_total_1v1_wins,teammate_total_1v2_wins,'
      'teammate_utility_damage_success_rate,teammate_utility_damage_per_round,teammate_utility_damage,'
      'teammate_utility_usage_per_round,teammate_utility_success_rate,teammate_total_utility_successes,'
      'teammate_total_utility_count,'
      'teammate_enemies_flashed_per_round,teammate_flashes_per_round,teammate_flash_success_rate,'
      'teammate_flash_successes,teammate_flash_count,teammate_total_enemies_flashed,'
      'teammate_entry_wins,teammate_match_entry_rate,teammate_match_entry_success_rate,teammate_entry_count,'
      'teammate_current_win_streak,teammate_total_damage,teammate_total_headshots_percentage,'
      'teammate_average_headshots_percentage,teammate_matches,teammate_wins,teammate_total_rounds,'
      'teammate_win_rate_percentage,teammate_total_matches,teammate_longest_win_streak,teammate_total_kills');

  // Полный SQL запрос, включающий все поля статистики
  final results = await db.rawQuery('''
    SELECT 
      t.player_id, 
      p1.nickname as player_nickname, 
      t.teammate_id, 
      p2.nickname as teammate_nickname, 
      t.matches_together, 
      t.wins_together,
      (t.wins_together * 1.0 / t.matches_together) as win_rate,
      s.kd_ratio as teammate_kd_ratio,
      s.kr_ratio as teammate_kr_ratio,
      s.adr as teammate_adr,
      s.sniper_kill_rate_per_round as teammate_sniper_kill_rate_per_round,
      s.sniper_kill_rate_per_match as teammate_sniper_kill_rate_per_match,
      s.total_sniper_kills as teammate_total_sniper_kills,
      s.v1_count as teammate_v1_count,
      s.v2_count as teammate_v2_count,
      s.match_1v1_win_rate as teammate_match_1v1_win_rate,
      s.match_1v2_win_rate as teammate_match_1v2_win_rate,
      s.total_1v1_wins as teammate_total_1v1_wins,
      s.total_1v2_wins as teammate_total_1v2_wins,
      s.utility_damage_success_rate as teammate_utility_damage_success_rate,
      s.utility_damage_per_round as teammate_utility_damage_per_round,
      s.utility_damage as teammate_utility_damage,
      s.utility_usage_per_round as teammate_utility_usage_per_round,
      s.utility_success_rate as teammate_utility_success_rate,
      s.total_utility_successes as teammate_total_utility_successes,
      s.total_utility_count as teammate_total_utility_count,
      s.enemies_flashed_per_round as teammate_enemies_flashed_per_round,
      s.flashes_per_round as teammate_flashes_per_round,
      s.flash_success_rate as teammate_flash_success_rate,
      s.flash_successes as teammate_flash_successes,
      s.flash_count as teammate_flash_count,
      s.total_enemies_flashed as teammate_total_enemies_flashed,
      s.entry_wins as teammate_entry_wins,
      s.match_entry_rate as teammate_match_entry_rate,
      s.match_entry_success_rate as teammate_match_entry_success_rate,
      s.entry_count as teammate_entry_count,
      s.current_win_streak as teammate_current_win_streak,
      s.total_damage as teammate_total_damage,
      s.total_headshots_percentage as teammate_total_headshots_percentage,
      s.average_headshots_percentage as teammate_average_headshots_percentage,
      s.matches as teammate_matches,
      s.wins as teammate_wins,
      s.total_rounds as teammate_total_rounds,
      s.win_rate_percentage as teammate_win_rate_percentage,
      s.total_matches as teammate_total_matches,
      s.longest_win_streak as teammate_longest_win_streak,
      s.total_kills as teammate_total_kills
    FROM teammates t
    JOIN players p1 ON t.player_id = p1.player_id
    JOIN players p2 ON t.teammate_id = p2.player_id
    LEFT JOIN player_stats s ON t.teammate_id = s.player_id
    ORDER BY t.player_id, win_rate DESC
  ''');

  // Вывод всех полей в CSV
  for (final row in results) {
    sink.writeln('${row['player_id'] ?? ''},'
        '${row['player_nickname'] ?? ''},'
        '${row['teammate_id'] ?? ''},'
        '${row['teammate_nickname'] ?? ''},'
        '${row['matches_together'] ?? ''},'
        '${row['wins_together'] ?? ''},'
        '${row['win_rate'] ?? ''},'
        '${row['teammate_kd_ratio'] ?? ''},'
        '${row['teammate_kr_ratio'] ?? ''},'
        '${row['teammate_adr'] ?? ''},'
        '${row['teammate_sniper_kill_rate_per_round'] ?? ''},'
        '${row['teammate_sniper_kill_rate_per_match'] ?? ''},'
        '${row['teammate_total_sniper_kills'] ?? ''},'
        '${row['teammate_v1_count'] ?? ''},'
        '${row['teammate_v2_count'] ?? ''},'
        '${row['teammate_match_1v1_win_rate'] ?? ''},'
        '${row['teammate_match_1v2_win_rate'] ?? ''},'
        '${row['teammate_total_1v1_wins'] ?? ''},'
        '${row['teammate_total_1v2_wins'] ?? ''},'
        '${row['teammate_utility_damage_success_rate'] ?? ''},'
        '${row['teammate_utility_damage_per_round'] ?? ''},'
        '${row['teammate_utility_damage'] ?? ''},'
        '${row['teammate_utility_usage_per_round'] ?? ''},'
        '${row['teammate_utility_success_rate'] ?? ''},'
        '${row['teammate_total_utility_successes'] ?? ''},'
        '${row['teammate_total_utility_count'] ?? ''},'
        '${row['teammate_enemies_flashed_per_round'] ?? ''},'
        '${row['teammate_flashes_per_round'] ?? ''},'
        '${row['teammate_flash_success_rate'] ?? ''},'
        '${row['teammate_flash_successes'] ?? ''},'
        '${row['teammate_flash_count'] ?? ''},'
        '${row['teammate_total_enemies_flashed'] ?? ''},'
        '${row['teammate_entry_wins'] ?? ''},'
        '${row['teammate_match_entry_rate'] ?? ''},'
        '${row['teammate_match_entry_success_rate'] ?? ''},'
        '${row['teammate_entry_count'] ?? ''},'
        '${row['teammate_current_win_streak'] ?? ''},'
        '${row['teammate_total_damage'] ?? ''},'
        '${row['teammate_total_headshots_percentage'] ?? ''},'
        '${row['teammate_average_headshots_percentage'] ?? ''},'
        '${row['teammate_matches'] ?? ''},'
        '${row['teammate_wins'] ?? ''},'
        '${row['teammate_total_rounds'] ?? ''},'
        '${row['teammate_win_rate_percentage'] ?? ''},'
        '${row['teammate_total_matches'] ?? ''},'
        '${row['teammate_longest_win_streak'] ?? ''},'
        '${row['teammate_total_kills'] ?? ''}');
  }

  await sink.close();
  logger
      .i('Exported ${results.length} complete teammate records to $outputPath');
}

// Добавьте новую функцию:

Future<void> exportMapStatsForML(String outputPath) async {
  logger.i('Exporting player map stats for machine learning to $outputPath');

  final file = File(outputPath);
  final sink = file.openWrite();

  // Полный заголовок CSV файла для статистики по картам
  sink.writeln('player_id,nickname,map_name,'
      'kd_ratio,kr_ratio,adr,'
      'sniper_kill_rate_per_round,sniper_kill_rate_per_match,total_sniper_kills,'
      'v1_count,v2_count,match_1v1_win_rate,match_1v2_win_rate,total_1v1_wins,total_1v2_wins,'
      'utility_damage_success_rate,utility_damage_per_round,utility_damage,utility_usage_per_round,'
      'utility_success_rate,total_utility_successes,total_utility_count,'
      'enemies_flashed_per_round,flashes_per_round,flash_success_rate,flash_successes,flash_count,total_enemies_flashed,'
      'entry_wins,match_entry_rate,match_entry_success_rate,entry_count,'
      'total_damage,total_headshots_percentage,average_headshots_percentage,'
      'matches,wins,total_rounds,win_rate_percentage,total_kills,'
      'average_kills,average_deaths,average_assists,headshots,assists,deaths,kills,rounds,'
      'triple_kills,quadro_kills,penta_kills,average_triple_kills,average_quadro_kills,average_penta_kills,'
      'mvps,average_mvps,headshots_per_match');

  // Получаем все данные по картам для всех обработанных игроков
  final results = await db.rawQuery('''
    SELECT p.player_id, p.nickname, ms.*
    FROM players p
    JOIN player_map_stats ms ON p.player_id = ms.player_id
    WHERE p.processed = 1
    ORDER BY p.player_id, ms.map_name
  ''');

  for (final row in results) {
    sink.writeln('${row['player_id']},${row['nickname']},${row['map_name']},'
        '${row['kd_ratio']},${row['kr_ratio']},${row['adr']},'
        '${row['sniper_kill_rate_per_round']},${row['sniper_kill_rate_per_match']},${row['total_sniper_kills']},'
        '${row['v1_count']},${row['v2_count']},${row['match_1v1_win_rate']},${row['match_1v2_win_rate']},'
        '${row['total_1v1_wins']},${row['total_1v2_wins']},'
        '${row['utility_damage_success_rate']},${row['utility_damage_per_round']},${row['utility_damage']},'
        '${row['utility_usage_per_round']},${row['utility_success_rate']},${row['total_utility_successes']},'
        '${row['total_utility_count']},'
        '${row['enemies_flashed_per_round']},${row['flashes_per_round']},${row['flash_success_rate']},'
        '${row['flash_successes']},${row['flash_count']},${row['total_enemies_flashed']},'
        '${row['entry_wins']},${row['match_entry_rate']},${row['match_entry_success_rate']},${row['entry_count']},'
        '${row['total_damage']},${row['total_headshots_percentage']},${row['average_headshots_percentage']},'
        '${row['matches']},${row['wins']},${row['total_rounds']},${row['win_rate_percentage']},${row['total_kills']},'
        '${row['average_kills']},${row['average_deaths']},${row['average_assists']},${row['headshots']},'
        '${row['assists']},${row['deaths']},${row['kills']},${row['rounds']},'
        '${row['triple_kills']},${row['quadro_kills']},${row['penta_kills']},'
        '${row['average_triple_kills']},${row['average_quadro_kills']},${row['average_penta_kills']},'
        '${row['mvps']},${row['average_mvps']},${row['headshots_per_match']}');
  }

  await sink.close();
  logger.i('Exported ${results.length} map stat records to $outputPath');
}

Future<void> exportCompleteDataToJson(String outputPath) async {
  logger.i('Exporting complete data to JSON file: $outputPath');

  // Получаем всех обработанных игроков
  final playersResult = await db.rawQuery('''
    SELECT * FROM players WHERE processed = 1
  ''');

  final players = <Map<String, dynamic>>[];

  for (final playerRow in playersResult) {
    final playerId = playerRow['player_id'] as String;
    final player = {
      'player_id': playerId,
      'nickname': playerRow['nickname'],
      'skill_level': playerRow['skill_level'],
      'faceit_elo': playerRow['faceit_elo'],
      'country': playerRow['country'],
      'stats': {},
      'map_stats': [],
      'teammates': []
    };

    // Получаем статистику игрока
    final statsResult = await db.rawQuery('''
      SELECT * FROM player_stats WHERE player_id = ?
    ''', [playerId]);

    if (statsResult.isNotEmpty) {
      player['stats'] = Map<String, dynamic>.from(statsResult.first);
    }

    // Получаем статистику по картам
    final mapStatsResult = await db.rawQuery('''
      SELECT * FROM player_map_stats WHERE player_id = ? ORDER BY map_name
    ''', [playerId]);

    player['map_stats'] = List<Map<String, dynamic>>.from(
        mapStatsResult.map((row) => Map<String, dynamic>.from(row)));

    // Получаем тиммейтов с их статистикой
    final teammatesResult = await db.rawQuery('''
      SELECT 
        t.id as teammate_relation_id,
        t.player_id,
        t.teammate_id,
        t.matches_together,
        t.wins_together,
        p.nickname as teammate_nickname,
        p.skill_level as teammate_skill_level,
        p.faceit_elo as teammate_faceit_elo,
        p.country as teammate_country,
        (t.wins_together * 1.0 / t.matches_together) as win_rate
      FROM teammates t
      JOIN players p ON t.teammate_id = p.player_id
      WHERE t.player_id = ?
      ORDER BY win_rate DESC
    ''', [playerId]);

    final teammates = <Map<String, dynamic>>[];

    for (final teammateRow in teammatesResult) {
      final teammateId = teammateRow['teammate_id'] as String;
      final teammate = {
        'teammate_id': teammateId,
        'teammate_nickname': teammateRow['teammate_nickname'],
        'teammate_skill_level': teammateRow['teammate_skill_level'],
        'teammate_faceit_elo': teammateRow['teammate_faceit_elo'],
        'teammate_country': teammateRow['teammate_country'],
        'matches_together': teammateRow['matches_together'],
        'wins_together': teammateRow['wins_together'],
        'win_rate': teammateRow['win_rate'],
        'stats': {},
        'map_stats': []
      };

      // Получаем общую статистику тиммейта
      final teammateStatsResult = await db.rawQuery('''
        SELECT * FROM player_stats WHERE player_id = ?
      ''', [teammateId]);

      if (teammateStatsResult.isNotEmpty) {
        teammate['stats'] =
            Map<String, dynamic>.from(teammateStatsResult.first);
      }

      // Получаем статистику по картам для тиммейта
      final teammateMapStatsResult = await db.rawQuery('''
        SELECT * FROM player_map_stats WHERE player_id = ? ORDER BY map_name
      ''', [teammateId]);

      teammate['map_stats'] = List<Map<String, dynamic>>.from(
          teammateMapStatsResult.map((row) => Map<String, dynamic>.from(row)));

      teammates.add(teammate);
    }

    player['teammates'] = teammates;
    players.add(player);
  }

  // Создаем итоговую структуру JSON
  final completeData = {
    'export_date': DateTime.now().toIso8601String(),
    'total_players': players.length,
    'players': players
  };

  // Записываем в файл
  final file = File(outputPath);

  try {
    final jsonString = jsonEncode(completeData);
    await file.writeAsString(jsonString);
    logger.i(
        'Exported complete data for ${players.length} players to $outputPath');
  } catch (e) {
    logger.e('Error writing JSON file: $e');
    // Попытка записать с более простым подходом в случае ошибки
    try {
      const encoder = JsonEncoder.withIndent('  '); // Более читабельный формат
      final jsonString = encoder.convert(completeData);
      await file.writeAsString(jsonString);
      logger.i(
          'Exported data with simplified encoder for ${players.length} players');
    } catch (e2) {
      logger.e('Failed to write JSON even with simplified encoder: $e2');
      rethrow;
    }
  }
}
