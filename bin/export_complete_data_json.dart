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
