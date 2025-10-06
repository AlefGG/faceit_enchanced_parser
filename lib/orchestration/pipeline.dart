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
    final total = players.length;
    final pipelineStart = DateTime.now();
    for (final p in players) {
      final playerStart = DateTime.now();
      final playerId = p['player_id'] as String;
      final nickname = (p['nickname'] ?? '') as String;
      final indexDisplay = processed + 1; // 1-based
      final percent = total == 0 ? 0 : ((indexDisplay / total) * 100);
      logger.i(
          '[PLAYER_PROGRESS] start {idx:$indexDisplay,total:$total,percent:${percent.toStringAsFixed(1)}%,player:$nickname,$playerId}');
      await statsFetcher.fetchIfNeeded(playerId, debugName: nickname);
      final ingested = await matchesIngestor.ingestMatches(playerId, nickname,
          target: AppConfig.matchesPerPlayer);
      await recentFetcher.fetchRecent(playerId,
          limit: AppConfig.activityMatchWindow);
      await activityCalc.recompute(playerId, AppConfig.activityMatchWindow);
      await playerRepo.markProcessed(playerId);
      // Teammates (after matches ingested)
      await teammatesProcessor.process(db, playerId,
          minMatches: AppConfig.minTeammateMatches);
      // Fetch recent stats + activity for each teammate (limit 20) to enrich export
      final teammateIds = await db.rawQuery(
          'SELECT teammate_id FROM teammates WHERE player_id = ?', [playerId]);
      int teammateEnriched = 0;
      for (final row in teammateIds) {
        final tid = row['teammate_id'] as String;
        // Recent detailed stats (skip if already have some recent rows)
        await recentFetcher.fetchRecent(tid,
            limit: AppConfig.activityMatchWindow);
        await activityCalc.recompute(tid, AppConfig.activityMatchWindow);
        teammateEnriched++;
      }
      processed++;
      final playerElapsed = DateTime.now().difference(playerStart);
      final elapsedTotal = DateTime.now().difference(pipelineStart);
      final avgPerPlayerMs = processed == 0
          ? 0
          : (elapsedTotal.inMilliseconds / processed).round();
      final remainingPlayers = total - processed;
      final estRemainingMs = remainingPlayers * avgPerPlayerMs;
      final eta = Duration(milliseconds: estRemainingMs);
      logger.i(
          '[PLAYER_PROGRESS] done {idx:$indexDisplay,total:$total,percent:${percent.toStringAsFixed(1)}%,player:$nickname,$playerId,matches_ingested:$ingested,teammates:$teammateEnriched,elapsed_s:${playerElapsed.inSeconds},eta:${_fmtDur(eta)}}');
    }
    // Export after processing batch
    final timestamp = DateTime.now();
    final name =
        'faceit_complete_data_${timestamp.toIso8601String().replaceAll(':', '-')}.json';
    await exporter.export(name);
    final totalElapsed = DateTime.now().difference(pipelineStart);
    final avgMs =
        processed == 0 ? 0 : (totalElapsed.inMilliseconds / processed).round();
    logger.i('Pipeline completed for $processed players. Export: $name');
    logger.i(
        '[PIPELINE_SUMMARY] total_elapsed:${_fmtDur(totalElapsed)} total_s:${totalElapsed.inSeconds} avg_per_player_ms:$avgMs');
  }
}

String _fmtDur(Duration d) {
  String two(int v) => v.toString().padLeft(2, '0');
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60);
  return '${two(h)}:${two(m)}:${two(s)}';
}
