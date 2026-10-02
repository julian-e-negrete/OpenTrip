import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_service.dart';
import '../config/app_config.dart';
import 'crew_models.dart';

/// Crews (supabase/crews.sql): management calls for the Crews screen, and
/// the live side of a group ride — publishing your own position while
/// recording and polling your crewmates' positions for the Record map.
///
/// Live positions are polled (every [_pollInterval]) rather than pushed
/// over Realtime on purpose: what any one rider may see depends on
/// per-crew sharing flags evaluated inside get_crew_live_positions(),
/// which a Realtime row subscription can't apply, and a few-second-old
/// position is plenty for "where's everyone?" on a ride. Your own
/// position is published at most every [_publishInterval] — one tiny
/// upsert, not a per-GPS-fix write.
///
/// Sign-in only, like the rest of the social features: a guest has no
/// account for a crewmate to see.
class CrewService {
  CrewService._();
  static final instance = CrewService._();

  static const _pollInterval = Duration(seconds: 5);
  static const _publishInterval = Duration(seconds: 5);
  static const _shareWhileRidingKey = 'opentrip_crew_share_while_riding';

  String? lastError;

  /// Crewmates currently riding and visible to you. Empty unless a ride
  /// is recording or a crew map is open (see [acquireLiveFeed]).
  final liveCrew = ValueNotifier<List<CrewLivePosition>>(const []);

  Timer? _pollTimer;
  int _feedHolders = 0;
  bool _riding = false;
  bool _publishEnabled = false;
  DateTime? _lastPublishedAt;

  SupabaseClient get _client => Supabase.instance.client;

  bool get isAvailable => AppConfig.isSupabaseConfigured && AuthService.instance.isSignedIn;

  // ---- Settings -----------------------------------------------------------

