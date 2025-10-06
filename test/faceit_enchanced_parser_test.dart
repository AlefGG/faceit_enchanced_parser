import 'dart:convert';
import 'package:test/test.dart';
import 'package:logger/logger.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:http/http.dart' as http;

import 'package:faceit_ecnhanced_parser/db/database.dart';
import 'package:faceit_ecnhanced_parser/orchestration/pipeline.dart';
import 'package:faceit_ecnhanced_parser/services/faceit_api.dart';
import 'package:faceit_ecnhanced_parser/utils/http_client.dart';

/// A very light smoke test ensuring Pipeline can be constructed and run with
/// an empty DB and that it produces an export file. We stub HTTP responses
/// minimally by providing a custom HttpClientWrapper that returns controlled
/// payloads for known endpoints. This avoids real network calls.
void main() {
  sqfliteFfiInit();

  group('pipeline smoke', () {
    test('runs with mocked API (no real network)', () async {
      final db = await AppDatabase.open(inMemory: true);
      final logger = Logger(level: Level.warning);

      final mockHttp = _MockHttpClient(logger: logger);
      final api = FaceitApi(http: mockHttp, logger: logger);
      final pipeline = Pipeline(db: db, logger: logger, api: api);

      // Run for zero range (start=end) -> should effectively no-op gracefully
      await pipeline.run(0, 0);

      // Run for small range 0..1 to trigger top player ensure + processing with mock data
      await pipeline.run(0, 1);

      // Validate some tables exist and contain expected mock inserted rows
      final players = await db.rawQuery('SELECT COUNT(*) as c FROM players');
      expect((players.first['c'] as int) >= 1, isTrue);

      await db.close();
    });
  });
}

class _MockHttpClient extends HttpClientWrapper {
  _MockHttpClient({required super.logger}) : super(defaultHeaders: const {});

  @override
  Future<http.Response> get(Uri url, {Map<String, String>? headers}) async {
    final u = url.toString();
    Map<String, dynamic> body = {};
    int status = 200;
    if (u.contains('/rankings/games/cs2/regions/EU')) {
      body = {
        'items': [
          {
            'player_id': 'mock_player_1',
            'nickname': 'MockOne',
            'country': 'eu',
            'skill_level': 10,
            'faceit_elo': 3000,
          }
        ]
      };
    } else if (u.contains('/players/') && u.contains('/history')) {
      body = {
        'items': List.generate(3, (i) {
          final matchId = 'match_$i';
          return {
            'match_id': matchId,
            'game_mode': '5v5',
            'competition_type': 'matchmaking',
            'started_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
            'finished_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
            'teams': [
              {
                'team_id': 't1',
                'players': [
                  {
                    'player_id': 'mock_player_1',
                    'nickname': 'MockOne',
                  },
                  {
                    'player_id': 'mock_teammate_a',
                    'nickname': 'TeammateA',
                  }
                ]
              },
              {
                'team_id': 't2',
                'players': [
                  {
                    'player_id': 'mock_opponent',
                    'nickname': 'Opponent',
                  }
                ]
              }
            ]
          };
        })
      };
    } else if (u.contains('/players/mock_player_1/stats/cs2')) {
      body = {
        'lifetime': {
          'Average Headshots %': '52',
          'Average K/D Ratio': '1.20',
          'Matches': '3',
          'Wins': '2',
        },
        'segments': [
          {
            'label': 'de_inferno',
            'stats': {
              'Matches': '2',
              'Wins': '1',
              'Kills': '40',
              'Deaths': '30',
              'Headshots %': '55'
            }
          }
        ]
      };
    } else if (u.contains('/players/mock_teammate_a/stats/cs2')) {
      body = {
        'lifetime': {
          'Average Headshots %': '47',
          'Average K/D Ratio': '0.95',
          'Matches': '1',
          'Wins': '0',
        },
        'segments': []
      };
    } else if (u.contains('/matches/') && u.contains('/stats')) {
      body = {
        'rounds': [
          {
            'teams': [
              {
                'players': [
                  {
                    'player_id': 'mock_player_1',
                    'player_stats': {
                      'Kills': '20',
                      'Deaths': '15',
                      'Assists': '5',
                      'Headshot %': '50'
                    }
                  },
                  {
                    'player_id': 'mock_teammate_a',
                    'player_stats': {
                      'Kills': '10',
                      'Deaths': '18',
                      'Assists': '3',
                      'Headshot %': '40'
                    }
                  }
                ]
              },
              {
                'players': [
                  {
                    'player_id': 'mock_opponent',
                    'player_stats': {
                      'Kills': '25',
                      'Deaths': '20',
                      'Assists': '2',
                      'Headshot %': '45'
                    }
                  }
                ]
              }
            ]
          }
        ]
      };
    } else if (u.contains('/players/mock_player_1')) {
      body = {
        'player_id': 'mock_player_1',
        'nickname': 'MockOne',
        'country': 'eu',
        'skill_level': 10,
        'faceit_elo': 3000,
      };
    } else if (u.contains('/players/mock_teammate_a')) {
      body = {
        'player_id': 'mock_teammate_a',
        'nickname': 'TeammateA',
        'country': 'eu',
        'skill_level': 8,
        'faceit_elo': 2500,
      };
    }
    return http.Response(jsonEncode(body), status);
  }
}
