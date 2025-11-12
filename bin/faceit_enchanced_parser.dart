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
        abbr: 'e', defaultsTo: '100', help: 'End player index (exclusive)')
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

  // Load env (.env.faceit) for API key(s)
  final env = DotEnv()..load(['.env.faceit']);
  final tokens = _collectFaceitTokens(env);
  if (tokens.isEmpty) {
    stderr.writeln('No FACEIT_API_KEY* entries found in .env.faceit');
    exit(1);
  }
  logger.i('Loaded ${tokens.length} FACEIT API token(s)');

  logger.i('Starting pipeline for players range [$start, $end)');

  try {
    final db = await AppDatabase.open(fileName: dbFile);
    final http = HttpClientWrapper(
        logger: logger,
        defaultHeaders: {'Accept': 'application/json'},
        bearerTokens: tokens);
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

List<String> _collectFaceitTokens(DotEnv env) {
  final entries = <MapEntry<String, String>>[];

  final envFile = File('.env.faceit');
  if (envFile.existsSync()) {
    for (final rawLine in envFile.readAsLinesSync()) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final idx = line.indexOf('=');
      if (idx <= 0) continue;
      final key = line.substring(0, idx).trim();
      final value = line.substring(idx + 1).trim();
      if (key.toUpperCase().startsWith('FACEIT_API_KEY') && value.isNotEmpty) {
        entries.add(MapEntry(key, value));
      }
    }
  }

  // Also include values already loaded into the DotEnv instance (covers runtime overrides)
  const fallbackKeys = [
    'FACEIT_API_KEY',
    'FACEIT_API_KEY_ONE',
    'FACEIT_API_KEY_TWO',
    'FACEIT_API_KEY_THREE',
    'FACEIT_API_KEY_FOUR',
    'FACEIT_API_KEY_FIVE',
  ];
  for (final key in fallbackKeys) {
    final value = env[key];
    if (value != null && value.trim().isNotEmpty) {
      entries.add(MapEntry(key, value.trim()));
    }
  }

  entries.sort((a, b) => a.key.compareTo(b.key));
  final seen = <String>{};
  final tokens = <String>[];
  for (final entry in entries) {
    if (seen.add(entry.value)) {
      tokens.add(entry.value);
    }
  }
  return tokens;
}
