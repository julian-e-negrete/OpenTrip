import 'dart:async';

import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_service.dart';
import '../config/app_config.dart';
import '../data/data_events.dart';
import '../data/local_database.dart';
import '../data/models/trip.dart';
import '../data/models/trip_music_event.dart';
import '../data/models/trip_point.dart';
import '../data/models/user_profile.dart';
import '../data/models/vehicle.dart';
import '../data/repositories/trip_repository.dart';
import '../friends/friend_models.dart';
import '../gamification/territory_map_cell.dart';
import '../leaderboard/leaderboard_entry.dart';

/// Mirrors local vehicles/trips/trip_points/profile (display name only)
/// to Supabase Postgres — see /supabase/schema.sql for the tables this
/// pushes to and pulls from, and /docs/CLOUD_SYNC_SETUP.md for the setup
/// steps only you can do (running that SQL, and enabling Realtime
/// replication, once in your project).
///
/// Strategy:
/// - **Push**: every local vehicle/trip/profile write marks itself
///   `synced = 0` (see the `synced` field on those models). This service
///   listens to the same DataEvents bus the UI already reloads from, and
///   after any change, upserts every unsynced row for the signed-in user,
///   marking it synced on success. A trip's points are pushed in bulk
///   alongside it, once, the same moment the trip itself is pushed.
/// - **Pull (catch-up)**: [pullAll] fetches every vehicle/trip/profile row
///   for the signed-in user and upserts them into local SQLite. Runs once
///   right after sign-in (including "already signed in" on a cold app
///   start) to catch this device up on anything that happened while it
///   wasn't running — a websocket subscription can't deliver events from
///   before it existed.
/// - **Live (continuous)**: [_startRealtimeSync] subscribes to Postgres
///   Changes (a Supabase Realtime feature — logical replication over a
///   websocket, not polling) on vehicles/trips/profiles, filtered to the
///   signed-in user, for as long as the app is running and signed in. A
///   change made on another device lands here within roughly a second,
///   applied straight to local SQLite, no button or reconnect needed.
///   Trip points are deliberately **not** part of this subscription — a
///   finished trip can push hundreds of point rows in one go, which would
///   mean hundreds of individual realtime events on every other device;
///   they stay on the existing lazy-pull-per-trip model instead (see
///   TripRepository.pointsForTrip), which is the right shape for
///   "load this trip's route when I open it," not a live feed.
///
/// Remote-applied rows go straight into SQLite (bypassing the
/// repositories' create/update methods, the same way [pullAll] already
/// does) specifically so they don't re-trigger a push of the row that was
/// just pulled — see [_applyRemoteRow].
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
  RealtimeChannel? _channel;

  SupabaseClient get _client => Supabase.instance.client;

  bool get _canSync => AppConfig.isSupabaseConfigured && AuthService.instance.isSignedIn;

  /// Call once at app start (see main.dart). Safe to call more than once.
  void startListening() {
    if (_listening) return;
    _listening = true;
    DataEvents.instance.listenable.addListener(_onLocalChange);

    if (!AppConfig.isSupabaseConfigured) return;
    // Trigger catch-up + live sync off the actual auth-state stream, not
    // a screen's initState — a screen inside HomeShell's IndexedStack
    // only initializes once (see data/data_events.dart's doc comment for
    // the same issue on the UI side), so it would miss a sign-in that
    // happens later in the same session (e.g. guest -> "Sign in" from the
    // Account tab). `initialSession` covers the "already signed in" case
    // on a cold app start, when `signedIn` never fires because there's no
    // new sign-in to report.
    AuthService.instance.onAuthStateChange.listen((state) {
      if (state.event == AuthChangeEvent.signedIn || state.event == AuthChangeEvent.initialSession) {
        if (AuthService.instance.isSignedIn) {
          unawaited(pullAll().then((_) => _startRealtimeSync()));
        }
      } else if (state.event == AuthChangeEvent.signedOut) {
        unawaited(_stopRealtimeSync());
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
        await _pushMusicEvents(trip.id);
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

      // Territory/trophies (gamification/) — same unsynced-row pattern,
      // pushed in bulk since a finished trip can add many cells at once.
      final cellRows = await db.query(
        'territory_cells',
        where: 'user_id = ? AND synced = 0',
        whereArgs: [userId],
      );
      if (cellRows.isNotEmpty) {
        await _client.from('territory_cells').upsert(
          cellRows
              .map(
                (r) => {
                  'user_id': r['user_id'],
                  'cell_key': r['cell_key'],
                  'first_seen_at': r['first_seen_at'],
                  // Overwrite, not increment — the local row is already the
                  // authoritative cumulative count (see
                  // GamificationRepository.addTerritoryCells).
                  'visit_count': r['visit_count'],
                },
              )
              .toList(),
        );
        final cellBatch = db.batch();
        for (final row in cellRows) {
          cellBatch.update(
            'territory_cells',
            {'synced': 1},
            where: 'user_id = ? AND cell_key = ?',
            whereArgs: [row['user_id'], row['cell_key']],
          );
        }
        await cellBatch.commit(noResult: true);
      }

      final trophyRows = await db.query(
        'trophies',
        where: 'user_id = ? AND synced = 0',
        whereArgs: [userId],
      );
      if (trophyRows.isNotEmpty) {
        await _client.from('trophies').upsert(
          trophyRows
              .map((r) => {'user_id': r['user_id'], 'trophy_key': r['trophy_key'], 'earned_at': r['earned_at']})
              .toList(),
        );
        final trophyBatch = db.batch();
        for (final row in trophyRows) {
          trophyBatch.update(
            'trophies',
            {'synced': 1},
            where: 'user_id = ? AND trophy_key = ?',
            whereArgs: [row['user_id'], row['trophy_key']],
          );
        }
        await trophyBatch.commit(noResult: true);
      }

      lastSyncAt = DateTime.now();
      lastError = null;
      // gamification/territory_map_screen.dart reads *remote* aggregate
      // state (get_territory_map()), not local rows — the local write
      // that triggered this push already fired a DataEvents notification,
      // but that reload could easily race ahead of this push actually
      // landing. Firing again once the push genuinely completes is what
      // lets that screen (and anything else keyed off synced state) catch
      // up without the user having to know to pull-to-refresh.
      if (cellRows.isNotEmpty || trophyRows.isNotEmpty) {
        DataEvents.instance.notifyChanged();
      }
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

  Future<void> _pushMusicEvents(String tripId) async {
    final events = await TripRepository.instance.musicEventsForTrip(tripId);
    if (events.isEmpty) return;
    await _client.from('trip_music_events').upsert(events.map((e) => e.toSupabaseRow()).toList());
  }

  /// Same lazy-pull-per-trip shape as [pullTripPoints], for a trip's
  /// music timeline instead of its GPS route.
  Future<List<TripMusicEvent>> pullMusicEvents(String tripId) async {
    if (!_canSync) return const [];
    final rows = await _client.from('trip_music_events').select().eq('trip_id', tripId).order('seq');
    final events = rows.map((row) => TripMusicEvent.fromSupabaseRow(row)).toList();
    if (events.isNotEmpty) {
      final db = await LocalDatabase.instance.database;
      final batch = db.batch();
      for (final event in events) {
        batch.insert('trip_music_events', event.toRow(), conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    }
    return events;
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

  /// Subscribes to live Postgres Changes for the signed-in user's
  /// vehicles/trips/profile row. Requires Realtime replication to be
  /// enabled for these tables in the Supabase project (see
  /// supabase/enable_realtime.sql + docs/CLOUD_SYNC_SETUP.md) — if it
  /// isn't, this subscribes successfully but simply never receives
  /// events, which fails silently by design (same posture as the rest of
  /// this file when the schema itself hasn't been applied yet).
  Future<void> _startRealtimeSync() async {
    if (!_canSync) return;
    await _stopRealtimeSync();

    final userId = AuthService.instance.currentUser!.id;
    final channel = _client.channel('opentrip-user-$userId');

    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'vehicles',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'user_id', value: userId),
          callback: (payload) => _applyRemoteRow('vehicles', payload),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'trips',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'user_id', value: userId),
          callback: (payload) => _applyRemoteRow('trips', payload),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'profiles',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'user_id', value: userId),
          callback: (payload) => _applyRemoteRow('profiles', payload),
        )
        .subscribe();

    _channel = channel;
  }

  Future<void> _stopRealtimeSync() async {
    final channel = _channel;
    if (channel == null) return;
    _channel = null;
    await _client.removeChannel(channel);
  }

  /// Applies one Postgres Changes event straight to local SQLite —
  /// deliberately not via the repositories' create/update methods (which
  /// would mark the row `synced = 0` again and cause this device to
  /// immediately push back a row it just received). Marked `synced = 1`
  /// here instead, since it's already on the server by definition.
  Future<void> _applyRemoteRow(String table, PostgresChangePayload payload) async {
    final db = await LocalDatabase.instance.database;
    try {
      if (payload.eventType == PostgresChangeEvent.delete) {
        // profiles' primary key is user_id, not id — read whichever
        // column this table actually uses so oldRecord lookup succeeds.
        final idColumn = table == 'profiles' ? 'user_id' : 'id';
        final id = payload.oldRecord[idColumn] as String?;
        if (id == null) return;
        await db.delete(table, where: '$idColumn = ?', whereArgs: [id]);
      } else {
        final row = payload.newRecord;
        final Map<String, Object?> localRow = switch (table) {
          'vehicles' => Vehicle.fromSupabaseRow(row).toRow(),
          'trips' => Trip.fromSupabaseRow(row).toRow(),
          'profiles' => await _mergeRemoteProfile(db, row),
          _ => throw StateError('Unexpected realtime table: $table'),
        };
        await db.insert(table, localRow, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      DataEvents.instance.notifyChanged();
    } catch (e) {
      lastError = e.toString();
    }
  }

  /// A remote profile row has no avatar (that's local-only) — preserve
  /// whatever this device already has on disk rather than clearing it.
  Future<Map<String, Object?>> _mergeRemoteProfile(Database db, Map<String, dynamic> row) async {
    final userId = row['user_id'] as String;
    final existing = await db.query('profiles', where: 'user_id = ?', whereArgs: [userId], limit: 1);
    final localAvatar = existing.isNotEmpty ? existing.first['avatar_path'] as String? : null;
    return UserProfile.fromSupabaseRow(row, localAvatarPath: localAvatar).toRow();
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

  /// Deletes a trip's remote row (and, via Postgres's real `ON DELETE
  /// CASCADE`, its points too). Same best-effort posture as
  /// [deleteVehicleRemote].
  Future<void> deleteTripRemote(String tripId) async {
    if (!_canSync) return;
    try {
      await _client.from('trips').delete().eq('id', tripId);
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
      // Not cascaded from vehicles/profiles — territory_cells and
      // trophies (supabase/leaderboard.sql) are independent tables keyed
      // only off auth.users, so they need their own explicit delete.
      await _client.from('territory_cells').delete().eq('user_id', userId);
      await _client.from('trophies').delete().eq('user_id', userId);
    } catch (e) {
      lastError = e.toString();
    }
  }

  /// Calls supabase/leaderboard.sql's get_leaderboard() function. Only
  /// ever returns aggregated numbers + display names — see that file for
  /// why a `security definer` function, not a view, was necessary to
  /// show cross-user data at all given every table's RLS. Returns an
  /// empty list (not a thrown error) if the function doesn't exist yet
  /// (leaderboard.sql not applied) or the caller isn't signed in — the
  /// UI shows an explanatory state for both, see leaderboard/.
  Future<List<LeaderboardEntry>> fetchLeaderboard() async {
    if (!_canSync) return const [];
    try {
      final rows = await _client.rpc('get_leaderboard') as List;
      return rows.map((row) => LeaderboardEntry.fromRow(row as Map<String, dynamic>)).toList();
    } catch (e) {
      lastError = e.toString();
      return const [];
    }
  }

  /// Every claimed territory cell across all riders, for
  /// gamification/territory_map_screen.dart. See get_territory_map()'s
  /// comment in supabase/leaderboard.sql for why this needed its own
  /// security-definer function rather than a plain SELECT.
  Future<List<TerritoryMapCell>> fetchTerritoryMap() async {
    if (!_canSync) return const [];
    try {
      final rows = await _client.rpc('get_territory_map') as List;
      return rows.map((row) => TerritoryMapCell.fromRow(row as Map<String, dynamic>)).toList();
    } catch (e) {
      lastError = e.toString();
      return const [];
    }
  }

  /// Same shape as [fetchTerritoryMap], scoped to you plus your accepted
  /// friends — see get_friends_territory_map() in supabase/friends.sql.
  Future<List<TerritoryMapCell>> fetchFriendsTerritoryMap() async {
    if (!_canSync) return const [];
    try {
      final rows = await _client.rpc('get_friends_territory_map') as List;
      return rows.map((row) => TerritoryMapCell.fromRow(row as Map<String, dynamic>)).toList();
    } catch (e) {
      lastError = e.toString();
      return const [];
    }
  }

  /// Riders whose display name contains [query] (case-insensitive),
  /// excluding yourself — see search_riders() in supabase/friends.sql.
  Future<List<RiderSummary>> searchRiders(String query) async {
    if (!_canSync || query.trim().isEmpty) return const [];
    try {
      final rows = await _client.rpc('search_riders', params: {'query': query.trim()}) as List;
      return rows.map((row) => RiderSummary.fromRow(row as Map<String, dynamic>)).toList();
    } catch (e) {
      lastError = e.toString();
      return const [];
    }
  }

  /// Sends a friend request to [userId] — or accepts theirs, if they'd
  /// already sent one to you. Returns the outcome string
  /// send_or_accept_friend_request() reports ('requested', 'accepted',
  /// 'already_friends', 'already_requested'), or null on failure.
  Future<String?> sendOrAcceptFriendRequest(String userId) async {
    if (!_canSync) return null;
    try {
      final result = await _client.rpc('send_or_accept_friend_request', params: {'target_user_id': userId});
      return result as String?;
    } catch (e) {
      lastError = e.toString();
      return null;
    }
  }

  Future<bool> acceptFriendRequest(String requesterId) async {
    if (!_canSync) return false;
    try {
      await _client.rpc('accept_friend_request', params: {'requester_user_id': requesterId});
      return true;
    } catch (e) {
      lastError = e.toString();
      return false;
    }
  }

  /// Removes a friendship in either direction — also how a pending
  /// incoming request is declined, or one you sent is cancelled, since
  /// both are just rows in the same table server-side.
  Future<bool> removeFriendship(String otherUserId) async {
    if (!_canSync) return false;
    try {
      await _client.rpc('remove_friendship', params: {'other_user_id': otherUserId});
      return true;
    } catch (e) {
      lastError = e.toString();
      return false;
    }
  }

  Future<List<RiderSummary>> fetchFriends() async {
    if (!_canSync) return const [];
    try {
      final rows = await _client.rpc('get_friends') as List;
      return rows.map((row) => RiderSummary.fromRow(row as Map<String, dynamic>)).toList();
    } catch (e) {
      lastError = e.toString();
      return const [];
    }
  }

  Future<List<PendingFriendRequest>> fetchPendingFriendRequests() async {
    if (!_canSync) return const [];
    try {
      final rows = await _client.rpc('get_pending_friend_requests') as List;
      return rows.map((row) => PendingFriendRequest.fromRow(row as Map<String, dynamic>)).toList();
    } catch (e) {
      lastError = e.toString();
      return const [];
    }
  }

  /// Same shape as [fetchLeaderboard], scoped to you plus your accepted
  /// friends — see get_friends_leaderboard() in supabase/friends.sql.
  Future<List<LeaderboardEntry>> fetchFriendsLeaderboard() async {
    if (!_canSync) return const [];
    try {
      final rows = await _client.rpc('get_friends_leaderboard') as List;
      return rows.map((row) => LeaderboardEntry.fromRow(row as Map<String, dynamic>)).toList();
    } catch (e) {
      lastError = e.toString();
      return const [];
    }
  }
}
