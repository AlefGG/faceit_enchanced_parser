part of 'faceit_enchanced_parser.dart';

Future<void> collectData() async {
  // Шаг 1: Получаем топ игроков (только если их ещё нет)
  await fetchTopPlayers();

  // Шаг 2: Обрабатываем игроков из топа в указанном диапазоне, по порядку топа
  final players = await db.rawQuery('''
    SELECT * FROM players 
    WHERE processed = 0 AND source = 'top'
    ORDER BY rank_order
    LIMIT ? OFFSET ?
  ''', [PLAYER_LIMIT, startPlayerIndex]);

  logger.i(
      'Found ${players.length} top players to process (range $startPlayerIndex..${startPlayerIndex + players.length})');

  int processedCount = 0;
  const int progressBatchSize = 10; // сохраняем прогресс батчами

  for (final player in players) {
    final playerId = player['player_id'] as String;

    logger.i(
        'Processed ${processedCount + 1}/${players.length}: ${player['nickname']}, $playerId');

    // 1) Общая статистика игрока
    await fetchPlayerStats(playerId);

    // 2) Последние 300 матчей (учитываем только 5v5 внутри функции)
    final fetched =
        await fetchPlayerMatches(playerId, player['nickname'].toString());
    logger.i('Fetched $fetched matches for $playerId');

    // 3) Тиммейты (>=5 совместных матчей). Для тиммейтов — только общие статы.
    await processTeammates(playerId);

    // Отмечаем игрока как обработанного
    await db.update('players', {'processed': 1},
        where: 'player_id = ?', whereArgs: [playerId]);

    processedCount++;

    // Сохраняем прогресс батчами
    if (processedCount % progressBatchSize == 0) {
      await saveProgress(startPlayerIndex + processedCount);
    }
  }

  // Сохраняем финальный прогресс
  await saveProgress(startPlayerIndex + processedCount);
}

// Получение топ игроков с пагинацией (загружаем, только если ещё не загружали source='top')
Future<void> fetchTopPlayers() async {
  logger.i('Ensuring top list (limit $PLAYER_LIMIT) is present');

  final countResult = await db
      .rawQuery("SELECT COUNT(*) AS c FROM players WHERE source = 'top'");
  final topCount = (countResult.first['c'] as int?) ?? 0;

  if (topCount > 0) {
    logger.i('Top list already present: $topCount players');
    return;
  }

  try {
    int offset = 0;
    final maxLimit = 100; // лимит API
    int totalFetched = 0;
    int rankBase = 0;

    while (totalFetched < PLAYER_LIMIT) {
      final currentLimit = (PLAYER_LIMIT - totalFetched) > maxLimit
          ? maxLimit
          : (PLAYER_LIMIT - totalFetched);

      logger.i('Fetching TOP players $offset..${offset + currentLimit}');
      final url =
          'https://open.faceit.com/data/v4/rankings/games/cs2/regions/EU?offset=$offset&limit=$currentLimit';
      final response = await reliableHttpGet(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $apiKey',
        },
        logger: logger,
      );

      if (response.statusCode != 200) {
        logger.e(
            'Failed to load top players: ${response.statusCode} - ${response.body}');
        break;
      }

      final data = jsonDecode(response.body);
      final items = List<Map<String, dynamic>>.from(data['items'] ?? []);
      if (items.isEmpty) {
        logger.w('No more top players available from API');
        break;
      }

      await db.transaction((txn) async {
        final batch = txn.batch();
        for (int i = 0; i < items.length; i++) {
          final p = items[i];
          final rankOrder = rankBase + totalFetched + i;
          batch.insert(
            'players',
            {
              'player_id': p['player_id'],
              'nickname': p['nickname'],
              'country': p['country'],
              'skill_level': p['skill_level'],
              'faceit_elo': p['faceit_elo'],
              'processed': 0,
              'source': 'top',
              'rank_order': rankOrder,
            },
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        }
        await batch.commit(noResult: true);
      });

      totalFetched += items.length;
      offset += currentLimit;
      logger.i('Stored ${items.length} top players (total $totalFetched)');
      await Future.delayed(Duration(milliseconds: REQUEST_DELAY));
    }

    logger.i('Completed fetching and storing top players: $totalFetched');
  } catch (e) {
    logger.e('Failed to fetch/store top players: $e');
  }
}

