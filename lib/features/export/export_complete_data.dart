import 'dart:convert';
import 'dart:io';
import 'package:logger/logger.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class CompleteDataExporter {
  final Database db;
  final Logger logger;
  CompleteDataExporter({required this.db, required this.logger});

  Future<void> export(String outputPath) async {
    logger.i('Exporting complete data to $outputPath');
    final playersResult =
        await db.rawQuery('SELECT * FROM players WHERE processed = 1');
    final players = <Map<String, dynamic>>[];
    for (final pr in playersResult) {
      final playerId = pr['player_id'] as String;
      final player = {
        'player_id': playerId,
        'nickname': pr['nickname'],
        'skill_level': pr['skill_level'],
        'faceit_elo': pr['faceit_elo'],
        'country': pr['country'],
        'stats': {},
        'map_stats': [],
        'activity': {},
        'teammates': []
      };
      final stats = await db.rawQuery(
          'SELECT * FROM player_stats WHERE player_id = ?', [playerId]);
      if (stats.isNotEmpty)
        player['stats'] = Map<String, dynamic>.from(stats.first);
      final mapStats = await db.rawQuery(
          'SELECT * FROM player_map_stats WHERE player_id = ? ORDER BY map_name',
          [playerId]);
      player['map_stats'] =
          mapStats.map((r) => Map<String, dynamic>.from(r)).toList();
      final recentMatches = await db.rawQuery('''
        SELECT COALESCE(m.finished_at, m.date) AS ts
        FROM matches m JOIN player_matches pm ON pm.match_id = m.match_id
        WHERE pm.player_id = ?
        ORDER BY COALESCE(m.finished_at, m.date) DESC
        LIMIT 20
      ''', [playerId]);
      final hoursArr = List<int>.filled(24, 0);
      final weekdaysArr = List<int>.filled(7, 0);
      for (final row in recentMatches) {
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
        final dt =
            DateTime.fromMillisecondsSinceEpoch(epoch * 1000, isUtc: true);
        hoursArr[dt.hour] += 1;
        weekdaysArr[dt.weekday - 1] += 1;
      }
      final weekdayNames = [
        'monday',
        'tuesday',
        'wednesday',
        'thursday',
        'friday',
        'saturday',
        'sunday'
      ];
      player['activity'] = {
        'total_activity_matches': recentMatches.length,
        'hourly_distribution': {
          for (var i = 0; i < 24; i++) i.toString(): hoursArr[i]
        },
        'daily_distribution': {
          for (var i = 0; i < 7; i++) weekdayNames[i]: weekdaysArr[i]
        },
        'activity_window_matches': 20,
      };
      final recentAgg = await db.rawQuery('''
        SELECT COUNT(*) as matches, AVG(kills) as avg_kills, AVG(deaths) as avg_deaths, AVG(assists) as avg_assists, AVG(adr) as avg_adr,
               AVG(kr_ratio) as avg_kr_ratio, AVG(kd_ratio) as avg_kd_ratio, AVG(headshots) as avg_headshots, AVG(headshots_percentage) as avg_headshots_percentage,
               AVG(mvps) as avg_mvps, AVG(entry_count) as avg_entry_count, AVG(entry_wins) as avg_entry_wins, AVG(clutch_kills) as avg_clutch_kills,
               AVG(sniper_kills) as avg_sniper_kills, AVG(flash_count) as avg_flash_count, AVG(flash_successes) as avg_flash_successes,
               AVG(utility_damage) as avg_utility_damage, AVG(utility_usage_per_round) as avg_utility_usage_per_round, AVG(utility_damage_per_round) as avg_utility_damage_per_round,
               AVG(enemies_flashed) as avg_enemies_flashed
        FROM recent_player_match_stats WHERE player_id = ? ORDER BY created_at DESC LIMIT 20
      ''', [playerId]);
      if (recentAgg.isNotEmpty &&
          ((recentAgg.first['matches'] as int?) ?? 0) > 0) {
        final ra = recentAgg.first;
        double? rd(String k, [int f = 2]) {
          final v = ra[k];
          if (v == null) return null;
          if (v is num) return double.parse(v.toStringAsFixed(f));
          return null;
        }

        player['recent_20_avg_stats'] = {
          'matches_count': ra['matches'],
          'kills': rd('avg_kills'),
          'deaths': rd('avg_deaths'),
          'assists': rd('avg_assists'),
          'adr': rd('avg_adr'),
          'kr_ratio': rd('avg_kr_ratio'),
          'kd_ratio': rd('avg_kd_ratio'),
          'headshots': rd('avg_headshots'),
          'headshots_percentage': rd('avg_headshots_percentage'),
          'mvps': rd('avg_mvps'),
          'entry_count': rd('avg_entry_count'),
          'entry_wins': rd('avg_entry_wins'),
          'clutch_kills': rd('avg_clutch_kills'),
          'sniper_kills': rd('avg_sniper_kills'),
          'flash_count': rd('avg_flash_count'),
          'flash_successes': rd('avg_flash_successes'),
          'utility_damage': rd('avg_utility_damage'),
          'utility_usage_per_round': rd('avg_utility_usage_per_round'),
          'utility_damage_per_round': rd('avg_utility_damage_per_round'),
          'enemies_flashed': rd('avg_enemies_flashed'),
          'window_size': 20,
        };
      }
      final matchRows = await db.rawQuery('''
        SELECT m.finished_at, m.date FROM matches m JOIN player_matches pm ON pm.match_id = m.match_id
        WHERE pm.player_id = ? ORDER BY COALESCE(m.finished_at, m.date) DESC LIMIT 20
      ''', [playerId]);
      final counts = <int, Map<int, int>>{}; // wd -> hour -> c
      for (final r in matchRows) {
        final ts = (r['finished_at'] as int?) ?? (r['date'] as int?) ?? 0;
        if (ts == 0) continue;
        final dt = DateTime.fromMillisecondsSinceEpoch(ts * 1000, isUtc: true);
        final wd = dt.weekday;
        final h = dt.hour;
        counts.putIfAbsent(wd, () => {});
        counts[wd]![h] = (counts[wd]![h] ?? 0) + 1;
      }
      final weekdayNames2 = [
        'monday',
        'tuesday',
        'wednesday',
        'thursday',
        'friday',
        'saturday',
        'sunday'
      ];
      final combos = <Map<String, dynamic>>[];
      for (var wd = 1; wd <= 7; wd++) {
        final m = counts[wd] ?? {};
        for (var h = 0; h < 24; h++) {
          final c = m[h] ?? 0;
          if (c > 0)
            combos.add(
                {'day': weekdayNames2[wd - 1], 'hour': h, 'matches_count': c});
        }
      }
      combos.sort((a, b) {
        final cb = b['matches_count'] as int;
        final ca = a['matches_count'] as int;
        if (cb != ca) return cb.compareTo(ca);
        final da = a['day'] as String;
        final dbs = b['day'] as String;
        final cmp = da.compareTo(dbs);
        if (cmp != 0) return cmp;
        return (a['hour'] as int).compareTo(b['hour'] as int);
      });
      final top = <Map<String, dynamic>>[];
      for (var i = 0; i < combos.length && i < 10; i++) {
        final it = Map<String, dynamic>.from(combos[i]);
        it['rank'] = i + 1;
        top.add(it);
      }
      player['activity_insights'] = {'top_day_hour_combinations': top};
      final teammates = await db.rawQuery('''
        SELECT t.teammate_id,
               p.nickname as teammate_nickname,
               p.skill_level as teammate_skill_level,
               p.faceit_elo as teammate_faceit_elo,
               p.country as teammate_country,
               t.matches_together,
               t.wins_together,
               (t.wins_together * 1.0 / t.matches_together) as win_rate
        FROM teammates t 
        JOIN players p ON t.teammate_id = p.player_id
        WHERE t.player_id = ? 
        ORDER BY t.matches_together DESC
      ''', [playerId]);
      final teammatesJson = <Map<String, dynamic>>[];
      for (final t in teammates) {
        final tid = t['teammate_id'] as String;
        // Lifetime stats
        final statRows = await db.rawQuery(
            'SELECT * FROM player_stats WHERE player_id = ? LIMIT 1', [tid]);
        Map<String, dynamic> statsObj = {};
        if (statRows.isNotEmpty) {
          final s = statRows.first;
          statsObj = Map<String, dynamic>.from(s)
            ..remove('player_id'); // player_id redundant inside teammate object
        }
        // Map stats
        final mapRows = await db.rawQuery(
            'SELECT * FROM player_map_stats WHERE player_id = ? ORDER BY map_name',
            [tid]);
        final mapStatsList = mapRows
            .map((m) => Map<String, dynamic>.from(m)
              ..remove('player_id')
              ..remove('id'))
            .toList();
        // Teammate activity (reuse recent 20 matches logic)
        final recentMatchesT = await db.rawQuery('''
          SELECT COALESCE(m.finished_at, m.date) AS ts
          FROM matches m JOIN player_matches pm ON pm.match_id = m.match_id
          WHERE pm.player_id = ?
          ORDER BY COALESCE(m.finished_at, m.date) DESC
          LIMIT 20
        ''', [tid]);
        final hoursArrT = List<int>.filled(24, 0);
        final weekdaysArrT = List<int>.filled(7, 0);
        for (final row in recentMatchesT) {
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
          final dt =
              DateTime.fromMillisecondsSinceEpoch(epoch * 1000, isUtc: true);
          hoursArrT[dt.hour] += 1;
          weekdaysArrT[dt.weekday - 1] += 1;
        }
        final weekdayNames = [
          'monday',
          'tuesday',
          'wednesday',
          'thursday',
          'friday',
          'saturday',
          'sunday'
        ];
        final teammateActivity = {
          'total_activity_matches': recentMatchesT.length,
          'hourly_distribution': {
            for (var i = 0; i < 24; i++) i.toString(): hoursArrT[i]
          },
          'daily_distribution': {
            for (var i = 0; i < 7; i++) weekdayNames[i]: weekdaysArrT[i]
          },
          'activity_window_matches': 20,
        };
        // Activity insights (top 10 day-hour combos) for teammate
        final matchRowsT = await db.rawQuery('''
          SELECT m.finished_at, m.date FROM matches m JOIN player_matches pm ON pm.match_id = m.match_id
          WHERE pm.player_id = ? ORDER BY COALESCE(m.finished_at, m.date) DESC LIMIT 20
        ''', [tid]);
        final countsT = <int, Map<int, int>>{}; // wd -> hour -> c
        for (final r in matchRowsT) {
          final ts = (r['finished_at'] as int?) ?? (r['date'] as int?) ?? 0;
          if (ts == 0) continue;
          final dt =
              DateTime.fromMillisecondsSinceEpoch(ts * 1000, isUtc: true);
          final wd = dt.weekday;
          final h = dt.hour;
          countsT.putIfAbsent(wd, () => {});
          countsT[wd]![h] = (countsT[wd]![h] ?? 0) + 1;
        }
        final weekdayNames2 = [
          'monday',
          'tuesday',
          'wednesday',
          'thursday',
          'friday',
          'saturday',
          'sunday'
        ];
        final combosT = <Map<String, dynamic>>[];
        for (var wd = 1; wd <= 7; wd++) {
          final m = countsT[wd] ?? {};
          for (var h = 0; h < 24; h++) {
            final c = m[h] ?? 0;
            if (c > 0) {
              combosT.add({
                'day': weekdayNames2[wd - 1],
                'hour': h,
                'matches_count': c
              });
            }
          }
        }
        combosT.sort((a, b) {
          final cb = b['matches_count'] as int;
          final ca = a['matches_count'] as int;
          if (cb != ca) return cb.compareTo(ca);
          final da = a['day'] as String;
          final dbs = b['day'] as String;
          final cmp = da.compareTo(dbs);
          if (cmp != 0) return cmp;
          return (a['hour'] as int).compareTo(b['hour'] as int);
        });
        final topT = <Map<String, dynamic>>[];
        for (var i = 0; i < combosT.length && i < 10; i++) {
          final it = Map<String, dynamic>.from(combosT[i]);
          it['rank'] = i + 1;
          topT.add(it);
        }
        final teammateActivityInsights = {'top_day_hour_combinations': topT};
        // Teammate recent average stats
        final recentAggT = await db.rawQuery('''
          SELECT COUNT(*) as matches, AVG(kills) as avg_kills, AVG(deaths) as avg_deaths, AVG(assists) as avg_assists, AVG(adr) as avg_adr,
                 AVG(kr_ratio) as avg_kr_ratio, AVG(kd_ratio) as avg_kd_ratio, AVG(headshots) as avg_headshots, AVG(headshots_percentage) as avg_headshots_percentage,
                 AVG(mvps) as avg_mvps, AVG(entry_count) as avg_entry_count, AVG(entry_wins) as avg_entry_wins, AVG(clutch_kills) as avg_clutch_kills,
                 AVG(sniper_kills) as avg_sniper_kills, AVG(flash_count) as avg_flash_count, AVG(flash_successes) as avg_flash_successes,
                 AVG(utility_damage) as avg_utility_damage, AVG(utility_usage_per_round) as avg_utility_usage_per_round, AVG(utility_damage_per_round) as avg_utility_damage_per_round,
                 AVG(enemies_flashed) as avg_enemies_flashed
          FROM recent_player_match_stats WHERE player_id = ? ORDER BY created_at DESC LIMIT 20
        ''', [tid]);
        Map<String, dynamic>? recentAvgT;
        if (recentAggT.isNotEmpty &&
            ((recentAggT.first['matches'] as int?) ?? 0) > 0) {
          final ra = recentAggT.first;
          double? rd(String k, [int f = 2]) {
            final v = ra[k];
            if (v == null) return null;
            if (v is num) return double.parse(v.toStringAsFixed(f));
            return null;
          }

          recentAvgT = {
            'matches_count': ra['matches'],
            'kills': rd('avg_kills'),
            'deaths': rd('avg_deaths'),
            'assists': rd('avg_assists'),
            'adr': rd('avg_adr'),
            'kr_ratio': rd('avg_kr_ratio'),
            'kd_ratio': rd('avg_kd_ratio'),
            'headshots': rd('avg_headshots'),
            'headshots_percentage': rd('avg_headshots_percentage'),
            'mvps': rd('avg_mvps'),
            'entry_count': rd('avg_entry_count'),
            'entry_wins': rd('avg_entry_wins'),
            'clutch_kills': rd('avg_clutch_kills'),
            'sniper_kills': rd('avg_sniper_kills'),
            'flash_count': rd('avg_flash_count'),
            'flash_successes': rd('avg_flash_successes'),
            'utility_damage': rd('avg_utility_damage'),
            'utility_usage_per_round': rd('avg_utility_usage_per_round'),
            'utility_damage_per_round': rd('avg_utility_damage_per_round'),
            'enemies_flashed': rd('avg_enemies_flashed'),
            'window_size': 20,
          };
        }
        teammatesJson.add({
          'teammate_id': tid,
          'teammate_nickname': t['teammate_nickname'],
          'teammate_skill_level': t['teammate_skill_level'],
          'teammate_faceit_elo': t['teammate_faceit_elo'],
          'teammate_country': t['teammate_country'],
          'matches_together': t['matches_together'],
          'wins_together': t['wins_together'],
          'win_rate': t['win_rate'],
          'stats': statsObj,
          'map_stats': mapStatsList,
          'activity': teammateActivity,
          'activity_insights': teammateActivityInsights,
          if (recentAvgT != null) 'recent_20_avg_stats': recentAvgT,
        });
      }
      player['teammates'] = teammatesJson;
      players.add(player);
    }
    final complete = {
      'export_date': DateTime.now().toIso8601String(),
      'total_players': players.length,
      'players': players
    };
    final jsonString = jsonEncode(complete);
    logger.i('Total players exported: ${players.length}');
    final file = File(outputPath);
    await file.writeAsString(jsonString);
  }
}
