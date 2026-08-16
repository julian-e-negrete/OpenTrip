import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Local-first storage: every vehicle and trip lives in an on-device
/// SQLite database, keyed by the signed-in user's id, so recording trips
/// never depends on network. Syncing this to a backend (Supabase, per
/// /docs/ROADMAP.md) is the next slice — this file is deliberately the
/// only place that knows about the schema, so that sync logic can be
/// layered on without touching the repositories built on top of it.
class LocalDatabase {
  LocalDatabase._();
  static final instance = LocalDatabase._();

  Database? _db;

  Future<Database> get database async {
    final existing = _db;
    if (existing != null) return existing;
    final db = await _open();
    _db = db;
    return db;
  }

  Future<Database> _open() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'opentrip.db');
    return openDatabase(
      path,
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE vehicles (
            id TEXT PRIMARY KEY,
            user_id TEXT NOT NULL,
            name TEXT NOT NULL,
            type TEXT NOT NULL,
            ble_connector TEXT NOT NULL,
            created_at TEXT NOT NULL
          )
        ''');
        await db.execute('CREATE INDEX idx_vehicles_user ON vehicles(user_id)');

        await db.execute('''
          CREATE TABLE trips (
            id TEXT PRIMARY KEY,
            user_id TEXT NOT NULL,
            vehicle_id TEXT NOT NULL REFERENCES vehicles(id) ON DELETE CASCADE,
            started_at TEXT NOT NULL,
            ended_at TEXT,
            distance_meters REAL NOT NULL DEFAULT 0,
            duration_seconds INTEGER NOT NULL DEFAULT 0,
            avg_speed_kph REAL,
            max_speed_kph REAL,
            point_count INTEGER NOT NULL DEFAULT 0,
            ble_max_speed_kph REAL,
            ble_max_rpm INTEGER,
            ble_max_lean_deg REAL,
            ble_max_brake_kpa REAL,
            ble_min_water_temp_c INTEGER,
            ble_max_water_temp_c INTEGER
          )
        ''');
        await db.execute('CREATE INDEX idx_trips_vehicle ON trips(vehicle_id)');
        await db.execute('CREATE INDEX idx_trips_user ON trips(user_id)');

        await db.execute('''
          CREATE TABLE trip_points (
            trip_id TEXT NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
            seq INTEGER NOT NULL,
            latitude REAL NOT NULL,
            longitude REAL NOT NULL,
            altitude_meters REAL,
            speed_kph REAL,
            timestamp TEXT NOT NULL,
            PRIMARY KEY (trip_id, seq)
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          for (final column in [
            'ble_max_speed_kph REAL',
            'ble_max_rpm INTEGER',
            'ble_max_lean_deg REAL',
            'ble_max_brake_kpa REAL',
            'ble_min_water_temp_c INTEGER',
            'ble_max_water_temp_c INTEGER',
          ]) {
            await db.execute('ALTER TABLE trips ADD COLUMN $column');
          }
        }
      },
    );
  }
}
