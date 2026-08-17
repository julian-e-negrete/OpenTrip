import 'dart:async';

import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_service.dart';
import '../config/app_config.dart';
import '../data/data_events.dart';
import '../data/local_database.dart';
import '../data/models/trip.dart';
import '../data/models/trip_point.dart';
import '../data/models/user_profile.dart';
import '../data/models/vehicle.dart';
import '../data/repositories/trip_repository.dart';

/// Mirrors local vehicles/trips/trip_points/profile (display name only)
/// to Supabase Postgres — see /supabase/schema.sql for the tables this
/// pushes to and pulls from, and /docs/CLOUD_SYNC_SETUP.md for the setup
/// step only you can do (running that SQL once in your project).
///
/// Strategy, deliberately simple rather than a full offline sync engine:
/// - **Push**: every local vehicle/trip/profile write marks itself
///   `synced = 0` (see the `synced` field on those models). This service
///   listens to the same DataEvents bus the UI already reloads from, and
///   after any change, upserts every unsynced row for the signed-in user,
///   marking it synced on success. A trip's points are pushed in bulk
///   alongside it, once, the same moment the trip itself is pushed.
/// - **Pull**: [pullAll] fetches every vehicle/trip/profile row for the
///   signed-in user and upserts them into local SQLite (remote always
///   wins on conflict — there's no per-field merge). Called once right
///   after sign-in, not continuously, so this isn't real-time multi-device
///   sync; it's "catch this device up." Trip points are pulled lazily,
///   per-trip, from TripRepository.pointsForTrip, since eagerly pulling
///   every point of every trip up front doesn't scale.
///
/// Only ever runs for a real signed-in user — guest-mode data
/// (auth/current_user.dart) has no Supabase session to authenticate
/// with, and RLS in supabase/schema.sql would reject the write anyway.
/// That's intentional: guest data stays local-only until you sign in.
class SyncService {
  SyncService._();
  static final instance = SyncService._();

  bool _listening = false;
  bool _busy = false;
  DateTime? lastSyncAt;
  String? lastError;

  SupabaseClient get _client => Supabase.instance.client;

  bool get _canSync => AppConfig.isSupabaseConfigured && AuthService.instance.isSignedIn;

  /// Call once at app start (see main.dart). Safe to call more than once.
  void startListening() {
    if (_listening) return;
    _listening = true;
    DataEvents.instance.listenable.addListener(_onLocalChange);

    if (!AppConfig.isSupabaseConfigured) return;
    // Trigger the "catch this device up" pull off the actual sign-in
    // event, not a screen's initState — a screen inside HomeShell's
    // IndexedStack only initializes once (see data/data_events.dart's doc
    // comment for the same issue on the UI side), so it would miss a
    // sign-in that happens later in the same session (e.g. guest ->
    // "Sign in" from the Account tab).
    AuthService.instance.onAuthStateChange.listen((state) {
      if (state.event == AuthChangeEvent.signedIn) {
        unawaited(pullAll());
      }
    });
  }

  void _onLocalChange() {
    if (!_canSync) return;
    unawaited(pushPendingChanges());
  }

  Future<void> pushPendingChanges() async {
    if (!_canSync || _busy) return;
    _busy = true;
    try {
      final userId = AuthService.instance.currentUser!.id;
      final db = await LocalDatabase.instance.database;

      // Vehicles before trips — trips reference vehicle_id remotely too.
      final vehicleRows = await db.query(
        'vehicles',
        where: 'user_id = ? AND synced = 0',
        whereArgs: [userId],
      );
      for (final row in vehicleRows) {
        final vehicle = Vehicle.fromRow(row);
        await _client.from('vehicles').upsert(vehicle.toSupabaseRow());
        await db.update('vehicles', {'synced': 1}, where: 'id = ?', whereArgs: [vehicle.id]);
      }

      final tripRows = await db.query('trips', where: 'user_id = ? AND synced = 0', whereArgs: [userId]);
      for (final row in tripRows) {
        final trip = Trip.fromRow(row);
        await _client.from('trips').upsert(trip.toSupabaseRow());
        await _pushTripPoints(trip.id);
        await db.update('trips', {'synced': 1}, where: 'id = ?', whereArgs: [trip.id]);
      }

      final profileRows = await db.query(
        'profiles',
        where: 'user_id = ? AND synced = 0',
        whereArgs: [userId],
      );
      for (final row in profileRows) {
        final profile = UserProfile.fromRow(row);
        await _client.from('profiles').upsert(profile.toSupabaseRow());
        await db.update('profiles', {'synced': 1}, where: 'user_id = ?', whereArgs: [profile.userId]);
      }

      lastSyncAt = DateTime.now();
      lastError = null;
    } catch (e) {
      lastError = e.toString();
    } finally {
      _busy = false;
    }
  }

