import 'package:logger/logger.dart';
import '../../repositories/activity_repository.dart';

class ActivityCalculator {
  final ActivityRepository repo;
  final Logger logger;
  ActivityCalculator({required this.repo, required this.logger});

  Future<void> recompute(String playerId, int window) async {
    final timestamps = await repo.recentMatchesTimestamps(playerId, window);
    final hours = List<int>.filled(24, 0);
    final weekdays = List<int>.filled(7, 0);
    for (final row in timestamps) {
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
      hours[dt.hour] += 1;
      weekdays[dt.weekday - 1] += 1;
    }
    final hourRows = <Map<String, Object?>>[];
    for (int h = 0; h < 24; h++) {
      hourRows.add({
        'player_id': playerId,
        'hour': h,
        'matches_count': hours[h],
        'window_size': window
      });
    }
    final weekdayRows = <Map<String, Object?>>[];
    for (int i = 0; i < 7; i++) {
      weekdayRows.add({
        'player_id': playerId,
        'weekday': i + 1,
        'matches_count': weekdays[i],
        'window_size': window
      });
    }
    await repo.replaceActivity(playerId, hourRows, weekdayRows);
    logger.d('Recomputed activity for $playerId (window=$window)');
  }
}
