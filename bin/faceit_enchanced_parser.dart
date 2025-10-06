import 'dart:io';
import 'package:args/args.dart';
import 'package:dotenv/dotenv.dart';
import 'package:logger/logger.dart';

// New modular architecture imports
import 'package:faceit_ecnhanced_parser/db/database.dart';
import 'package:faceit_ecnhanced_parser/utils/http_client.dart';
import 'package:faceit_ecnhanced_parser/services/faceit_api.dart';
import 'package:faceit_ecnhanced_parser/orchestration/pipeline.dart';

/// Minimal CLI entrypoint delegating to the new Pipeline orchestration.
/// Legacy monolithic logic has been replaced (see lib/orchestration/pipeline.dart).
Future<void> main(List<String> args) async {
  final logger = Logger();
  final parser = ArgParser()
    ..addOption('start',
        abbr: 's', defaultsTo: '0', help: 'Start player index (inclusive)')
    ..addOption('end',
        abbr: 'e', defaultsTo: '78', help: 'End player index (exclusive)')
    ..addOption('db',
        defaultsTo: 'faceit_stats.db', help: 'SQLite database file name')
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show help');

  late int start;
  late int end;
  late String dbFile;

  try {
    final r = parser.parse(args);
    if (r['help'] as bool) {
      stdout.writeln('FACEIT CS2 Collector (modular pipeline)');
      stdout.writeln(
          'Usage: dart run bin/faceit_enchanced_parser.dart [options]\n');
      stdout.writeln(parser.usage);
      return;
    }
    start = int.parse(r['start'] as String);
    end = int.parse(r['end'] as String);
    dbFile = r['db'] as String;
  } catch (e) {
    stderr.writeln('Argument parsing failed: $e');
    stderr.writeln(parser.usage);
    exit(64); // EX_USAGE
  }

  if (start < 0 || end <= start) {
    stderr.writeln('Invalid range: ensure 0 <= start < end');
    exit(64);
  }

  // Load env (.env.faceit) for API key
  final env = DotEnv()..load(['.env.faceit']);
  final apiKey = env['FACEIT_API_KEY'] ?? '';
  if (apiKey.isEmpty) {
    stderr.writeln('FACEIT_API_KEY missing in .env.faceit');
    exit(1);
  }

  logger.i('Starting pipeline for players range [$start, $end)');

  try {
    final db = await AppDatabase.open(fileName: dbFile);
    final http = HttpClientWrapper(logger: logger, defaultHeaders: {
      'Authorization': 'Bearer $apiKey',
      'Accept': 'application/json'
    });
    final api = FaceitApi(http: http, logger: logger);
    final pipeline = Pipeline(db: db, logger: logger, api: api);
    await pipeline.run(start, end);
    await db.close();
    logger.i('Pipeline finished successfully');
  } catch (e, st) {
    logger.e('Fatal pipeline error', error: e, stackTrace: st);
    exit(1);
  }
}
