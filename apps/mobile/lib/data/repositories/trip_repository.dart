import 'package:uuid/uuid.dart';

import '../data_events.dart';
import '../local_database.dart';
import '../models/trip.dart';
import '../models/trip_point.dart';

class TripRepository {
  TripRepository._();
  static final instance = TripRepository._();

  final _uuid = const Uuid();

  Future<Trip> startTrip({required String userId, required String vehicleId}) async {
    final trip = Trip(id: _uuid.v4(), userId: userId, vehicleId: vehicleId, startedAt: DateTime.now());
    final db = await LocalDatabase.instance.database;
    await db.insert('trips', trip.toRow());
    DataEvents.instance.notifyChanged();
    return trip;
  }

  /// Appends points in one transaction — called periodically while
  /// recording (see trip/location_recorder.dart), not once per GPS fix,
  /// to keep SQLite write volume reasonable. Deliberately doesn't fire
  /// DataEvents — that would make Trip history reload on every batch
  /// while a trip is being recorded, for no visible benefit (the list
  /// view doesn't show live point counts).
  Future<void> appendPoints(List<TripPoint> points) async {
    if (points.isEmpty) return;
    final db = await LocalDatabase.instance.database;
    final batch = db.batch();
    for (final point in points) {
      batch.insert('trip_points', point.toRow());
    }
    await batch.commit(noResult: true);
  }

  Future<Trip> finishTrip(Trip finished) async {
    final db = await LocalDatabase.instance.database;
    await db.update('trips', finished.toRow(), where: 'id = ?', whereArgs: [finished.id]);
    DataEvents.instance.notifyChanged();
    return finished;
  }

  Future<List<Trip>> listForVehicle(String vehicleId) async {
    final db = await LocalDatabase.instance.database;
    final rows = await db.query(
      'trips',
      where: 'vehicle_id = ?',
      whereArgs: [vehicleId],
      orderBy: 'started_at DESC',
    );
    return rows.map(Trip.fromRow).toList();
  }

  Future<List<Trip>> listForUser(String userId) async {
    final db = await LocalDatabase.instance.database;
    final rows = await db.query(
      'trips',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'started_at DESC',
    );
    return rows.map(Trip.fromRow).toList();
  }

  Future<List<TripPoint>> pointsForTrip(String tripId) async {
    final db = await LocalDatabase.instance.database;
    final rows = await db.query(
      'trip_points',
      where: 'trip_id = ?',
      whereArgs: [tripId],
      orderBy: 'seq ASC',
    );
    return rows.map(TripPoint.fromRow).toList();
  }

  Future<void> deleteTrip(String tripId) async {
    final db = await LocalDatabase.instance.database;
    await db.delete('trips', where: 'id = ?', whereArgs: [tripId]);
    DataEvents.instance.notifyChanged();
  }
}
