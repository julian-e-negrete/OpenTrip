import 'package:uuid/uuid.dart';

import '../data_events.dart';
import '../local_database.dart';
import '../local_image_store.dart';
import '../models/vehicle.dart';

class VehicleRepository {
  VehicleRepository._();
  static final instance = VehicleRepository._();

  final _uuid = const Uuid();

  Future<List<Vehicle>> listForUser(String userId) async {
    final db = await LocalDatabase.instance.database;
    final rows = await db.query(
      'vehicles',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'created_at ASC',
    );
    return rows.map(Vehicle.fromRow).toList();
  }

  Future<Vehicle> create({
    required String userId,
    required String name,
    required VehicleType type,
    String brand = '',
    String model = '',
    VehicleBleConnector bleConnector = VehicleBleConnector.none,
    String? photoPath,
  }) async {
    final vehicle = Vehicle(
      id: _uuid.v4(),
      userId: userId,
      name: name,
      type: type,
      brand: brand,
      model: model,
      bleConnector: bleConnector,
      photoPath: photoPath,
      createdAt: DateTime.now(),
    );
    final db = await LocalDatabase.instance.database;
    await db.insert('vehicles', vehicle.toRow());
    DataEvents.instance.notifyChanged();
    return vehicle;
  }

  Future<void> update(Vehicle vehicle) async {
    final db = await LocalDatabase.instance.database;
    await db.update('vehicles', vehicle.toRow(), where: 'id = ?', whereArgs: [vehicle.id]);
    DataEvents.instance.notifyChanged();
  }

  Future<void> delete(String vehicleId) async {
    final db = await LocalDatabase.instance.database;
    final rows = await db.query('vehicles', where: 'id = ?', whereArgs: [vehicleId], limit: 1);
    if (rows.isNotEmpty) {
      await LocalImageStore.deleteIfExists(rows.first['photo_path'] as String?);
    }
    await db.delete('vehicles', where: 'id = ?', whereArgs: [vehicleId]);
    DataEvents.instance.notifyChanged();
  }
}
