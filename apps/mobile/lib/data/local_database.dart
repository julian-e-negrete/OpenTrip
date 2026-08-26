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
      version: 13,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE vehicles (
            id TEXT PRIMARY KEY,
            user_id TEXT NOT NULL,
            name TEXT NOT NULL,
            type TEXT NOT NULL,
            brand TEXT NOT NULL DEFAULT '',
            model TEXT NOT NULL DEFAULT '',
            ble_connector TEXT NOT NULL,
            photo_path TEXT,
            created_at TEXT NOT NULL,
            starting_odometer_km REAL,
            service_interval_km REAL,
            last_service_odometer_km REAL,
            synced INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await db.execute('CREATE INDEX idx_vehicles_user ON vehicles(user_id)');

        await db.execute('''
          CREATE TABLE profiles (
            user_id TEXT PRIMARY KEY,
            display_name TEXT NOT NULL,
            avatar_path TEXT,
            country_code TEXT,
            leaderboard_visible INTEGER NOT NULL DEFAULT 1,
            synced INTEGER NOT NULL DEFAULT 0
          )
        ''');

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
            ble_max_water_temp_c INTEGER,
            behavior_max_accel_g REAL,
            behavior_max_brake_g REAL,
            behavior_max_cornering_g REAL,
            behavior_hard_accel_count INTEGER,
            behavior_hard_brake_count INTEGER,
            behavior_hard_cornering_count INTEGER,
            -- No longer written by the app (auto-start drive detection
            -- was removed) — column stays for anyone upgrading from a
            -- build that had it, rather than a destructive migration for
            -- a harmless, always-0 leftover.
            auto_started INTEGER NOT NULL DEFAULT 0,
            phone_lean_max_deg REAL,
            ble_odometer_km REAL,
            synced INTEGER NOT NULL DEFAULT 0
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
            ble_speed_kph REAL,
            ble_rpm INTEGER,
            ble_gear INTEGER,
            ble_throttle_percent REAL,
            ble_lean_deg REAL,
            ble_water_temp_c INTEGER,
            PRIMARY KEY (trip_id, seq)
          )
        ''');

        await db.execute('''
          CREATE TABLE territory_cells (
            user_id TEXT NOT NULL,
            cell_key TEXT NOT NULL,
            first_seen_at TEXT NOT NULL,
            visit_count INTEGER NOT NULL DEFAULT 1,
            synced INTEGER NOT NULL DEFAULT 0,
            PRIMARY KEY (user_id, cell_key)
          )
        ''');

        await db.execute('''
          CREATE TABLE trophies (
            user_id TEXT NOT NULL,
            trophy_key TEXT NOT NULL,
            earned_at TEXT NOT NULL,
            synced INTEGER NOT NULL DEFAULT 0,
            PRIMARY KEY (user_id, trophy_key)
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
        if (oldVersion < 3) {
          await db.execute("ALTER TABLE vehicles ADD COLUMN brand TEXT NOT NULL DEFAULT ''");
          await db.execute("ALTER TABLE vehicles ADD COLUMN model TEXT NOT NULL DEFAULT ''");
          await db.execute('ALTER TABLE vehicles ADD COLUMN photo_path TEXT');
          await db.execute('''
            CREATE TABLE IF NOT EXISTS profiles (
              user_id TEXT PRIMARY KEY,
              display_name TEXT NOT NULL,
              avatar_path TEXT
            )
          ''');
        }
        if (oldVersion < 4) {
          await db.execute('ALTER TABLE vehicles ADD COLUMN synced INTEGER NOT NULL DEFAULT 0');
          await db.execute('ALTER TABLE trips ADD COLUMN synced INTEGER NOT NULL DEFAULT 0');
          // profiles may not exist yet if jumping straight from version 2.
          await db.execute('''
            CREATE TABLE IF NOT EXISTS profiles (
              user_id TEXT PRIMARY KEY,
              display_name TEXT NOT NULL,
              avatar_path TEXT,
              synced INTEGER NOT NULL DEFAULT 0
            )
          ''');
          final columns = await db.rawQuery('PRAGMA table_info(profiles)');
          final hasSynced = columns.any((c) => c['name'] == 'synced');
          if (!hasSynced) {
            await db.execute('ALTER TABLE profiles ADD COLUMN synced INTEGER NOT NULL DEFAULT 0');
          }
        }
        if (oldVersion < 5) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS territory_cells (
              user_id TEXT NOT NULL,
              cell_key TEXT NOT NULL,
              first_seen_at TEXT NOT NULL,
              synced INTEGER NOT NULL DEFAULT 0,
              PRIMARY KEY (user_id, cell_key)
            )
          ''');
          await db.execute('''
            CREATE TABLE IF NOT EXISTS trophies (
              user_id TEXT NOT NULL,
              trophy_key TEXT NOT NULL,
              earned_at TEXT NOT NULL,
              synced INTEGER NOT NULL DEFAULT 0,
              PRIMARY KEY (user_id, trophy_key)
            )
          ''');
        }
        if (oldVersion < 6) {
          final columns = await db.rawQuery('PRAGMA table_info(profiles)');
          final hasCountry = columns.any((c) => c['name'] == 'country_code');
          if (!hasCountry) {
            await db.execute('ALTER TABLE profiles ADD COLUMN country_code TEXT');
          }
        }
        if (oldVersion < 7) {
          final columns = await db.rawQuery('PRAGMA table_info(profiles)');
          final hasVisible = columns.any((c) => c['name'] == 'leaderboard_visible');
          if (!hasVisible) {
            await db.execute('ALTER TABLE profiles ADD COLUMN leaderboard_visible INTEGER NOT NULL DEFAULT 1');
          }
        }
        if (oldVersion < 8) {
          final columns = await db.rawQuery('PRAGMA table_info(trips)');
          final hasAutoStarted = columns.any((c) => c['name'] == 'auto_started');
          if (!hasAutoStarted) {
            await db.execute('ALTER TABLE trips ADD COLUMN auto_started INTEGER NOT NULL DEFAULT 0');
          }
        }
        if (oldVersion < 9) {
          final columns = await db.rawQuery('PRAGMA table_info(trips)');
          final existing = columns.map((c) => c['name']).toSet();
          for (final column in [
            'behavior_max_accel_g REAL',
            'behavior_max_brake_g REAL',
            'behavior_max_cornering_g REAL',
            'behavior_hard_accel_count INTEGER',
            'behavior_hard_brake_count INTEGER',
            'behavior_hard_cornering_count INTEGER',
          ]) {
            final name = column.split(' ').first;
            if (!existing.contains(name)) {
              await db.execute('ALTER TABLE trips ADD COLUMN $column');
            }
          }
        }
        if (oldVersion < 10) {
          final columns = await db.rawQuery('PRAGMA table_info(trips)');
          final hasLean = columns.any((c) => c['name'] == 'phone_lean_max_deg');
          if (!hasLean) {
            await db.execute('ALTER TABLE trips ADD COLUMN phone_lean_max_deg REAL');
          }
        }
        if (oldVersion < 11) {
          final columns = await db.rawQuery('PRAGMA table_info(territory_cells)');
          final hasVisitCount = columns.any((c) => c['name'] == 'visit_count');
          if (!hasVisitCount) {
            await db.execute('ALTER TABLE territory_cells ADD COLUMN visit_count INTEGER NOT NULL DEFAULT 1');
          }
        }
        if (oldVersion < 12) {
          // gamification/territory.dart switched its cell_key encoding from
          // a square lat/lng grid ("latCell:lngCell") to hexagonal axial
          // coordinates ("q:r") — same two-integers-separated-by-a-colon
          // shape, completely different meaning. A pre-existing row's key
          // would silently get reinterpreted as a hex coordinate and drawn
          // in the wrong place, so unlike every other migration in this
          // file, this one can't be additive. Clearing local claims here;
          // they refill the next time each cell is ridden through again.
          await db.delete('territory_cells');
        }
        if (oldVersion < 13) {
          final vehicleColumns = await db.rawQuery('PRAGMA table_info(vehicles)');
          final vehicleExisting = vehicleColumns.map((c) => c['name']).toSet();
          for (final column in [
            'starting_odometer_km REAL',
            'service_interval_km REAL',
            'last_service_odometer_km REAL',
          ]) {
            final name = column.split(' ').first;
            if (!vehicleExisting.contains(name)) {
              await db.execute('ALTER TABLE vehicles ADD COLUMN $column');
            }
          }

          final tripColumns = await db.rawQuery('PRAGMA table_info(trips)');
          final hasOdometer = tripColumns.any((c) => c['name'] == 'ble_odometer_km');
          if (!hasOdometer) {
            await db.execute('ALTER TABLE trips ADD COLUMN ble_odometer_km REAL');
          }

          final pointColumns = await db.rawQuery('PRAGMA table_info(trip_points)');
          final pointExisting = pointColumns.map((c) => c['name']).toSet();
          for (final column in [
            'ble_speed_kph REAL',
            'ble_rpm INTEGER',
            'ble_gear INTEGER',
            'ble_throttle_percent REAL',
            'ble_lean_deg REAL',
            'ble_water_temp_c INTEGER',
          ]) {
            final name = column.split(' ').first;
            if (!pointExisting.contains(name)) {
              await db.execute('ALTER TABLE trip_points ADD COLUMN $column');
            }
          }
        }
      },
    );
  }
}
