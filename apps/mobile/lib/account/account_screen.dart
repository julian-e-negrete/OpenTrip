import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../auth/auth_service.dart';
import '../auth/current_user.dart';
import '../auth/login_screen.dart';
import '../autostart/auto_start_controller.dart';
import '../data/account_data_service.dart';
import '../data/catalog/country_catalog.dart';
import '../data/data_events.dart';
import '../data/local_image_store.dart';
import '../data/models/user_profile.dart';
import '../data/repositories/profile_repository.dart';
import '../data/repositories/gamification_repository.dart';
import '../data/repositories/trip_repository.dart';
import '../data/repositories/vehicle_repository.dart';
import '../gamification/monthly_recap_screen.dart';
import '../sync/sync_service.dart';
import 'country_picker.dart';

/// Identity (display name + avatar — deliberately never the email, per
/// the "other users should be able to identify you without seeing your
/// email" requirement), local stats, and account management.
///
/// The display name is what shows up on the leaderboard
/// (leaderboard/leaderboard_screen.dart) for a real signed-in account —
/// it's saved locally and best-effort mirrored into Supabase's user
/// metadata too.
class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  late String _userId;
  UserProfile? _profile;
  int _vehicleCount = 0;
  int _tripCount = 0;
  int _trophyCount = 0;
  double _totalDistanceMeters = 0;
  bool _loading = true;
  bool _busy = false;
  bool _autoStartEnabled = false;
  bool _autoStartBusy = false;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _load();
    // This screen lives inside HomeShell's IndexedStack, so initState only
    // ever runs once — reload whenever a vehicle/trip/profile changes
    // elsewhere, so the counts and distance total stay accurate.
    DataEvents.instance.listenable.addListener(_load);
  }

  @override
  void dispose() {
    DataEvents.instance.listenable.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final userId = await CurrentUser.instance.id();
    final profile = await ProfileRepository.instance.get(userId);
    final vehicles = await VehicleRepository.instance.listForUser(userId);
    final trips = await TripRepository.instance.listForUser(userId);
    final trophyCount = await GamificationRepository.instance.trophyCount(userId);
    final totalDistance = trips.fold<double>(0, (sum, t) => sum + t.distanceMeters);
    final autoStartEnabled = await AutoStartController.instance.isEnabled();
    if (!mounted) return;
    setState(() {
      _userId = userId;
      _profile = profile;
      _vehicleCount = vehicles.length;
      _tripCount = trips.length;
      _trophyCount = trophyCount;
      _totalDistanceMeters = totalDistance;
      _autoStartEnabled = autoStartEnabled;
      _loading = false;
    });
  }

  Future<void> _syncNow() async {
    setState(() => _syncing = true);
    await SyncService.instance.pushPendingChanges();
    await SyncService.instance.pullAll();
    await _load();
    if (mounted) setState(() => _syncing = false);
  }

  String _syncStatusText() {
    final error = SyncService.instance.lastError;
    if (error != null) return 'Last sync failed: $error';
    final at = SyncService.instance.lastSyncAt;
    if (at == null) return 'Not synced yet';
    return 'Last synced ${at.toLocal().toString().substring(0, 19)}';
  }

  String get _displayName {
    final name = _profile?.displayName;
    return (name == null || name.isEmpty) ? 'Unnamed rider' : name;
  }

  Future<void> _editName() async {
    final controller = TextEditingController(text: _profile?.displayName ?? '');
    final newName = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Your name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'How other riders will see you'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (newName == null || newName.isEmpty) return;

    // synced: false explicitly — copyWith would otherwise preserve a
    // prior "already synced" flag from _profile, and this edit would
    // never get pushed again. See sync/sync_service.dart.
    final updated = (_profile ?? UserProfile(userId: _userId, displayName: newName)).copyWith(
      displayName: newName,
      synced: false,
    );
    await ProfileRepository.instance.upsert(updated);
    if (!CurrentUser.instance.isGuest) {
      // Best-effort — a failed network call here shouldn't undo the local save.
      unawaited(AuthService.instance.updateDisplayName(newName).catchError((_) {}));
    }
  }

  Future<void> _editCountry() async {
    final picked = await pickCountry(context, currentCode: _profile?.countryCode);
    if (picked == null) return;

    // synced: false explicitly — see the same note in _editName above.
    final updated = (_profile ?? UserProfile(userId: _userId, displayName: '')).copyWith(
      countryCode: picked.code,
      synced: false,
    );
    await ProfileRepository.instance.upsert(updated);
  }

  Future<void> _setAutoStartEnabled(bool enabled) async {
    setState(() => _autoStartBusy = true);
    String? error;
    if (enabled) {
      error = await AutoStartController.instance.enable();
    } else {
      await AutoStartController.instance.disable();
    }
    if (!mounted) return;
    setState(() {
      // Only actually flips on success — a denied permission or a failed
      // service start leaves the switch showing what's really happening,
      // not what was requested.
      if (error == null) _autoStartEnabled = enabled;
      _autoStartBusy = false;
    });
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
    }
  }

  Future<void> _setLeaderboardVisible(bool visible) async {
    // synced: false explicitly — see the same note in _editName above.
    final updated = (_profile ?? UserProfile(userId: _userId, displayName: '')).copyWith(
      leaderboardVisible: visible,
      synced: false,
    );
    await ProfileRepository.instance.upsert(updated);
  }

  Future<void> _editAvatar() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 800);
    if (picked == null) return;
    final path = await LocalImageStore.save(File(picked.path));
    await LocalImageStore.deleteIfExists(_profile?.avatarPath);
    final updated = (_profile ?? UserProfile(userId: _userId, displayName: '')).copyWith(
      avatarPath: path,
      synced: false,
    );
    await ProfileRepository.instance.upsert(updated);
  }

  Future<void> _signIn() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => LoginScreen(onContinueAsGuest: () => Navigator.of(context).pop())),
    );
    if (mounted) await _load();
  }

  Future<void> _deleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete account?'),
        content: const Text(
          'This permanently deletes every vehicle, trip, and photo — on '
          'this device, and in the cloud if you\'re signed in and synced. '
          'This cannot be undone.\n\n'
          'If you\'re signed in with Google or email, this does not delete '
          'the Google/email account itself — only this app\'s data. '
          'You\'ll be signed out.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: const Text('Delete everything'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    final wasGuest = CurrentUser.instance.isGuest;
    if (!wasGuest) {
      // Before signing out — deleteAllRemoteData needs the still-active
      // session to authenticate the delete against RLS.
      await SyncService.instance.deleteAllRemoteData(_userId);
    }
    await AccountDataService.wipeLocalData(_userId);
    if (wasGuest) {
      await CurrentUser.instance.resetGuestId();
      if (mounted) setState(() => _busy = false);
      await _load();
    } else {
      // _AuthGate's auth-state listener takes over navigation to the login
      // screen once this completes.
      await AuthService.instance.signOut();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final guest = CurrentUser.instance.isGuest;
    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: GestureDetector(
              onTap: _editAvatar,
              child: CircleAvatar(
                radius: 44,
                backgroundImage: _profile?.avatarPath != null ? FileImage(File(_profile!.avatarPath!)) : null,
                child: _profile?.avatarPath == null
                    ? const Icon(Icons.person_outline, size: 36)
                    : null,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton.icon(
              onPressed: _editName,
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: Text(_displayName),
            ),
          ),
          Center(
            child: TextButton.icon(
              onPressed: _editCountry,
              icon: const Icon(Icons.public_outlined, size: 16),
              label: Text(countryForCode(_profile?.countryCode)?.name ?? 'Add your country'),
            ),
          ),
          if (guest)
            const Center(
              child: Text(
                'Local testing mode — not signed in',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Auto-start drive detection'),
            subtitle: const Text(
              'Starts recording automatically once driving is detected, even if OpenTrip '
              'isn\'t open. Can\'t always tell your own vehicle apart from being a '
              'passenger in a bus or train — GPS-only, doesn\'t connect a bike for you.',
            ),
            value: _autoStartEnabled,
            onChanged: _autoStartBusy ? null : _setAutoStartEnabled,
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _StatTile(label: 'Vehicles', value: '$_vehicleCount'),
              _StatTile(label: 'Trips', value: '$_tripCount'),
              _StatTile(label: 'Distance', value: '${(_totalDistanceMeters / 1000).toStringAsFixed(0)} km'),
              _StatTile(label: 'Trophies', value: '$_trophyCount'),
            ],
          ),
          const SizedBox(height: 16),
          Center(
            child: OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const MonthlyRecapScreen()),
              ),
              icon: const Icon(Icons.calendar_month_outlined),
              label: const Text('Monthly recap'),
            ),
          ),
          if (!guest) ...[
            const SizedBox(height: 24),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Show me on leaderboards'),
              subtitle: const Text(
                'Off hides you from the global leaderboard, friends leaderboard, '
                'and territory map — your trips still sync either way.',
              ),
              value: _profile?.leaderboardVisible ?? true,
              onChanged: _setLeaderboardVisible,
            ),
            const SizedBox(height: 8),
            Center(
              child: Column(
                children: [
                  OutlinedButton.icon(
                    onPressed: _syncing ? null : _syncNow,
                    icon: _syncing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.cloud_sync_outlined),
                    label: Text(_syncing ? 'Syncing…' : 'Sync now'),
                  ),
                  const SizedBox(height: 4),
                  Text(_syncStatusText(), style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            ),
          ],
          const SizedBox(height: 32),
          if (guest)
            OutlinedButton.icon(onPressed: _signIn, icon: const Icon(Icons.login), label: const Text('Sign in'))
          else
            OutlinedButton.icon(
              onPressed: () => AuthService.instance.signOut(),
              icon: const Icon(Icons.logout),
              label: const Text('Sign out'),
            ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _busy ? null : _deleteAccount,
            style: OutlinedButton.styleFrom(foregroundColor: Colors.redAccent),
            icon: const Icon(Icons.delete_forever_outlined),
            label: Text(_busy ? 'Deleting…' : 'Delete account'),
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }
}
