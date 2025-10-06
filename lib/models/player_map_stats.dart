class PlayerMapStats {
  final int? id;
  final String playerId;
  final String mapName;
  final double? kdRatio;
  final double? krRatio;
  final double? adr;
  final double? sniperKillRatePerRound;
  final double? sniperKillRatePerMatch;
  final int? totalSniperKills;
  final int? v1Count;
  final int? v2Count;
  final double? match1v1WinRate;
  final double? match1v2WinRate;
  final int? total1v1Wins;
  final int? total1v2Wins;
  final double? utilityDamageSuccessRate;
  final double? utilityDamagePerRound;
  final int? utilityDamage;
  final double? utilityUsagePerRound;
  final double? utilitySuccessRate;
  final int? totalUtilitySuccesses;
  final int? totalUtilityCount;
  final double? enemiesFlashedPerRound;
  final double? flashesPerRound;
  final double? flashSuccessRate;
  final int? flashSuccesses;
  final int? flashCount;
  final int? totalEnemiesFlashed;
  final int? entryWins;
  final double? matchEntryRate;
  final double? matchEntrySuccessRate;
  final int? entryCount;
  final int? totalDamage;
  final int? totalHeadshotsPercentage;
  final double? averageHeadshotsPercentage;
  final int? matches;
  final int? wins;
  final int? totalRounds;
  final int? winRatePercentage;
  final int? totalKills;
  final double? averageKills;
  final double? averageDeaths;
  final double? averageAssists;
  final int? headshots;
  final int? assists;
  final int? deaths;
  final int? kills;
  final int? rounds;
  final int? tripleKills;
  final int? quadroKills;
  final int? pentaKills;
  final double? averageTripleKills;
  final double? averageQuadroKills;
  final double? averagePentaKills;
  final int? mvps;
  final double? averageMvps;
  final double? headshotsPerMatch;

  PlayerMapStats({
    this.id,
    required this.playerId,
    required this.mapName,
    this.kdRatio,
    this.krRatio,
    this.adr,
    this.sniperKillRatePerRound,
    this.sniperKillRatePerMatch,
    this.totalSniperKills,
    this.v1Count,
    this.v2Count,
    this.match1v1WinRate,
    this.match1v2WinRate,
    this.total1v1Wins,
    this.total1v2Wins,
    this.utilityDamageSuccessRate,
    this.utilityDamagePerRound,
    this.utilityDamage,
    this.utilityUsagePerRound,
    this.utilitySuccessRate,
    this.totalUtilitySuccesses,
    this.totalUtilityCount,
    this.enemiesFlashedPerRound,
    this.flashesPerRound,
    this.flashSuccessRate,
    this.flashSuccesses,
    this.flashCount,
    this.totalEnemiesFlashed,
    this.entryWins,
    this.matchEntryRate,
    this.matchEntrySuccessRate,
    this.entryCount,
    this.totalDamage,
    this.totalHeadshotsPercentage,
    this.averageHeadshotsPercentage,
    this.matches,
    this.wins,
    this.totalRounds,
    this.winRatePercentage,
    this.totalKills,
    this.averageKills,
    this.averageDeaths,
    this.averageAssists,
    this.headshots,
    this.assists,
    this.deaths,
    this.kills,
    this.rounds,
    this.tripleKills,
    this.quadroKills,
    this.pentaKills,
    this.averageTripleKills,
    this.averageQuadroKills,
    this.averagePentaKills,
    this.mvps,
    this.averageMvps,
    this.headshotsPerMatch,
  });

  factory PlayerMapStats.fromMap(Map<String, dynamic> m) => PlayerMapStats(
        id: m['id'] as int?,
        playerId: m['player_id'] as String,
        mapName: m['map_name'] as String,
        kdRatio: (m['kd_ratio'] as num?)?.toDouble(),
        krRatio: (m['kr_ratio'] as num?)?.toDouble(),
        adr: (m['adr'] as num?)?.toDouble(),
        sniperKillRatePerRound:
            (m['sniper_kill_rate_per_round'] as num?)?.toDouble(),
        sniperKillRatePerMatch:
            (m['sniper_kill_rate_per_match'] as num?)?.toDouble(),
        totalSniperKills: m['total_sniper_kills'] as int?,
        v1Count: m['v1_count'] as int?,
        v2Count: m['v2_count'] as int?,
        match1v1WinRate: (m['match_1v1_win_rate'] as num?)?.toDouble(),
        match1v2WinRate: (m['match_1v2_win_rate'] as num?)?.toDouble(),
        total1v1Wins: m['total_1v1_wins'] as int?,
        total1v2Wins: m['total_1v2_wins'] as int?,
        utilityDamageSuccessRate:
            (m['utility_damage_success_rate'] as num?)?.toDouble(),
        utilityDamagePerRound:
            (m['utility_damage_per_round'] as num?)?.toDouble(),
        utilityDamage: m['utility_damage'] as int?,
        utilityUsagePerRound:
            (m['utility_usage_per_round'] as num?)?.toDouble(),
        utilitySuccessRate: (m['utility_success_rate'] as num?)?.toDouble(),
        totalUtilitySuccesses: m['total_utility_successes'] as int?,
        totalUtilityCount: m['total_utility_count'] as int?,
        enemiesFlashedPerRound:
            (m['enemies_flashed_per_round'] as num?)?.toDouble(),
        flashesPerRound: (m['flashes_per_round'] as num?)?.toDouble(),
        flashSuccessRate: (m['flash_success_rate'] as num?)?.toDouble(),
        flashSuccesses: m['flash_successes'] as int?,
        flashCount: m['flash_count'] as int?,
        totalEnemiesFlashed: m['total_enemies_flashed'] as int?,
        entryWins: m['entry_wins'] as int?,
        matchEntryRate: (m['match_entry_rate'] as num?)?.toDouble(),
        matchEntrySuccessRate:
            (m['match_entry_success_rate'] as num?)?.toDouble(),
        entryCount: m['entry_count'] as int?,
        totalDamage: m['total_damage'] as int?,
        totalHeadshotsPercentage: m['total_headshots_percentage'] as int?,
        averageHeadshotsPercentage:
            (m['average_headshots_percentage'] as num?)?.toDouble(),
        matches: m['matches'] as int?,
        wins: m['wins'] as int?,
        totalRounds: m['total_rounds'] as int?,
        winRatePercentage: m['win_rate_percentage'] as int?,
        totalKills: m['total_kills'] as int?,
        averageKills: (m['average_kills'] as num?)?.toDouble(),
        averageDeaths: (m['average_deaths'] as num?)?.toDouble(),
        averageAssists: (m['average_assists'] as num?)?.toDouble(),
        headshots: m['headshots'] as int?,
        assists: m['assists'] as int?,
        deaths: m['deaths'] as int?,
        kills: m['kills'] as int?,
        rounds: m['rounds'] as int?,
        tripleKills: m['triple_kills'] as int?,
        quadroKills: m['quadro_kills'] as int?,
        pentaKills: m['penta_kills'] as int?,
        averageTripleKills: (m['average_triple_kills'] as num?)?.toDouble(),
        averageQuadroKills: (m['average_quadro_kills'] as num?)?.toDouble(),
        averagePentaKills: (m['average_penta_kills'] as num?)?.toDouble(),
        mvps: m['mvps'] as int?,
        averageMvps: (m['average_mvps'] as num?)?.toDouble(),
        headshotsPerMatch: (m['headshots_per_match'] as num?)?.toDouble(),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'player_id': playerId,
        'map_name': mapName,
        'kd_ratio': kdRatio,
        'kr_ratio': krRatio,
        'adr': adr,
        'sniper_kill_rate_per_round': sniperKillRatePerRound,
        'sniper_kill_rate_per_match': sniperKillRatePerMatch,
        'total_sniper_kills': totalSniperKills,
        'v1_count': v1Count,
        'v2_count': v2Count,
        'match_1v1_win_rate': match1v1WinRate,
        'match_1v2_win_rate': match1v2WinRate,
        'total_1v1_wins': total1v1Wins,
        'total_1v2_wins': total1v2Wins,
        'utility_damage_success_rate': utilityDamageSuccessRate,
        'utility_damage_per_round': utilityDamagePerRound,
        'utility_damage': utilityDamage,
        'utility_usage_per_round': utilityUsagePerRound,
        'utility_success_rate': utilitySuccessRate,
        'total_utility_successes': totalUtilitySuccesses,
        'total_utility_count': totalUtilityCount,
        'enemies_flashed_per_round': enemiesFlashedPerRound,
        'flashes_per_round': flashesPerRound,
        'flash_success_rate': flashSuccessRate,
        'flash_successes': flashSuccesses,
        'flash_count': flashCount,
        'total_enemies_flashed': totalEnemiesFlashed,
        'entry_wins': entryWins,
        'match_entry_rate': matchEntryRate,
        'match_entry_success_rate': matchEntrySuccessRate,
        'entry_count': entryCount,
        'total_damage': totalDamage,
        'total_headshots_percentage': totalHeadshotsPercentage,
        'average_headshots_percentage': averageHeadshotsPercentage,
        'matches': matches,
        'wins': wins,
        'total_rounds': totalRounds,
        'win_rate_percentage': winRatePercentage,
        'total_kills': totalKills,
        'average_kills': averageKills,
        'average_deaths': averageDeaths,
        'average_assists': averageAssists,
        'headshots': headshots,
        'assists': assists,
        'deaths': deaths,
        'kills': kills,
        'rounds': rounds,
        'triple_kills': tripleKills,
        'quadro_kills': quadroKills,
        'penta_kills': pentaKills,
        'average_triple_kills': averageTripleKills,
        'average_quadro_kills': averageQuadroKills,
        'average_penta_kills': averagePentaKills,
        'mvps': mvps,
        'average_mvps': averageMvps,
        'headshots_per_match': headshotsPerMatch,
      };
}
