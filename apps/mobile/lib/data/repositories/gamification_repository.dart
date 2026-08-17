import 'package:sqflite/sqflite.dart';

import '../data_events.dart';
import '../local_database.dart';

class GamificationRepository {
  GamificationRepository._();
  static final instance = GamificationRepository._();

  Future<int> territoryCellCount(String userId) async {
    final db = await LocalDatabase.instance.database;
    final result = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM territory_cells WHERE user_id = ?', [userId]),
    );
    return result ?? 0;
  }

  /// Inserts any cell keys not already recorded for this user. Duplicate
  /// cells (revisiting the same area) are silently ignored via the
  /// (user_id, cell_key) primary key — that's the whole point, "how much
  /// *new* ground" only counts a cell once.
  Future<void> addTerritoryCells(String userId, Set<String> cellKeys) async {
    if (cellKeys.isEmpty) return;
    final db = await LocalDatabase.instance.database;
    final now = DateTime.now().toIso8601String();
    final batch = db.batch();
    for (final cellKey in cellKeys) {
      batch.insert('territory_cells', {
        'user_id': userId,
        'cell_key': cellKey,
        'first_seen_at': now,
        'synced': 0,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await batch.commit(noResult: true);
    DataEvents.instance.notifyChanged();
  }

  Future<Set<String>> earnedTrophyKeys(String userId) async {
    final db = await LocalDatabase.instance.database;
    final rows = await db.query('trophies', columns: ['trophy_key'], where: 'user_id = ?', whereArgs: [userId]);
    return rows.map((r) => r['trophy_key'] as String).toSet();
  }

  Future<void> awardTrophy(String userId, String trophyKey) async {
    final db = await LocalDatabase.instance.database;
    await db.insert('trophies', {
      'user_id': userId,
      'trophy_key': trophyKey,
      'earned_at': DateTime.now().toIso8601String(),
      'synced': 0,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    DataEvents.instance.notifyChanged();
  }

  Future<int> trophyCount(String userId) async {
    final db = await LocalDatabase.instance.database;
    final result = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM trophies WHERE user_id = ?', [userId]),
    );
    return result ?? 0;
  }

  /// Territory cells first claimed within [start, end) — used for
  /// gamification/monthly_recap_screen.dart's "new ground this month",
  /// distinct from [territoryCellCount]'s all-time total.
  Future<int> territoryCellCountInRange(String userId, {required DateTime start, required DateTime end}) async {
    final db = await LocalDatabase.instance.database;
    final result = Sqflite.firstIntValue(
      await db.rawQuery(
        'SELECT COUNT(*) FROM territory_cells WHERE user_id = ? AND first_seen_at >= ? AND first_seen_at < ?',
        [userId, start.toIso8601String(), end.toIso8601String()],
      ),
    );
    return result ?? 0;
  }

  /// Trophy keys earned within [start, end) — for the same monthly
  /// recap use as [territoryCellCountInRange].
  Future<List<String>> trophyKeysEarnedInRange(String userId, {required DateTime start, required DateTime end}) async {
    final db = await LocalDatabase.instance.database;
    final rows = await db.query(
      'trophies',
      columns: ['trophy_key'],
      where: 'user_id = ? AND earned_at >= ? AND earned_at < ?',
      whereArgs: [userId, start.toIso8601String(), end.toIso8601String()],
    );
    return rows.map((r) => r['trophy_key'] as String).toList();
  }
}