// Получение матчей игрока с пагинацией
Future<int> fetchPlayerMatches(String playerId, String playerName) async {
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
    int totalFetched = 0; // всего получено от API
    int acceptedFetched = 0; // принято в БД (только 5v5)
    final int targetCount = MATCHES_PER_PLAYER;

    while (acceptedFetched < targetCount) {
      // Определяем количество записей для текущего запроса
      final currentLimit = (targetCount - totalFetched) > maxLimit
          ? maxLimit
          : (targetCount - totalFetched);

      logger.i(
          'Fetching matches $offset to ${offset + currentLimit} for player $playerName $playerId');

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

            // Фильтруем только 5v5
            final gameMode = (match['game_mode'] ?? '').toString();
            if (gameMode != '5v5') {
              continue;
            }

            // Проверяем, есть ли уже такой матч
            final existingMatch = await txn
                .query('matches', where: 'match_id = ?', whereArgs: [matchId]);

            if (existingMatch.isEmpty) {
              // Сохраняем информацию о матче
              await txn.insert('matches', {
                'match_id': matchId,
                'game_mode': gameMode,
                'map': match['map'] ?? '',
                'region': match['region'] ?? '',
                'date': match['started_at'] ?? 0,
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
            }

            // Сохраняем/актуализируем информацию об игроках в матче (всегда)
            for (final faction in ['faction1', 'faction2']) {
              if (match['teams'][faction] != null &&
                  match['teams'][faction]['players'] != null) {
                final roster = List<Map<String, dynamic>>.from(
                    match['teams'][faction]['players']);
                for (final player in roster) {
                  final thisPlayerId = player['player_id'];
                  final winner = match['results'] != null
                      ? match['results']['winner']
                      : null;
                  final result = winner == faction ? 1 : 0;

                  // Данные профиля из ростера (когда доступны)
                  final nickname = (player['nickname'] ?? '').toString();
                  final country = (player['country'] ?? '').toString();
                  int? skillLevel;
                  int? faceitElo;
                  // skill_level/faceit_elo могут быть либо на верхнем уровне, либо в game_profile
                  final dynamic sl =
                      player['skill_level'] ?? player['cs2_skill_level'];
                  final dynamic fe =
                      player['faceit_elo'] ?? player['cs2_faceit_elo'];
                  if (sl is int)
                    skillLevel = sl;
                  else if (sl != null) {
                    skillLevel = int.tryParse('$sl');
                  }
                  if (fe is int)
                    faceitElo = fe;
                  else if (fe != null) {
                    faceitElo = int.tryParse('$fe');
                  }
                  final gp = player['game_profile'];
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

                  // Добавляем игрока, если его ещё нет в базе, сразу с известными полями
                  final existingPlayer = await txn.query('players',
                      where: 'player_id = ?', whereArgs: [thisPlayerId]);

                  if (existingPlayer.isEmpty) {
                    await txn.insert('players', {
                      'player_id': thisPlayerId,
                      'nickname': nickname,
                      'country': country.isNotEmpty ? country : null,
                      'skill_level': skillLevel,
                      'faceit_elo': faceitElo,
                      'processed': 0,
                      'source': 'discovered',
                      'rank_order': null,
                    });
                  } else {
                    // Обновляем только отсутствующие поля
                    final row = existingPlayer.first;
                    final updateMap = <String, Object?>{};
                    if ((row['nickname'] == null ||
                            (row['nickname'] as String).isEmpty) &&
                        nickname.isNotEmpty) {
                      updateMap['nickname'] = nickname;
                    }
                    if (row['country'] == null && country.isNotEmpty) {
                      updateMap['country'] = country;
                    }
                    if (row['skill_level'] == null && skillLevel != null) {
                      updateMap['skill_level'] = skillLevel;
                    }
                    if (row['faceit_elo'] == null && faceitElo != null) {
                      updateMap['faceit_elo'] = faceitElo;
                    }
                    if (updateMap.isNotEmpty) {
                      await txn.update('players', updateMap,
                          where: 'player_id = ?', whereArgs: [thisPlayerId]);
                    }
                  }

                  // Связываем игрока с матчем, если еще нет записи. Храним снимок профиля из ростера.
                  final existingLink = await txn.query('player_matches',
                      where: 'player_id = ? AND match_id = ?',
                      whereArgs: [thisPlayerId, matchId]);
                  final linkSnapshot = {
                    'player_id': thisPlayerId,
                    'match_id': matchId,
                    'team': faction,
                    'result': result,
                    'nickname': nickname.isNotEmpty ? nickname : null,
                    'country': country.isNotEmpty ? country : null,
                    'skill_level': skillLevel,
                    'faceit_elo': faceitElo,
                  };
                  if (existingLink.isEmpty) {
                    await txn.insert('player_matches', linkSnapshot);
                  } else {
                    // Обновление снимка: заполняем только NULL значения
                    final row = existingLink.first;
                    final updateLink = <String, Object?>{};
                    if ((row['nickname'] == null ||
                            (row['nickname'] as String?)?.isEmpty == true) &&
                        linkSnapshot['nickname'] != null) {
                      updateLink['nickname'] = linkSnapshot['nickname'];
                    }
                    if (row['country'] == null &&
                        linkSnapshot['country'] != null) {
                      updateLink['country'] = linkSnapshot['country'];
                    }
                    if (row['skill_level'] == null &&
                        linkSnapshot['skill_level'] != null) {
                      updateLink['skill_level'] = linkSnapshot['skill_level'];
                    }
                    if (row['faceit_elo'] == null &&
                        linkSnapshot['faceit_elo'] != null) {
                      updateLink['faceit_elo'] = linkSnapshot['faceit_elo'];
                    }
                    if (updateLink.isNotEmpty) {
                      await txn.update('player_matches', updateLink,
                          where: 'player_id = ? AND match_id = ?',
                          whereArgs: [thisPlayerId, matchId]);
                    }
                  }
                }
              }
            }

            // Если у целевого игрока есть линк на этот матч, считаем его принятым
            final linkForPlayer = await txn.query('player_matches',
                where: 'player_id = ? AND match_id = ?',
                whereArgs: [playerId, matchId]);
            if (linkForPlayer.isNotEmpty) {
              acceptedFetched++;
            }
          }
        });

        totalFetched += matches.length;
        offset += currentLimit;
        logger.i(
            'Saved $acceptedFetched accepted (5v5) matches so far for player $playerId, API total: $totalFetched/$targetCount');

        // Добавляем задержку между запросами
        await Future.delayed(Duration(milliseconds: REQUEST_DELAY));
      } else {
        logger.e(
            'Failed to load player matches: ${response.statusCode} - ${response.body}');
        break; // Прерываем цикл при ошибке
      }
    }

    logger.i(
        'Completed fetching $acceptedFetched 5v5 matches for player $playerId');
    return acceptedFetched;
  } catch (e) {
    logger.e('Error fetching player matches: $e');
    return 0;
  }
}

