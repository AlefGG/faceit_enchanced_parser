class Player {
  final String playerId;
  final String? nickname;
  final String? country;
  final int? skillLevel;
  final int? faceitElo;
  final bool processed;
  final String source; // 'top' | 'discovered'
  final int? rankOrder;

  Player({
    required this.playerId,
    this.nickname,
    this.country,
    this.skillLevel,
    this.faceitElo,
    required this.processed,
    required this.source,
    this.rankOrder,
  });

  factory Player.fromMap(Map<String, dynamic> map) => Player(
        playerId: map['player_id'] as String,
        nickname: map['nickname'] as String?,
        country: map['country'] as String?,
        skillLevel: map['skill_level'] as int?,
        faceitElo: map['faceit_elo'] as int?,
        processed: (map['processed'] ?? 0) == 1,
        source: map['source'] as String? ?? 'top',
        rankOrder: map['rank_order'] as int?,
      );

  Map<String, dynamic> toMap() => {
        'player_id': playerId,
        'nickname': nickname,
        'country': country,
        'skill_level': skillLevel,
        'faceit_elo': faceitElo,
        'processed': processed ? 1 : 0,
        'source': source,
        'rank_order': rankOrder,
      };
}
