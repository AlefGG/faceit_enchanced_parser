import 'dart:async';
import 'dart:io';
import 'package:dotenv/dotenv.dart';
import 'package:logger/logger.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart';
import 'dart:convert';
import 'package:args/args.dart';
import 'export_complete_data_json.dart';
import 'reliable_http_get.dart';
import 'create_db.dart';

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
      onCreate: (db, version) {
        createDb(db, version);
      },
    );

    logger.i('Database initialized at $path');

    // Создаем имена файлов с учетом префикса, временной метки и диапазона игроков
    final rangeStamp = '_${startPlayerIndex}_$endPlayerIndex';

    final completeDataFile =
        '${outputPrefix}_complete_data$dateTimeStamp$rangeStamp.json';

    // Вызываем функции экспорта с новыми именами файлов
    await exportCompleteDataToJson(completeDataFile, logger, db);
    // Закрываем базу данных
    await db.close();
    logger.i('Data collection completed');
  } catch (e, stackTrace) {
    logger.e('Fatal error during execution', error: e, stackTrace: stackTrace);
    exit(1);
  }
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
      final response = await reliableHttpGet(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $apiKey',
        },
        logger: logger,
      );

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
      final response = await reliableHttpGet(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $apiKey',
        },
        logger: logger,
      );

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
    final response = await reliableHttpGet(
      Uri.parse(url),
      headers: {
        'Authorization': 'Bearer $apiKey',
      },
      logger: logger,
    );

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