  Future<void> _pushTripPoints(String tripId) async {
    final points = await TripRepository.instance.pointsForTrip(tripId);
    if (points.isEmpty) return;
    const chunkSize = 500;
    for (var i = 0; i < points.length; i += chunkSize) {
      final end = (i + chunkSize < points.length) ? i + chunkSize : points.length;
      final chunk = points.sublist(i, end);
      await _client.from('trip_points').upsert(chunk.map((p) => p.toSupabaseRow()).toList());
    }
  }

  /// Fetches this trip's points from Supabase and caches them locally.
  /// Used by TripRepository.pointsForTrip as a fallback when a trip has
  /// no local points yet (e.g. it was pulled via [pullAll] on a new
  /// device, which doesn't eagerly fetch points).
  Future<List<TripPoint>> pullTripPoints(String tripId) async {
    if (!_canSync) return const [];
    final rows = await _client.from('trip_points').select().eq('trip_id', tripId).order('seq');
    final points = rows.map((row) => TripPoint.fromSupabaseRow(row)).toList();
    if (points.isNotEmpty) {
      final db = await LocalDatabase.instance.database;
      final batch = db.batch();
      for (final point in points) {
        batch.insert('trip_points', point.toRow(), conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    }
    return points;
  }

  /// Pulls every vehicle/trip/profile row for the signed-in user into
  /// local SQLite. Call once right after sign-in.
  Future<void> pullAll() async {
    if (!_canSync) return;
    try {
      final userId = AuthService.instance.currentUser!.id;
      final db = await LocalDatabase.instance.database;

      final remoteVehicles = await _client.from('vehicles').select().eq('user_id', userId);
      final vehicleBatch = db.batch();
      for (final row in remoteVehicles) {
        vehicleBatch.insert(
          'vehicles',
          Vehicle.fromSupabaseRow(row).toRow(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await vehicleBatch.commit(noResult: true);

      final remoteTrips = await _client.from('trips').select().eq('user_id', userId);
      final tripBatch = db.batch();
      for (final row in remoteTrips) {
        tripBatch.insert(
          'trips',
          Trip.fromSupabaseRow(row).toRow(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await tripBatch.commit(noResult: true);

      final remoteProfileRows = await _client.from('profiles').select().eq('user_id', userId).limit(1);
      if (remoteProfileRows.isNotEmpty) {
        final existing = await db.query('profiles', where: 'user_id = ?', whereArgs: [userId], limit: 1);
        final localAvatar = existing.isNotEmpty ? existing.first['avatar_path'] as String? : null;
        final profile = UserProfile.fromSupabaseRow(remoteProfileRows.first, localAvatarPath: localAvatar);
        await db.insert('profiles', profile.toRow(), conflictAlgorithm: ConflictAlgorithm.replace);
      }

      DataEvents.instance.notifyChanged();
      lastSyncAt = DateTime.now();
      lastError = null;
    } catch (e) {
      lastError = e.toString();
    }
  }

  /// Deletes a vehicle's remote row (and, via Postgres's real `ON DELETE
  /// CASCADE` in supabase/schema.sql, its trips and their points too —
  /// unlike local SQLite, which needed the explicit cascade in
  /// data/account_data_service.dart since foreign keys aren't enforced
  /// there). Best-effort: swallows failures so a local delete while
  /// offline doesn't roll back or throw — see docs/ROADMAP.md's note that
  /// an offline delete can leave a stale remote row until the next
  /// successful call to this.
  Future<void> deleteVehicleRemote(String vehicleId) async {
    if (!_canSync) return;
    try {
      await _client.from('vehicles').delete().eq('id', vehicleId);
    } catch (e) {
      lastError = e.toString();
    }
  }

  /// Deletes every remote row (vehicles, cascading to trips and
  /// trip_points, plus the profile) for the signed-in user. Used by
  /// "Delete account" (data/account_data_service.dart) so cloud data
  /// doesn't resurrect local data on the next [pullAll].
  Future<void> deleteAllRemoteData(String userId) async {
    if (!_canSync) return;
    try {
      await _client.from('vehicles').delete().eq('user_id', userId);
      await _client.from('profiles').delete().eq('user_id', userId);
    } catch (e) {
      lastError = e.toString();
    }
  }
}
