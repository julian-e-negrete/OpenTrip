import 'data_events.dart';
import 'local_database.dart';
import 'local_image_store.dart';
import 'repositories/profile_repository.dart';
import 'repositories/vehicle_repository.dart';

/// Backs the Account tab's "Delete account" action.
///
/// Only ever touches on-device data — every vehicle, trip, trip point,
/// profile row, and locally-stored photo for [userId]. It does **not**
/// delete a real Supabase account/email registration; that needs a
/// privileged server-side operation (an Edge Function using the
/// service_role key) this app doesn't have set up yet, since the anon/
/// publishable key a mobile client uses can't self-delete an auth user.
/// See docs/ROADMAP.md.
class AccountDataService {
  AccountDataService._();

  static Future<void> wipeLocalData(String userId) async {
    final vehicles = await VehicleRepository.instance.listForUser(userId);
    for (final vehicle in vehicles) {
      await LocalImageStore.deleteIfExists(vehicle.photoPath);
    }
    final profile = await ProfileRepository.instance.get(userId);
    await LocalImageStore.deleteIfExists(profile?.avatarPath);

    final db = await LocalDatabase.instance.database;
    await db.transaction((txn) async {
      // sqflite doesn't enforce the schema's ON DELETE CASCADE (foreign
      // keys aren't turned on), so trip_points needs an explicit delete.
      final tripRows = await txn.query('trips', columns: ['id'], where: 'user_id = ?', whereArgs: [userId]);
      for (final row in tripRows) {
        await txn.delete('trip_points', where: 'trip_id = ?', whereArgs: [row['id']]);
      }
      await txn.delete('trips', where: 'user_id = ?', whereArgs: [userId]);
      await txn.delete('vehicles', where: 'user_id = ?', whereArgs: [userId]);
      await txn.delete('profiles', where: 'user_id = ?', whereArgs: [userId]);
      await txn.delete('territory_cells', where: 'user_id = ?', whereArgs: [userId]);
      await txn.delete('trophies', where: 'user_id = ?', whereArgs: [userId]);
    });

    DataEvents.instance.notifyChanged();
  }
}
