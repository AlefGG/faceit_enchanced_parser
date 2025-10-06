class MatchRecord {
  final String matchId;
  final String? gameMode; // expect '5v5'
  final String? map;
  final String? region;
  final int? date; // epoch seconds
  final int? finishedAt; // epoch seconds
  final int? scoreFaction1;
  final int? scoreFaction2;
  final String? competitionType; // matchmaking | championship | etc

  MatchRecord({
    required this.matchId,
    this.gameMode,
    this.map,
    this.region,
    this.date,
    this.finishedAt,
    this.scoreFaction1,
    this.scoreFaction2,
    this.competitionType,
  });

  factory MatchRecord.fromMap(Map<String, dynamic> map) => MatchRecord(
        matchId: map['match_id'] as String,
        gameMode: map['game_mode'] as String?,
        map: map['map'] as String?,
        region: map['region'] as String?,
        date: map['date'] as int?,
        finishedAt: map['finished_at'] as int?,
        scoreFaction1: map['score_faction1'] as int?,
        scoreFaction2: map['score_faction2'] as int?,
        competitionType: map['competition_type'] as String?,
      );

  Map<String, dynamic> toMap() => {
        'match_id': matchId,
        'game_mode': gameMode,
        'map': map,
        'region': region,
        'date': date,
        'finished_at': finishedAt,
        'score_faction1': scoreFaction1,
        'score_faction2': scoreFaction2,
        'competition_type': competitionType,
      };
}