// Получение статистики игрока
Future<void> fetchPlayerStats(
  String playerId,
) async {
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
          final cleaned = value.replaceAll('%', '').replaceAll(',', '.').trim();
          return double.parse(cleaned);
        } catch (e) {
          return 0.0;
        }
      }

      int safeParseInt(String? value) {
        if (value == null || value.isEmpty) return 0;
        try {
          final cleaned = value.replaceAll('%', '').trim();
          return int.parse(cleaned);
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

  // Для тиммейтов дотягиваем только общие статы при их отсутствии
  for (final teammate in filteredTeammates) {
    final teammateId = teammate['teammate_id'] as String;

    final hasStats = await db
        .query('player_stats', where: 'player_id = ?', whereArgs: [teammateId]);
    if (hasStats.isEmpty) {
      await fetchPlayerStats(teammateId);
    }
  }
}

// Бэкфилл: если у тиммейта нет faceit_elo, присваиваем ELO из последнего совместного матча (снимок ростера)
Future<void> backfillProfilesFromRosters() async {
  logger.i('Backfilling missing teammate profiles from roster snapshots');
  // Находим пары (player_id, teammate_id) где у teammate нет faceit_elo
  final rows = await db.rawQuery('''
    SELECT DISTINCT t.player_id, t.teammate_id
    FROM teammates t
    JOIN players p ON p.player_id = t.teammate_id
    WHERE p.faceit_elo IS NULL
  ''');

  for (final row in rows) {
    final playerId = row['player_id'] as String;
    final teammateId = row['teammate_id'] as String;

    // Ищем последний совместный матч и берем снимок профиля teammate
    final mutual = await db.rawQuery('''
      SELECT pm2.faceit_elo, pm2.skill_level, pm2.country, pm2.nickname, m.date
      FROM player_matches pm1
      JOIN player_matches pm2 ON pm1.match_id = pm2.match_id AND pm2.player_id = ?
      JOIN matches m ON m.match_id = pm1.match_id
      WHERE pm1.player_id = ?
      ORDER BY m.date DESC
      LIMIT 1
    ''', [teammateId, playerId]);

    if (mutual.isEmpty) continue;
    final snap = mutual.first;
    final int? snapElo = snap['faceit_elo'] as int?;
    final int? snapLevel = snap['skill_level'] as int?;
    final String? snapCountry = snap['country'] as String?;
    final String? snapNick = snap['nickname'] as String?;

    final update = <String, Object?>{};
    if (snapElo != null) update['faceit_elo'] = snapElo;
    // По желанию также можем заполнить прочие поля, если они отсутствуют
    final teammateRow = await db
        .query('players', where: 'player_id = ?', whereArgs: [teammateId]);
    if (teammateRow.isNotEmpty) {
      final r = teammateRow.first;
      if (r['skill_level'] == null && snapLevel != null)
        update['skill_level'] = snapLevel;
      if ((r['nickname'] == null || (r['nickname'] as String).isEmpty) &&
          (snapNick != null && snapNick.isNotEmpty))
        update['nickname'] = snapNick;
      if (r['country'] == null &&
          (snapCountry != null && snapCountry.isNotEmpty))
        update['country'] = snapCountry;
    }

    if (update.isNotEmpty) {
      await db.update('players', update,
          where: 'player_id = ?', whereArgs: [teammateId]);
      logger.i(
          'Backfilled ${update.keys.join(', ')} for $teammateId from last mutual match');
    }
  }
}
