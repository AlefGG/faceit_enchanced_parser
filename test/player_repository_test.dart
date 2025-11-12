import 'package:test/test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:faceit_ecnhanced_parser/db/database.dart';
import 'package:faceit_ecnhanced_parser/repositories/player_repository.dart';

void main() {
  sqfliteFfiInit();

  group('PlayerRepository.fetchUnprocessedTopSlice', () {
    late Database db;
    late PlayerRepository repo;

    setUp(() async {
      db = await AppDatabase.open(inMemory: true);
      repo = PlayerRepository(db);
      for (var i = 0; i < 100; i++) {
        await db.insert('players', {
          'player_id': 'player_$i',
          'source': 'top',
          'rank_order': i,
          'processed': i < 20 ? 1 : 0,
        });
      }
    });

    tearDown(() async {
      await db.close();
    });

    test('returns unprocessed players within requested rank window', () async {
      final rows = await repo.fetchUnprocessedTopSlice(20, 40);
      expect(rows.length, 20);
      expect(rows.first['player_id'], 'player_20');
      expect(rows.last['player_id'], 'player_39');
    });

    test('skips already processed players but keeps remaining ranks', () async {
      await db.update('players', {'processed': 1},
          where: 'player_id = ?', whereArgs: ['player_25']);
      final rows = await repo.fetchUnprocessedTopSlice(20, 30);
      expect(rows.length, 9);
      expect(rows.any((r) => r['player_id'] == 'player_25'), isFalse);
      expect(rows.first['player_id'], 'player_20');
      expect(rows.last['player_id'], 'player_29');
    });
  });
}
