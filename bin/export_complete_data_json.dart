import 'dart:convert';
import 'dart:io';

import 'package:logger/logger.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> exportCompleteDataToJson(
  String outputPath,
  Logger logger,
  Database db,
) async {
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
      'activity': {},
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

    // Активность игрока: пересчитываем on-the-fly по последним 20 матчам (UTC)
    final recentMatchesForActivity = await db.rawQuery('''
      SELECT COALESCE(m.finished_at, m.date) AS ts
      FROM matches m
      JOIN player_matches pm ON pm.match_id = m.match_id
      WHERE pm.player_id = ?
      ORDER BY COALESCE(m.finished_at, m.date) DESC
      LIMIT 20
    ''', [playerId]);

    final hoursArr = List<int>.filled(24, 0);
    final weekdaysArr = List<int>.filled(7, 0); // Mon=1..Sun=7 => idx 0..6
    for (final row in recentMatchesForActivity) {
      final ts = row['ts'];
      if (ts == null) continue;
      int epoch;
      if (ts is int) {
        epoch = ts;
      } else if (ts is BigInt) {
        epoch = ts.toInt();
      } else {
        continue;
      }
      if (epoch == 0) continue;
      final dt = DateTime.fromMillisecondsSinceEpoch(epoch * 1000, isUtc: true);
      hoursArr[dt.hour] += 1;
      weekdaysArr[dt.weekday - 1] += 1;
    }
    final totalActivity = recentMatchesForActivity.length;

    // Мапы для удобства потребления: часы как строки "0".."23", дни как названия
    final hourlyDistribution = <String, int>{
      for (var i = 0; i < 24; i++) i.toString(): hoursArr[i]
    };
    const weekdayNames = [
      'monday',
      'tuesday',
      'wednesday',
      'thursday',
      'friday',
      'saturday',
      'sunday'
    ];
    final dailyDistribution = <String, int>{
      for (var i = 0; i < 7; i++) weekdayNames[i]: weekdaysArr[i]
    };

    player['activity'] = {
      'total_activity_matches': totalActivity,
      'hourly_distribution': hourlyDistribution,
      'daily_distribution': dailyDistribution,
      'activity_window_matches': 20,
    };

    // Insights: топ-3 пика активности по комбинациям (день недели, час)
    final matchRows = await db.rawQuery('''
      SELECT m.date as started_at, m.finished_at as finished_at
      FROM matches m
      JOIN player_matches pm ON pm.match_id = m.match_id
      WHERE pm.player_id = ?
      ORDER BY m.date DESC
      LIMIT 300
    ''', [playerId]);

    // Счетчики по (weekday 1..7, hour 0..23)
    final Map<int, Map<int, int>> dayHourCounts = {};
    for (final r in matchRows) {
      final int ts =
          (r['finished_at'] as int?) ?? (r['started_at'] as int?) ?? 0;
      if (ts == 0) continue;
      final dt = DateTime.fromMillisecondsSinceEpoch(ts * 1000, isUtc: true);
      final wd = dt.weekday; // 1..7 (Mon..Sun)
      final h = dt.hour; // 0..23
      dayHourCounts.putIfAbsent(wd, () => {});
      dayHourCounts[wd]![h] = (dayHourCounts[wd]![h] ?? 0) + 1;
    }

    // Строим список всех комбинаций с их счетчиками
    final combos = <Map<String, dynamic>>[];
    for (var wd = 1; wd <= 7; wd++) {
      final m = dayHourCounts[wd] ?? const {};
      for (var h = 0; h < 24; h++) {
        final c = m[h] ?? 0;
        if (c > 0) {
          combos.add({
            'day': weekdayNames[wd - 1],
            'hour': h,
            'matches_count': c,
          });
        }
      }
    }

    combos.sort((a, b) {
      final ca = a['matches_count'] as int;
      final cb = b['matches_count'] as int;
      if (cb != ca) return cb.compareTo(ca); // по убыванию
      final da = a['day'] as String;
      final dbs = b['day'] as String;
      final cmpDay = da.compareTo(dbs);
      if (cmpDay != 0) return cmpDay;
      return (a['hour'] as int).compareTo(b['hour'] as int);
    });

    final topDayHour = <Map<String, dynamic>>[];
    for (var i = 0; i < combos.length && i < 10; i++) {
      final item = Map<String, dynamic>.from(combos[i]);
      item['rank'] = i + 1;
      topDayHour.add(item);
    }

    player['activity_insights'] = {
      'top_day_hour_combinations': topDayHour,
    };

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
