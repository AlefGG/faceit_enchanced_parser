import 'package:logger/logger.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../repositories/player_repository.dart';
import '../repositories/match_repository.dart';
import '../repositories/stats_repository.dart';
import '../repositories/activity_repository.dart';
import '../repositories/teammate_repository.dart';
import '../services/faceit_api.dart';
import '../core/config.dart';
import '../features/ingestion/top_players_ingestor.dart';
import '../features/ingestion/player_matches_ingestor.dart';
import '../features/ingestion/player_stats_fetcher.dart';
import '../features/ingestion/recent_detailed_stats_fetcher.dart';
import '../features/processing/activity_calculator.dart';
import '../features/processing/teammates_processor.dart';
import '../features/export/export_complete_data.dart';

class Pipeline {
  final Database db;
  final Logger logger;
  final FaceitApi api;
  Pipeline({required this.db, required this.logger, required this.api});

  Future<void> run(int startIndex, int endIndex) async {
    final playerRepo = PlayerRepository(db);
    final matchRepo = MatchRepository(db);
    final statsRepo = StatsRepository(db);
    final activityRepo = ActivityRepository(db);
    final teammateRepo = TeammateRepository(db);

    final topIngestor =
        TopPlayersIngestor(api: api, players: playerRepo, logger: logger);
    final matchesIngestor = PlayerMatchesIngestor(
        api: api,
        matchesRepo: matchRepo,
        playerRepo: playerRepo,
        logger: logger);
    final statsFetcher =
        PlayerStatsFetcher(api: api, statsRepo: statsRepo, logger: logger);
    final recentFetcher = RecentDetailedStatsFetcher(
        api: api, matchRepo: matchRepo, statsRepo: statsRepo, logger: logger);
    final activityCalc = ActivityCalculator(repo: activityRepo, logger: logger);
    final teammatesProcessor = TeammatesProcessor(
        teammateRepo: teammateRepo,
        playerRepo: playerRepo,
        statsRepo: statsRepo,
        statsFetcher: statsFetcher,
        api: api,
        logger: logger);
    final exporter = CompleteDataExporter(db: db, logger: logger);

    final limit = endIndex - startIndex;
    await topIngestor.ensureTopPlayers(endIndex);
    final players =
        await playerRepo.fetchUnprocessedTopRange(limit, startIndex);
    int processed = 0;
    for (final p in players) {
      final playerId = p['player_id'] as String;
      final nickname = (p['nickname'] ?? '') as String;
      await statsFetcher.fetchIfNeeded(playerId, debugName: nickname);
      await matchesIngestor.ingestMatches(playerId, nickname,
          target: AppConfig.matchesPerPlayer);
      await recentFetcher.fetchRecent(playerId,
          limit: AppConfig.activityMatchWindow);
      await activityCalc.recompute(playerId, AppConfig.activityMatchWindow);
      await playerRepo.markProcessed(playerId);
      // Teammates (after matches ingested)
      await teammatesProcessor.process(db, playerId,
          minMatches: AppConfig.minTeammateMatches);
      processed++;
    }
    // Export after processing batch
    final timestamp = DateTime.now();
    final name =
        'faceit_complete_data_${timestamp.toIso8601String().replaceAll(':', '-')}.json';
    await exporter.export(name);
    logger.i('Pipeline completed for $processed players. Export: $name');
  }
}
