import 'package:uuid/uuid.dart';

import '../local_database.dart';
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
    VehicleBleConnector bleConnector = VehicleBleConnector.none,
  }) async {
    final vehicle = Vehicle(
      id: _uuid.v4(),
      userId: userId,
      name: name,
      type: type,
      bleConnector: bleConnector,
      createdAt: DateTime.now(),
    );
    final db = await LocalDatabase.instance.database;
    await db.insert('vehicles', vehicle.toRow());
    return vehicle;
  }

  Future<void> update(Vehicle vehicle) async {
    final db = await LocalDatabase.instance.database;
    await db.update('vehicles', vehicle.toRow(), where: 'id = ?', whereArgs: [vehicle.id]);
  }

  Future<void> delete(String vehicleId) async {
    final db = await LocalDatabase.instance.database;
    await db.delete('vehicles', where: 'id = ?', whereArgs: [vehicleId]);
  }
}
