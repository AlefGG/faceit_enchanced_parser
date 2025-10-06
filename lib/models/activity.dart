class HourActivity {
  final String playerId;
  final int hour; // 0..23
  final int matchesCount;
  final int? windowSize;
  HourActivity(
      {required this.playerId,
      required this.hour,
      required this.matchesCount,
      this.windowSize});
  factory HourActivity.fromMap(Map<String, dynamic> m) => HourActivity(
        playerId: m['player_id'] as String,
        hour: m['hour'] as int,
        matchesCount: m['matches_count'] as int,
        windowSize: m['window_size'] as int?,
      );
  Map<String, dynamic> toMap() => {
        'player_id': playerId,
        'hour': hour,
        'matches_count': matchesCount,
        'window_size': windowSize,
      };
}

class WeekdayActivity {
  final String playerId;
  final int weekday; // 1..7
  final int matchesCount;
  final int? windowSize;
  WeekdayActivity(
      {required this.playerId,
      required this.weekday,
      required this.matchesCount,
      this.windowSize});
  factory WeekdayActivity.fromMap(Map<String, dynamic> m) => WeekdayActivity(
        playerId: m['player_id'] as String,
        weekday: m['weekday'] as int,
        matchesCount: m['matches_count'] as int,
        windowSize: m['window_size'] as int?,
      );
  Map<String, dynamic> toMap() => {
        'player_id': playerId,
        'weekday': weekday,
        'matches_count': matchesCount,
        'window_size': windowSize,
      };
}
