import 'package:logger/logger.dart';
import '../../services/faceit_api.dart';
import '../../repositories/stats_repository.dart';

class PlayerStatsFetcher {
  final FaceitApi api;
  final StatsRepository statsRepo;
  final Logger logger;
  final Set<String> _loaded = {};
  PlayerStatsFetcher(
      {required this.api, required this.statsRepo, required this.logger});

  Future<void> fetchIfNeeded(String playerId, {String? debugName}) async {
    if (_loaded.contains(playerId)) return;
    if (await statsRepo.hasPlayerStats(playerId)) {
      _loaded.add(playerId);
      return;
    }
    final data = await api.fetchPlayerStats(playerId);
    if (data == null) return;
    final lifetime = data['lifetime'];
    if (lifetime == null) return;

    double d(dynamic v) {
      if (v == null) return 0.0;
      final s = v.toString().replaceAll('%', '').replaceAll(',', '.');
      return double.tryParse(s) ?? 0.0;
    }

    int i(dynamic v) {
      if (v == null) return 0;
      final s = v.toString().replaceAll('%', '');
      return int.tryParse(s) ?? 0;
    }

    await statsRepo.insertPlayerStats({
      'player_id': playerId,
      'kd_ratio': d(lifetime['K/D Ratio']),
      'kr_ratio': d(lifetime['Average K/R Ratio']),
      'adr': d(lifetime['ADR']),
      'sniper_kill_rate_per_round': d(lifetime['Sniper Kill Rate per Round']),
      'sniper_kill_rate_per_match': d(lifetime['Sniper Kill Rate']),
      'total_sniper_kills': i(lifetime['Total Sniper Kills']),
      'v1_count': i(lifetime['Total 1v1 Count']),
      'v2_count': i(lifetime['Total 1v2 Count']),
      'match_1v1_win_rate': d(lifetime['1v1 Win Rate']),
      'match_1v2_win_rate': d(lifetime['1v2 Win Rate']),
      'utility_damage_success_rate': d(lifetime['Utility Damage Success Rate']),
      'utility_damage_per_round': d(lifetime['Utility Damage per Round']),
      'utility_damage': i(lifetime['Total Utility Damage']),
      'utility_usage_per_round': d(lifetime['Utility Usage per Round']),
      'enemies_flashed_per_round': d(lifetime['Enemies Flashed per Round']),
      'flashes_per_round': d(lifetime['Flashes per Round']),
      'flash_success_rate': d(lifetime['Flash Success Rate']),
      'flash_successes': i(lifetime['Total Flash Successes']),
      'flash_count': i(lifetime['Total Flash Count']),
      'entry_wins': i(lifetime['Total Entry Wins']),
      'match_entry_rate': d(lifetime['Entry Rate']),
      'match_entry_success_rate': d(lifetime['Entry Success Rate']),
      'entry_count': i(lifetime['Total Entry Count']),
      'current_win_streak': i(lifetime['Current Win Streak']),
      'total_damage': i(lifetime['Total Damage']),
      'total_utility_successes': i(lifetime['Total Utility Successes']),
      'total_headshots_percentage': i(lifetime['Total Headshots %']),
      'average_headshots_percentage': d(lifetime['Average Headshots %']),
      'matches': i(lifetime['Matches']),
      'wins': i(lifetime['Wins']),
      'total_rounds': i(lifetime['Total Rounds with extended stats']),
      'win_rate_percentage': i(lifetime['Win Rate %']),
      'total_matches': i(lifetime['Total Matches']),
      'longest_win_streak': i(lifetime['Longest Win Streak']),
      'total_1v1_wins': i(lifetime['Total 1v1 Wins']),
      'total_1v2_wins': i(lifetime['Total 1v2 Wins']),
      'total_utility_count': i(lifetime['Total Utility Count']),
      'total_kills': i(lifetime['Total Kills with extended stats']),
      'utility_success_rate': d(lifetime['Utility Success Rate']),
      'total_enemies_flashed': i(lifetime['Total Enemies Flashed']),
    });
    // Per-map stats (segments)
    final segments = data['segments'];
    if (segments is List) {
      for (final seg in segments) {
        if (seg is! Map) continue;
        final mode = seg['mode'];
        if (mode != '5v5') continue; // keep 5v5 only
        final segStats = seg['stats'];
        final label = seg['label']; // map name
        if (segStats is! Map || label == null) continue;
        final mapName = label.toString();
        if (await statsRepo.hasMapStats(playerId, mapName)) continue;
        try {
          await statsRepo.insertMapStats({
            'player_id': playerId,
            'map_name': mapName,
            'kd_ratio': d(segStats['K/D Ratio']),
            'kr_ratio': d(segStats['Average K/R Ratio']),
            'adr': d(segStats['ADR']),
            'sniper_kill_rate_per_round':
                d(segStats['Sniper Kill Rate per Round']),
            'sniper_kill_rate_per_match': d(segStats['Sniper Kill Rate']),
            'total_sniper_kills': i(segStats['Total Sniper Kills']),
            'v1_count': i(segStats['Total 1v1 Count']),
            'v2_count': i(segStats['Total 1v2 Count']),
            'match_1v1_win_rate': d(segStats['1v1 Win Rate']),
            'match_1v2_win_rate': d(segStats['1v2 Win Rate']),
            'utility_damage_success_rate':
                d(segStats['Utility Damage Success Rate']),
            'utility_damage_per_round': d(segStats['Utility Damage per Round']),
            'utility_damage': i(segStats['Total Utility Damage']),
            'utility_usage_per_round': d(segStats['Utility Usage per Round']),
            'utility_success_rate': d(segStats['Utility Success Rate']),
            'enemies_flashed_per_round':
                d(segStats['Enemies Flashed per Round']),
            'flashes_per_round': d(segStats['Flashes per Round']),
            'flash_success_rate': d(segStats['Flash Success Rate']),
            'flash_successes': i(segStats['Total Flash Successes']),
            'flash_count': i(segStats['Total Flash Count']),
            'entry_wins': i(segStats['Total Entry Wins']),
            'match_entry_rate': d(segStats['Entry Rate']),
            'match_entry_success_rate': d(segStats['Entry Success Rate']),
            'entry_count': i(segStats['Total Entry Count']),
            'total_damage': i(segStats['Total Damage']),
            'total_utility_successes': i(segStats['Total Utility Successes']),
            'total_headshots_percentage': i(segStats['Total Headshots %']),
            'average_headshots_percentage': d(segStats['Average Headshots %']),
            'matches': i(segStats['Matches']),
            'wins': i(segStats['Wins']),
            'total_rounds': i(segStats['Total Rounds with extended stats']),
            'win_rate_percentage': i(segStats['Win Rate %']),
            'total_kills': i(segStats['Total Kills with extended stats']),
            'average_kills': d(segStats['Average Kills']),
            'average_deaths': d(segStats['Average Deaths']),
            'average_assists': d(segStats['Average Assists']),
            'headshots': i(segStats['Total Headshots']),
            'assists': i(segStats['Total Assists']),
            'deaths': i(segStats['Total Deaths']),
            'kills': i(segStats['Total Kills']),
            'rounds': i(segStats['Rounds']),
            'triple_kills': i(segStats['Total Triple Kills']),
            'quadro_kills': i(segStats['Total Quadro Kills']),
            'penta_kills': i(segStats['Total Penta Kills']),
            'average_triple_kills': d(segStats['Average Triple Kills']),
            'average_quadro_kills': d(segStats['Average Quadro Kills']),
            'average_penta_kills': d(segStats['Average Penta Kills']),
            'mvps': i(segStats['Total MVPs']),
            'average_mvps': d(segStats['Average MVPs']),
            'headshots_per_match': d(segStats['Headshots per Match']),
          });
        } catch (e) {
          logger.w('Failed to insert map stats for $playerId/$mapName: $e');
        }
      }
    }
    _loaded.add(playerId);
  }
}