  /// Global "share my position with my crews while I ride" switch, on top
  /// of each crew's own share_location flag — a one-tap way to ride
  /// privately without editing every crew.
  Future<bool> shareWhileRiding() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_shareWhileRidingKey) ?? true;
  }

  Future<void> setShareWhileRiding(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_shareWhileRidingKey, value);
    if (_riding) {
      _publishEnabled = value && _publishEnabled;
      if (!value) await _clearOwnPosition();
    }
  }

  // ---- Management ---------------------------------------------------------

  Future<List<Crew>> fetchMyCrews() async {
    if (!isAvailable) return const [];
    try {
      final rows = await _client.rpc('get_my_crews') as List;
      lastError = null;
      return rows.map((r) => Crew.fromRow(r as Map<String, dynamic>)).toList();
    } catch (e) {
      lastError = e.toString();
      return const [];
    }
  }

  Future<List<CrewMember>> fetchMembers(String crewId) async {
    if (!isAvailable) return const [];
    try {
      final rows = await _client.rpc('get_crew_members', params: {'target_crew_id': crewId}) as List;
      return rows.map((r) => CrewMember.fromRow(r as Map<String, dynamic>)).toList();
    } catch (e) {
      lastError = e.toString();
      return const [];
    }
  }

  Future<String?> createCrew(String name) async {
    if (!isAvailable) return null;
    try {
      return await _client.rpc('create_crew', params: {'crew_name': name}) as String;
    } catch (e) {
      lastError = e.toString();
      return null;
    }
  }

  /// 'added' | 'already_member' | 'not_friends' | 'not_member', or null
  /// on a network/server error (see [lastError]).
  Future<String?> addMember(String crewId, String userId) async {
    if (!isAvailable) return null;
    try {
      return await _client.rpc('add_crew_member', params: {'target_crew_id': crewId, 'member_user_id': userId})
          as String;
    } catch (e) {
      lastError = e.toString();
      return null;
    }
  }

  Future<bool> removeMember(String crewId, String userId) =>
      _void('remove_crew_member', {'target_crew_id': crewId, 'member_user_id': userId});

  Future<bool> leaveCrew(String crewId) => _void('leave_crew', {'target_crew_id': crewId});

  Future<bool> renameCrew(String crewId, String name) =>
      _void('rename_crew', {'target_crew_id': crewId, 'crew_name': name});

  Future<bool> setSharing(Crew crew) => _void('set_crew_sharing', {
        'target_crew_id': crew.id,
        'location_on': crew.shareLocation,
        'speed_on': crew.shareSpeed,
        'lean_on': crew.shareLean,
      });

  Future<bool> _void(String fn, Map<String, dynamic> params) async {
    if (!isAvailable) return false;
    try {
      await _client.rpc(fn, params: params);
      lastError = null;
      return true;
    } catch (e) {
      lastError = e.toString();
      return false;
    }
  }

  // ---- Live feed ----------------------------------------------------------

  /// Starts polling crewmates' positions for as long as at least one
  /// holder (an active ride, an open crew map) wants them. Pair every call
  /// with [releaseLiveFeed].
  void acquireLiveFeed() {
    _feedHolders++;
    if (_feedHolders == 1 && isAvailable) {
      _poll();
      _pollTimer = Timer.periodic(_pollInterval, (_) => _poll());
    }
  }

  void releaseLiveFeed() {
    if (_feedHolders == 0) return;
    _feedHolders--;
    if (_feedHolders == 0) {
      _pollTimer?.cancel();
      _pollTimer = null;
      liveCrew.value = const [];
    }
  }

  Future<void> _poll() async {
    if (!isAvailable) return;
    try {
      final rows = await _client.rpc('get_crew_live_positions') as List;
      if (_feedHolders == 0) return; // released while the request was in flight
      liveCrew.value = rows.map((r) => CrewLivePosition.fromRow(r as Map<String, dynamic>)).toList();
    } catch (e) {
      // Keep the last known positions on a transient failure — a dropped
      // request mid-ride shouldn't make everyone vanish from the map.
      lastError = e.toString();
    }
  }

  /// Call when a recording starts. Decides once whether this ride
  /// publishes at all (signed in, global switch on, and sharing location
  /// with at least one crew), and starts the live feed either way.
  Future<void> startRide() async {
    if (_riding) return;
    _riding = true;
    _lastPublishedAt = null;
    acquireLiveFeed();
    if (!isAvailable) return;
    final share = await shareWhileRiding();
    final crews = await fetchMyCrews();
    _publishEnabled = _riding && share && crews.any((c) => c.shareLocation);
  }

  /// Call with every accepted GPS fix while recording; throttled
  /// internally, so calling it per fix is fine.
  void publishPosition({
    required double latitude,
    required double longitude,
    double? speedKph,
    double? leanDeg,
    double? headingDeg,
  }) {
    if (!_riding || !_publishEnabled || !isAvailable) return;
    final now = DateTime.now();
    final last = _lastPublishedAt;
    if (last != null && now.difference(last) < _publishInterval) return;
    _lastPublishedAt = now;
    final userId = AuthService.instance.currentUser!.id;
    unawaited(
      _client.from('live_positions').upsert({
        'user_id': userId,
        'latitude': latitude,
        'longitude': longitude,
        'speed_kph': speedKph,
        'lean_deg': leanDeg,
        'heading_deg': headingDeg,
      }).then((_) {}, onError: (Object e) => lastError = e.toString()),
    );
  }

  /// Call when the recording stops: stop publishing, remove our row so
  /// crewmates see us drop off right away rather than after the 2-minute
  /// staleness cutoff, and release this ride's hold on the live feed.
  Future<void> stopRide() async {
    if (!_riding) return;
    _riding = false;
    final wasPublishing = _publishEnabled;
    _publishEnabled = false;
    releaseLiveFeed();
    if (wasPublishing) await _clearOwnPosition();
  }

  Future<void> _clearOwnPosition() async {
    if (!isAvailable) return;
    try {
      await _client.from('live_positions').delete().eq('user_id', AuthService.instance.currentUser!.id);
    } catch (e) {
      lastError = e.toString();
    }
  }
}
