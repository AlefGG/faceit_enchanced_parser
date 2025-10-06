/// Global configuration & constants
class AppConfig {
  static const int matchesPerPlayer = 300; // historical window for base stats
  static const int activityMatchWindow =
      20; // recent window for activity/insights
  static const int requestDelayMs = 150; // HTTP pacing
  static const int dbRequestDelayMs = 0;
  static const int minTeammateMatches = 5; // threshold for teammate inclusion
  static const int detailedStatsParallelism =
      4; // max concurrent match detailed stats requests
}
