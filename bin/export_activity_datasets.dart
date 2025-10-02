import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

String? _argValue(List<String> args, String name) {
  for (var i = 0; i < args.length; i++) {
    if (args[i] == name && i + 1 < args.length) return args[i + 1];
    if (args[i].startsWith('$name=')) return args[i].split('=')[1];
  }
  return null;
}

List<T> _sample<T>(List<T> list, int n, Random rnd) {
  if (list.isEmpty) return const [];
  if (n >= list.length) return List<T>.from(list);
  final indices = List<int>.generate(list.length, (i) => i);
  // partial Fisher–Yates for first n
  for (var i = 0; i < n; i++) {
    final j = i + rnd.nextInt(list.length - i);
    final tmp = indices[i];
    indices[i] = indices[j];
    indices[j] = tmp;
  }
  return List<T>.generate(n, (k) => list[indices[k]]);
}

Future<void> main(List<String> args) async {
  final outDir = _argValue(args, '--out') ?? 'out/ml';
  final sampleSize = int.tryParse(_argValue(args, '--sample') ?? '100') ?? 100;
  final seed = int.tryParse(_argValue(args, '--seed') ?? '42') ?? 42;

  // Init SQLite
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  // Determine DB path (same as main app). Default to faceit_stats.db in default databases path.
  final db =
      await openDatabase(p.join((await getDatabasesPath()), 'faceit_stats.db'));

  try {
    final playersRows = await db.rawQuery(
      'SELECT player_id, nickname, skill_level, faceit_elo, country FROM players WHERE processed = 1',
    );

    final players = <Map<String, dynamic>>[];

    for (final row in playersRows) {
      final playerId = row['player_id'] as String;

      // Hours 0..23
      final hours = List<int>.filled(24, 0);
      final hoursRes = await db.rawQuery(
        'SELECT hour, matches_count FROM player_activity_hours WHERE player_id = ?',
        [playerId],
      );
      for (final hrow in hoursRes) {
        final h = (hrow['hour'] as int?) ?? 0;
        final c = (hrow['matches_count'] as int?) ?? 0;
        if (h >= 0 && h < 24) hours[h] = c;
      }

      // Weekdays 1..7 -> 0..6 (Mon..Sun)
      final weekdays = List<int>.filled(7, 0);
      final wdRes = await db.rawQuery(
        'SELECT weekday, matches_count FROM player_activity_weekdays WHERE player_id = ?',
        [playerId],
      );
      for (final wdRow in wdRes) {
        final wd = (wdRow['weekday'] as int?) ?? 0;
        final c = (wdRow['matches_count'] as int?) ?? 0;
        if (wd >= 1 && wd <= 7) weekdays[wd - 1] = c;
      }

      final total = hours.fold<int>(0, (a, b) => a + b);
      final hoursNorm = total > 0
          ? hours.map((c) => c / total).toList()
          : List<double>.filled(24, 0.0);
      final weekdaysNorm = total > 0
          ? weekdays.map((c) => c / total).toList()
          : List<double>.filled(7, 0.0);

      // Two-hour slots (12) using average and also sum + normalized
      final hours2hAvg = List<double>.generate(
          12, (i) => ((hours[i * 2] + hours[i * 2 + 1]) / 2.0));
      final hours2hSum =
          List<int>.generate(12, (i) => (hours[i * 2] + hours[i * 2 + 1]));
      final sum2h = hours2hSum.fold<int>(0, (a, b) => a + b);
      final hours2hNorm = sum2h > 0
          ? hours2hSum.map((c) => c / sum2h).toList()
          : List<double>.filled(12, 0.0);

      players.add({
        'player_id': playerId,
        'nickname': row['nickname'],
        'skill_level': row['skill_level'],
        'faceit_elo': row['faceit_elo'],
        'country': row['country'],
        'activity_hours_24': hours,
        'activity_hours_24_norm': hoursNorm,
        'activity_hours_2h_avg_12': hours2hAvg,
        'activity_hours_2h_norm_12': hours2hNorm,
        'activity_weekdays_7': weekdays,
        'activity_weekdays_norm_7': weekdaysNorm,
        'total_activity_matches': total,
      });
    }

    // Prepare directories
    final dirTimeslots = Directory(p.join(outDir, 'timeslots'));
    final dirWeekdays = Directory(p.join(outDir, 'weekdays'));
    await dirTimeslots.create(recursive: true);
    await dirWeekdays.create(recursive: true);

    // 2-hour slot labels
    final slotLabels = List<String>.generate(12, (i) {
      final start = (i * 2).toString().padLeft(2, '0');
      final end = ((i * 2 + 2) % 24).toString().padLeft(2, '0');
      return '$start-$end';
    });

    // Timeslot files with 100 sampled players each
    for (var i = 0; i < 12; i++) {
      final rnd = Random(seed + i);
      final sampled = _sample(players, sampleSize, rnd);

      final file = File(p.join(dirTimeslots.path, '${slotLabels[i]}.jsonl'));
      final sink = file.openWrite();
      try {
        for (final p in sampled) {
          final line = {
            'player_id': p['player_id'],
            'nickname': p['nickname'],
            'skill_level': p['skill_level'],
            'faceit_elo': p['faceit_elo'],
            'country': p['country'],
            'slot_index': i,
            'slot_label': slotLabels[i],
            'slot_avg': (p['activity_hours_2h_avg_12'] as List).elementAt(i),
            'slot_sum': (p['activity_hours_24'] as List)[i * 2] +
                (p['activity_hours_24'] as List)[i * 2 + 1],
            'slot_frac': (p['activity_hours_2h_norm_12'] as List).elementAt(i),
            // Full feature vectors
            'hours2h_avg_12': p['activity_hours_2h_avg_12'],
            'hours2h_norm_12': p['activity_hours_2h_norm_12'],
            'hours24': p['activity_hours_24'],
            'hours24_norm': p['activity_hours_24_norm'],
            'weekdays7': p['activity_weekdays_7'],
            'weekdays7_norm': p['activity_weekdays_norm_7'],
            'total_activity_matches': p['total_activity_matches'],
          };
          sink.writeln(jsonEncode(line));
        }
      } finally {
        await sink.close();
      }
    }

    // Weekday files with 100 sampled players each
    const wdNames = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
    for (var d = 0; d < 7; d++) {
      final rnd = Random(seed + 100 + d);
      final sampled = _sample(players, sampleSize, rnd);

      final file = File(p.join(dirWeekdays.path, '${wdNames[d]}.jsonl'));
      final sink = file.openWrite();
      try {
        for (final p in sampled) {
          final wdCount = (p['activity_weekdays_7'] as List)[d] as int;
          final wdFrac = (p['activity_weekdays_norm_7'] as List)[d] as double;

          final line = {
            'player_id': p['player_id'],
            'nickname': p['nickname'],
            'skill_level': p['skill_level'],
            'faceit_elo': p['faceit_elo'],
            'country': p['country'],
            'weekday_index': d, // 0..6 => Mon..Sun
            'weekday_label': wdNames[d],
            'weekday_count': wdCount,
            'weekday_frac': wdFrac,
            // Full feature vectors
            'hours2h_avg_12': p['activity_hours_2h_avg_12'],
            'hours2h_norm_12': p['activity_hours_2h_norm_12'],
            'hours24': p['activity_hours_24'],
            'hours24_norm': p['activity_hours_24_norm'],
            'weekdays7': p['activity_weekdays_7'],
            'weekdays7_norm': p['activity_weekdays_norm_7'],
            'total_activity_matches': p['total_activity_matches'],
          };
          sink.writeln(jsonEncode(line));
        }
      } finally {
        await sink.close();
      }
    }

    stdout.writeln('Datasets saved to: $outDir');
  } finally {
    await db.close();
  }
}
