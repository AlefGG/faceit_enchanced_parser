import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'schema.dart';

class AppDatabase {
  static Database? _instance;

  /// Open the application database. If [inMemory] is true an in-memory
  /// database is created (used for tests). For file-based DB we memoize the
  /// instance to avoid reopening; for in-memory we always create a fresh one.
  static Future<Database> open(
      {String fileName = 'faceit_stats.db', bool inMemory = false}) async {
    if (!inMemory && _instance != null) return _instance!;
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final path = inMemory
        ? inMemoryDatabasePath
        : join(await getDatabasesPath(), fileName);
    final db = await openDatabase(path, version: 1, onCreate: (db, v) async {
      await createOrMigrate(db);
    }, onOpen: (db) async {
      await createOrMigrate(db);
    });
    await db.execute('PRAGMA foreign_keys = ON');
    if (!inMemory) {
      _instance = db;
    }
    return db;
  }
}
