class PlayerStats {
  final String playerId;
  // Core
  final double? kdRatio;
  final double? krRatio;
  final double? adr;
  // Sniper
  final double? sniperKillRatePerRound;
  final double? sniperKillRatePerMatch;
  final int? totalSniperKills;
  // 1vX
  final int? v1Count;
  final int? v2Count;
  final double? match1v1WinRate;
  final double? match1v2WinRate;
  final int? total1v1Wins;
  final int? total1v2Wins;
  // Utility
  final double? utilityDamageSuccessRate;
  final double? utilityDamagePerRound;
  final int? utilityDamage;
  final double? utilityUsagePerRound;
  final double? utilitySuccessRate;
  final int? totalUtilitySuccesses;
  final int? totalUtilityCount;
  // Flash
  final double? enemiesFlashedPerRound;
  final double? flashesPerRound;
  final double? flashSuccessRate;
  final int? flashSuccesses;
  final int? flashCount;
  final int? totalEnemiesFlashed;
  // Entry
  final int? entryWins;
  final double? matchEntryRate;
  final double? matchEntrySuccessRate;
  final int? entryCount;
  // Matches summary
  final int? currentWinStreak;
  final int? totalDamage;
  final int? totalHeadshotsPercentage;
  final double? averageHeadshotsPercentage;
  final int? matches;
  final int? wins;
  final int? totalRounds;
  final int? winRatePercentage;
  final int? totalMatches;
  final int? longestWinStreak;
  final int? totalKills;

  PlayerStats({
    required this.playerId,
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
    this.currentWinStreak,
    this.totalDamage,
    this.totalHeadshotsPercentage,
    this.averageHeadshotsPercentage,
    this.matches,
    this.wins,
    this.totalRounds,
    this.winRatePercentage,
    this.totalMatches,
    this.longestWinStreak,
    this.totalKills,
  });

  factory PlayerStats.fromMap(Map<String, dynamic> m) => PlayerStats(
        playerId: m['player_id'] as String,
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
        currentWinStreak: m['current_win_streak'] as int?,
        totalDamage: m['total_damage'] as int?,
        totalHeadshotsPercentage: m['total_headshots_percentage'] as int?,
        averageHeadshotsPercentage:
            (m['average_headshots_percentage'] as num?)?.toDouble(),
        matches: m['matches'] as int?,
        wins: m['wins'] as int?,
        totalRounds: m['total_rounds'] as int?,
        winRatePercentage: m['win_rate_percentage'] as int?,
        totalMatches: m['total_matches'] as int?,
        longestWinStreak: m['longest_win_streak'] as int?,
        totalKills: m['total_kills'] as int?,
      );

  Map<String, dynamic> toMap() => {
        'player_id': playerId,
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
        'current_win_streak': currentWinStreak,
        'total_damage': totalDamage,
        'total_headshots_percentage': totalHeadshotsPercentage,
        'average_headshots_percentage': averageHeadshotsPercentage,
        'matches': matches,
        'wins': wins,
        'total_rounds': totalRounds,
        'win_rate_percentage': winRatePercentage,
        'total_matches': totalMatches,
        'longest_win_streak': longestWinStreak,
        'total_kills': totalKills,
      };
}
