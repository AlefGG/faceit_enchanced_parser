import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'schema.dart';

class AppDatabase {
  static Database? _instance;

  static Future<Database> open({String fileName = 'faceit_stats.db'}) async {
    if (_instance != null) return _instance!;
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, fileName);
    final db = await openDatabase(path, version: 1, onCreate: (db, v) async {
      await createOrMigrate(db);
    }, onOpen: (db) async {
      await createOrMigrate(db);
    });
    await db.execute('PRAGMA foreign_keys = ON');
    _instance = db;
    return db;
  }
}
