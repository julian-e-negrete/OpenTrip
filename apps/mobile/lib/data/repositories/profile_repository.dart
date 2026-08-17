import 'package:sqflite/sqflite.dart';

import '../data_events.dart';
import '../local_database.dart';
import '../models/user_profile.dart';

class ProfileRepository {
  ProfileRepository._();
  static final instance = ProfileRepository._();

  Future<UserProfile?> get(String userId) async {
    final db = await LocalDatabase.instance.database;
    final rows = await db.query('profiles', where: 'user_id = ?', whereArgs: [userId], limit: 1);
    if (rows.isEmpty) return null;
    return UserProfile.fromRow(rows.first);
  }

  Future<void> upsert(UserProfile profile) async {
    final db = await LocalDatabase.instance.database;
    await db.insert('profiles', profile.toRow(), conflictAlgorithm: ConflictAlgorithm.replace);
    DataEvents.instance.notifyChanged();
  }
}
