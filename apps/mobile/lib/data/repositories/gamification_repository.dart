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

  /// Records a trip's cells for this user: a cell seen for the first time
  /// gets a fresh row at visit_count 1; a cell seen again bumps its
  /// existing visit_count instead of being ignored. [territoryCellCount]
  /// (unique cells claimed, for the leaderboard's "territory" stat) is
  /// unaffected either way — it's a row count, and this never changes the
  /// row count for an already-seen cell. visit_count only feeds the
  /// territory map's heat intensity (gamification/territory_map_screen.dart):
  /// the more times you've ridden through a cell, the stronger it glows.
  Future<void> addTerritoryCells(String userId, Set<String> cellKeys) async {
    if (cellKeys.isEmpty) return;
    final db = await LocalDatabase.instance.database;
    final now = DateTime.now().toIso8601String();
    final batch = db.batch();
    for (final cellKey in cellKeys) {
      batch.rawInsert(
        '''
        INSERT INTO territory_cells (user_id, cell_key, first_seen_at, visit_count, synced)
        VALUES (?, ?, ?, 1, 0)
        ON CONFLICT(user_id, cell_key) DO UPDATE SET
          visit_count = visit_count + 1,
          synced = 0
        ''',
        [userId, cellKey, now],
      );
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
