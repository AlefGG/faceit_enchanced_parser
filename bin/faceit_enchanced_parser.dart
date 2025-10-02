import 'dart:async';
import 'dart:io';
import 'package:dotenv/dotenv.dart';
import 'package:logger/logger.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart';
import 'dart:convert';
import 'package:args/args.dart';
import 'export_complete_data_json.dart';
import 'reliable_http_get.dart';
import 'create_db.dart';

part 'collect_data.dart';

// Глобальные переменные
String outputPrefix = 'faceit';
String dateTimeStamp = ''; // Будет заполняться при запуске
int startPlayerIndex = 0; // По умолчанию начинаем с начала
int endPlayerIndex = 5; // По умолчанию обрабатываем 1000 игроков
late Database db;
late Logger logger;
late String apiKey;
int PLAYER_LIMIT = 5; // Начнем с 1000 игроков
final int MATCHES_PER_PLAYER = 300;
final int REQUEST_DELAY = 150; // мс
final int DB_REQUEST_DELAY = 0; // мс

// Функция для сохранения прогресса
Future<void> saveProgress(int processedIndex) async {
  final progressFile = File('progress.txt');
  await progressFile.writeAsString('$processedIndex');
  logger.i('Progress saved: processed up to player $processedIndex');
}

// Функция для чтения сохраненного прогресса
Future<int> loadProgress() async {
  final progressFile = File('progress.txt');
  if (await progressFile.exists()) {
    final content = await progressFile.readAsString();
    try {
      return int.parse(content.trim());
    } catch (e) {
      // Логгер может быть не инициализирован на этом этапе
      stderr.writeln('Invalid progress file content: $content');
      return 0;
    }
  }
  return 0;
}

void main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('start',
        abbr: 's', help: 'Starting player index (0-based)', defaultsTo: '0')
    ..addOption('end',
        abbr: 'e', help: 'Ending player index (exclusive)', defaultsTo: '1000')
    ..addOption('prefix',
        abbr: 'p', help: 'Output files prefix', defaultsTo: 'faceit')
    ..addFlag('continue',
        abbr: 'c', help: 'Continue from last saved progress', negatable: false)
    ..addFlag('timestamp',
        abbr: 't', help: 'Add timestamp to output files', defaultsTo: true)
    ..addFlag('help',
        abbr: 'h', help: 'Show this help message', negatable: false);

  // Парсим аргументы
  try {
    final results = parser.parse(arguments);

    // Если запрошена помощь, показываем и выходим
    if (results['help']) {
      print('FaceIT CS2 Data Collector\n');
      print('Usage: dart bin/faceit_enchanced_parser.dart [options]\n');
      print(parser.usage);
      exit(0);
    }

    if (results['continue']) {
      startPlayerIndex = await loadProgress();
      // Логгер еще не инициализирован
      stdout.writeln(
          'Continuing from previously saved progress: starting at player $startPlayerIndex');
    }

    if (results.wasParsed('prefix')) {
      outputPrefix = results['prefix'];
    }

    // Добавляем временную метку, если требуется
    if (results['timestamp']) {
      final now = DateTime.now();
      dateTimeStamp =
          '_${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}-${now.minute.toString().padLeft(2, '0')}';
    }

    // Получаем параметры диапазона
    // startPlayerIndex = int.parse(results['start']);
    // endPlayerIndex = int.parse(results['end']);
    startPlayerIndex = 0;
    endPlayerIndex = 1;
    // Проверка валидности диапазона
    if (startPlayerIndex < 0 || endPlayerIndex <= startPlayerIndex) {
      throw ArgumentError(
          'Invalid range: start must be >= 0 and end must be > start');
    }

    // Корректируем PLAYER_LIMIT на основе диапазона
    PLAYER_LIMIT = endPlayerIndex - startPlayerIndex;
  } catch (e) {
    print('Error parsing arguments: $e\n');
    print('Usage: dart bin/faceit_enchanced_parser.dart [options]\n');
    print(parser.usage);
    exit(1);
  }

  // Инициализация
  logger = Logger();
  logger.i(
      'Starting FACEIT CS2 data collection (players $startPlayerIndex-$endPlayerIndex)');

  // Загрузка переменных окружения
  var env = DotEnv()..load(['.env.faceit']);
  apiKey = env['FACEIT_API_KEY'] ?? '';

  if (apiKey.isEmpty) {
    logger.e(
        'FACEIT API key not found. Please set FACEIT_API_KEY in .env.faceit file');
    exit(1);
  }

  // Инициализация SQLite для Windows
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  try {
    // Открываем или создаем базу данных
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'faceit_stats.db');
    logger.i('Opening database at $path');
    db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await createDb(db, version);
      },
      onOpen: (db) async {
        // Гарантируем схему даже для существующих БД
        await createDb(db, 1);
      },
    );

    // Включаем поддержку внешних ключей
    await db.execute('PRAGMA foreign_keys = ON');

    logger.i('Database initialized at $path');

    // Создаем имена файлов с учетом префикса, временной метки и диапазона игроков
    final rangeStamp = '_${startPlayerIndex}_$endPlayerIndex';

    final completeDataFile =
        '${outputPrefix}_complete_data$dateTimeStamp$rangeStamp.json';

    // Основной процесс сбора данных
    await collectData();
    // Бэкфилл профилей тиммейтов из снимков ростеров (без дополнительных запросов)
    await backfillProfilesFromRosters();
    // Вызываем функции экспорта с новыми именами файлов
    await exportCompleteDataToJson(completeDataFile, logger, db);
    // Закрываем базу данных
    await db.close();
    logger.i('Data collection completed');
  } catch (e, stackTrace) {
    logger.e('Fatal error during execution', error: e, stackTrace: stackTrace);
    exit(1);
  }
}
