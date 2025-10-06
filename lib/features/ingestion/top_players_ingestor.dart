import 'package:logger/logger.dart';
import '../../services/faceit_api.dart';
import '../../repositories/player_repository.dart';
import '../../models/player.dart';

class TopPlayersIngestor {
  final FaceitApi api;
  final PlayerRepository players;
  final Logger logger;
  TopPlayersIngestor(
      {required this.api, required this.players, required this.logger});

  Future<void> ensureTopPlayers(int target, {int pageSize = 100}) async {
    final existing = await players.countTopPlayers();
    if (existing >= target) {
      logger.i('Top already loaded: $existing >= $target');
      return;
    }
    int fetched = existing;
    int offset = existing; // continue if partially loaded
    while (fetched < target) {
      final limit =
          (target - fetched) > pageSize ? pageSize : (target - fetched);
      logger.i('Fetch top segment offset=$offset limit=$limit');
      final items = await api.fetchTopPlayers(offset: offset, limit: limit);
      if (items.isEmpty) {
        logger.w('No more top players from API');
        break;
      }
      final batch = <Player>[];
      for (int i = 0; i < items.length; i++) {
        final p = items[i];
        batch.add(Player(
          playerId: p['player_id'],
          nickname: p['nickname'],
          country: p['country'],
          skillLevel: p['skill_level'],
          faceitElo: p['faceit_elo'],
          processed: false,
          source: 'top',
          rankOrder: offset + i,
        ));
      }
      await players.insertTopPlayers(batch);
      fetched += items.length;
      offset += items.length;
    }
    logger.i('Top ingest complete: stored $fetched');
  }
}
