import 'dart:async';

import 'package:uuid/uuid.dart';

import '../../sync/sync_service.dart';
import '../data_events.dart';
import '../local_database.dart';
import '../models/trip.dart';
import '../models/trip_point.dart';

class TripRepository {
  TripRepository._();
  static final instance = TripRepository._();

  final _uuid = const Uuid();

  Future<Trip> startTrip({required String userId, required String vehicleId, bool autoStarted = false}) async {
    final trip = Trip(
      id: _uuid.v4(),
      userId: userId,
      vehicleId: vehicleId,
      startedAt: DateTime.now(),
      autoStarted: autoStarted,
    );
    final db = await LocalDatabase.instance.database;
    await db.insert('trips', trip.toRow());
    DataEvents.instance.notifyChanged();
    return trip;
  }

  /// The trip currently being recorded for this user, if any — the trip
  /// with no `ended_at` yet. Durable, database-backed source of truth for
  /// "is a trip active right now," rather than in-memory state, since
  /// autostart/driving_detector_task.dart creates and finishes trips from
  /// a separate background isolate that doesn't share trip/recording_screen.dart's
  /// in-memory state. At most one should ever exist per user — both
  /// [startTrip] callers (the manual flow and the auto-detector) are
  /// expected to check this first.
  Future<Trip?> activeTripFor(String userId) async {
    final db = await LocalDatabase.instance.database;
    final rows = await db.query(
      'trips',
      where: 'user_id = ? AND ended_at IS NULL',
      whereArgs: [userId],
      orderBy: 'started_at DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : Trip.fromRow(rows.first);
  }

  /// The vehicle used on this user's most recently *started* trip, if
  /// any — the default guess for which vehicle an auto-detected drive
  /// belongs to, since there's no UI interaction available to ask.
  Future<String?> mostRecentVehicleId(String userId) async {
    final db = await LocalDatabase.instance.database;
    final rows = await db.query(
      'trips',
      columns: ['vehicle_id'],
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'started_at DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['vehicle_id'] as String;
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

  /// Trips started within [start, end) — used by
  /// gamification/monthly_recap_screen.dart to window an otherwise
  /// all-time aggregation by a single month.
  Future<List<Trip>> listForUserInRange(String userId, {required DateTime start, required DateTime end}) async {
    final db = await LocalDatabase.instance.database;
    final rows = await db.query(
      'trips',
      where: 'user_id = ? AND started_at >= ? AND started_at < ?',
      whereArgs: [userId, start.toIso8601String(), end.toIso8601String()],
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
    if (rows.isNotEmpty) {
      return rows.map(TripPoint.fromRow).toList();
    }
    // No local points — this trip may have been pulled from another
    // device via SyncService.pullAll, which doesn't eagerly fetch every
    // trip's points. Try fetching them now; a harmless no-op if there
    // genuinely are none (e.g. a trip stopped with zero GPS fixes) or
    // sync isn't available.
    return SyncService.instance.pullTripPoints(tripId);
  }

  /// Deletes a trip and its points. Deliberately leaves territory_cells
  /// and trophies (gamification/) untouched — you still physically
  /// covered that ground and earned those trophies even if you delete
  /// the trip record itself.
  Future<void> deleteTrip(String tripId) async {
    final db = await LocalDatabase.instance.database;
    // No local FK enforcement (see local_database.dart) — trip_points
    // needs its own explicit delete, unlike the remote side where
    // Postgres's real ON DELETE CASCADE (supabase/schema.sql) handles it.
    await db.delete('trip_points', where: 'trip_id = ?', whereArgs: [tripId]);
    await db.delete('trips', where: 'id = ?', whereArgs: [tripId]);
    DataEvents.instance.notifyChanged();
    // Best-effort — a local delete should never block on network.
    unawaited(SyncService.instance.deleteTripRemote(tripId));
  }
}
