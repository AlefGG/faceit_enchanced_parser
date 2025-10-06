class RecentMatchStat {
  final String matchId;
  final String playerId;
  final int? kills;
  final int? deaths;
  final int? assists;
  final double? adr;
  final double? krRatio;
  final double? kdRatio;
  final int? headshots;
  final double? headshotsPercentage;
  final int? mvps;
  final int? entryCount;
  final int? entryWins;
  final int? clutchKills;
  final int? sniperKills;
  final int? flashCount;
  final int? flashSuccesses;
  final int? utilityDamage;
  final double? utilityUsagePerRound;
  final double? utilityDamagePerRound;
  final int? enemiesFlashed;
  final String? createdAt;

  RecentMatchStat({
    required this.matchId,
    required this.playerId,
    this.kills,
    this.deaths,
    this.assists,
    this.adr,
    this.krRatio,
    this.kdRatio,
    this.headshots,
    this.headshotsPercentage,
    this.mvps,
    this.entryCount,
    this.entryWins,
    this.clutchKills,
    this.sniperKills,
    this.flashCount,
    this.flashSuccesses,
    this.utilityDamage,
    this.utilityUsagePerRound,
    this.utilityDamagePerRound,
    this.enemiesFlashed,
    this.createdAt,
  });

  factory RecentMatchStat.fromMap(Map<String, dynamic> map) => RecentMatchStat(
        matchId: map['match_id'] as String,
        playerId: map['player_id'] as String,
        kills: map['kills'] as int?,
        deaths: map['deaths'] as int?,
        assists: map['assists'] as int?,
        adr: (map['adr'] as num?)?.toDouble(),
        krRatio: (map['kr_ratio'] as num?)?.toDouble(),
        kdRatio: (map['kd_ratio'] as num?)?.toDouble(),
        headshots: map['headshots'] as int?,
        headshotsPercentage: (map['headshots_percentage'] as num?)?.toDouble(),
        mvps: map['mvps'] as int?,
        entryCount: map['entry_count'] as int?,
        entryWins: map['entry_wins'] as int?,
        clutchKills: map['clutch_kills'] as int?,
        sniperKills: map['sniper_kills'] as int?,
        flashCount: map['flash_count'] as int?,
        flashSuccesses: map['flash_successes'] as int?,
        utilityDamage: map['utility_damage'] as int?,
        utilityUsagePerRound:
            (map['utility_usage_per_round'] as num?)?.toDouble(),
        utilityDamagePerRound:
            (map['utility_damage_per_round'] as num?)?.toDouble(),
        enemiesFlashed: map['enemies_flashed'] as int?,
        createdAt: map['created_at'] as String?,
      );

  Map<String, dynamic> toMap() => {
        'match_id': matchId,
        'player_id': playerId,
        'kills': kills,
        'deaths': deaths,
        'assists': assists,
        'adr': adr,
        'kr_ratio': krRatio,
        'kd_ratio': kdRatio,
        'headshots': headshots,
        'headshots_percentage': headshotsPercentage,
        'mvps': mvps,
        'entry_count': entryCount,
        'entry_wins': entryWins,
        'clutch_kills': clutchKills,
        'sniper_kills': sniperKills,
        'flash_count': flashCount,
        'flash_successes': flashSuccesses,
        'utility_damage': utilityDamage,
        'utility_usage_per_round': utilityUsagePerRound,
        'utility_damage_per_round': utilityDamagePerRound,
        'enemies_flashed': enemiesFlashed,
        'created_at': createdAt,
      };
}
