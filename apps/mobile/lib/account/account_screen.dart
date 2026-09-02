import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../auth/auth_service.dart';
import '../auth/current_user.dart';
import '../auth/login_screen.dart';
import '../data/account_data_service.dart';
import '../data/catalog/country_catalog.dart';
import '../data/data_events.dart';
import '../data/local_image_store.dart';
import '../data/models/user_profile.dart';
import '../data/repositories/gamification_repository.dart';
import '../data/repositories/profile_repository.dart';
import '../data/repositories/trip_repository.dart';
import '../data/repositories/vehicle_repository.dart';
import '../gamification/monthly_recap_screen.dart';
import '../screens/log_screen.dart';
import '../sync/sync_service.dart';
import '../theme/app_theme.dart';
import '../theme/date_fmt.dart';
import '../theme/layout_prefs.dart';
import '../theme/num_fmt.dart';
import '../theme/ph_icons.dart';
import '../theme/primitives.dart';
import 'country_picker.dart';

/// Identity (display name + avatar — deliberately never the email, per
/// the "other users should be able to identify you without seeing your
/// email" requirement), local stats, the Appearance section that drives
/// every layout preference (theme/layout_prefs.dart), and account
/// management.
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
  double _kmThisMonth = 0;
  bool _loading = true;
  bool _busy = false;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _load();
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
    final monthStart = DateTime(DateTime.now().year, DateTime.now().month, 1);
    final kmThisMonth =
        trips.where((t) => !t.startedAt.isBefore(monthStart)).fold<double>(0, (sum, t) => sum + t.distanceKm);
    if (!mounted) return;
    setState(() {
      _userId = userId;
      _profile = profile;
      _vehicleCount = vehicles.length;
      _tripCount = trips.length;
      _trophyCount = trophyCount;
      _totalDistanceMeters = totalDistance;
      _kmThisMonth = kmThisMonth;
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
      builder: (dialogContext) => AlertDialog(
        title: const Text('Your name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'How other riders will see you'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (newName == null || newName.isEmpty) return;

    final updated = (_profile ?? UserProfile(userId: _userId, displayName: newName)).copyWith(
      displayName: newName,
      synced: false,
    );
    await ProfileRepository.instance.upsert(updated);
    if (!CurrentUser.instance.isGuest) {
      unawaited(AuthService.instance.updateDisplayName(newName).catchError((_) {}));
    }
  }

  Future<void> _editCountry() async {
    final picked = await pickCountry(context, currentCode: _profile?.countryCode);
    if (picked == null) return;
    final updated = (_profile ?? UserProfile(userId: _userId, displayName: '')).copyWith(
      countryCode: picked.code,
      synced: false,
    );
    await ProfileRepository.instance.upsert(updated);
  }

  Future<void> _setLeaderboardVisible(bool visible) async {
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
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => LoginScreen(onContinueAsGuest: () => Navigator.of(context).pop())));
    if (mounted) await _load();
  }

  Future<void> _deleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
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
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: Theme.of(dialogContext).colorScheme.error),
            child: const Text('Delete everything'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    final wasGuest = CurrentUser.instance.isGuest;
    if (!wasGuest) {
      await SyncService.instance.deleteAllRemoteData(_userId);
    }
    await AccountDataService.wipeLocalData(_userId);
    if (wasGuest) {
      await CurrentUser.instance.resetGuestId();
      if (mounted) setState(() => _busy = false);
      await _load();
    } else {
      await AuthService.instance.signOut();
    }
  }

  Future<void> _confirmSignOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sign out?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Sign out')),
        ],
      ),
    );
    if (confirmed == true) await AuthService.instance.signOut();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final guest = CurrentUser.instance.isGuest;
    final country = countryForCode(_profile?.countryCode);

    return ListenableBuilder(
      listenable: LayoutPrefs.instance,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: const SizedBox.shrink(),
            actions: [
              IconButton(
                icon: const Icon(Ph.fileText, size: 18, color: Noct.n400),
                tooltip: 'Licences',
                onPressed: () => showLicensePage(context: context, applicationName: 'OpenTrip'),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 26),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: _editAvatar,
                      child: Container(
                        width: 60,
                        height: 60,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Noct.a900,
                          shape: BoxShape.circle,
                          image: _profile?.avatarPath != null
                              ? DecorationImage(image: FileImage(File(_profile!.avatarPath!)), fit: BoxFit.cover)
                              : null,
                        ),
                        child: _profile?.avatarPath == null
                            ? Text(
                                _displayName.isEmpty ? '?' : _displayName[0].toUpperCase(),
                                style: const TextStyle(fontSize: 22, color: Noct.a200, fontWeight: FontWeight.w500),
                              )
                            : null,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          GestureDetector(
                            onTap: _editName,
                            child: Text(
                              _displayName,
                              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w500, letterSpacing: -0.4, color: Noct.text),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(height: 2),
                          GestureDetector(
                            onTap: _editCountry,
                            child: Text(
                              [
                                country?.name ?? 'Add your country',
                                guest ? 'local only' : 'signed in',
                                if (!guest && SyncService.instance.lastSyncAt != null)
                                  'synced ${fmtRelative(SyncService.instance.lastSyncAt!)}',
                              ].join(' · '),
                              style: const TextStyle(fontSize: 12, color: Noct.n500, fontWeight: FontWeight.w400),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 22, 18, 0),
                child: Row(
                  children: [
                    Expanded(child: NoctStat(value: '$_vehicleCount', label: 'Vehicles', valueSize: 20)),
                    _StatDivider(child: NoctStat(value: '$_tripCount', label: 'Trips', valueSize: 20)),
                    _StatDivider(
                      child: NoctStat(value: fmtThousands((_totalDistanceMeters / 1000).round()), suffix: ' km', label: 'Distance', valueSize: 20),
                    ),
                    _StatDivider(child: NoctStat(value: '$_trophyCount', label: 'Trophies', valueSize: 20, valueColor: Noct.a300)),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 22, 18, 0),
                child: NoctPanel(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MonthlyRecapScreen())),
                  child: Row(
                    children: [
                      const Icon(Ph.calendarBlank, size: 18, color: Noct.a300),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Monthly recap', style: TextStyle(fontSize: 13.5, color: Noct.text, fontWeight: FontWeight.w400)),
                            Text(
                              '${fmtMonthName(DateTime.now())} · ${_kmThisMonth.toStringAsFixed(0)} km so far',
                              style: const TextStyle(fontSize: 11, color: Noct.n500),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Ph.caretRight, size: 13, color: Noct.n600),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 24, 18, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'APPEARANCE',
                      style: TextStyle(fontSize: 10, letterSpacing: 1.2, color: Noct.accent, fontWeight: FontWeight.w400),
                    ),
                    _AppearanceBlock(
                      name: 'Record screen',
                      hint: 'What the live ride leads with.',
                      options: const [
                        (RecordVariant.map, 'Map'),
                        (RecordVariant.numbers, 'Numbers'),
                        (RecordVariant.cluster, 'Cluster'),
                      ],
                      value: LayoutPrefs.instance.record,
                      onChanged: LayoutPrefs.instance.setRecord,
                      footnote: LayoutPrefs.instance.record == RecordVariant.cluster ? 'Needs a connected bike' : null,
                    ),
                    _AppearanceBlock(
                      name: 'Trip list',
                      hint: 'Route thumbnails, or a compact log.',
                      options: const [(TripListVariant.cards, 'Route cards'), (TripListVariant.dense, 'Dense log')],
                      value: LayoutPrefs.instance.tripList,
                      onChanged: LayoutPrefs.instance.setTripList,
                    ),
                    _AppearanceBlock(
                      name: 'Trip detail',
                      hint: 'Headline stats, or the full report.',
                      options: const [(TripDetailVariant.grid, 'Stat grid'), (TripDetailVariant.report, 'Report')],
                      value: LayoutPrefs.instance.tripDetail,
                      onChanged: LayoutPrefs.instance.setTripDetail,
                    ),
                    _AppearanceBlock(
                      name: 'Ranks',
                      hint: 'Show a podium above the standings.',
                      options: const [(RanksVariant.bars, 'Bars only'), (RanksVariant.podium, 'With podium')],
                      value: LayoutPrefs.instance.ranks,
                      onChanged: LayoutPrefs.instance.setRanks,
                      isLast: true,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 22, 18, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'PRIVACY & SYNC',
                      style: TextStyle(fontSize: 10, letterSpacing: 1.2, color: Noct.n500, fontWeight: FontWeight.w400),
                    ),
                    if (!guest)
                      _PreferenceRow(
                        title: 'Show me on leaderboards',
                        subtitle: 'Off hides you from ranks and the territory map',
                        trailing: Switch(value: _profile?.leaderboardVisible ?? true, onChanged: _setLeaderboardVisible),
                      ),
                    _PreferenceRow(
                      title: 'Sync now',
                      subtitle: _syncing ? 'Syncing…' : _syncStatusText(),
                      trailing: GestureDetector(
                        onTap: _syncing ? null : _syncNow,
                        child: _syncing
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Noct.n400))
                            : const Icon(Ph.cloudArrowUp, size: 18, color: Noct.n400),
                      ),
                    ),
                    // Debug-only affordance, not in the design handoff's
                    // Account spec — kept reachable now that the old
                    // standalone BLE tab (screens/vehicle_screen.dart) no
                    // longer surfaces it.
                    _PreferenceRow(
                      title: 'Debug logs',
                      subtitle: 'Low-level BLE connection activity',
                      trailing: GestureDetector(
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LogScreen())),
                        child: const Icon(Icons.article_outlined, size: 18, color: Noct.n400),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 24, 18, 0),
                child: Column(
                  children: [
                    if (guest)
                      NoctOutlinedButton(label: 'Sign in', icon: Ph.userCircle, onPressed: _signIn)
                    else
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: _confirmSignOut,
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Noct.divider),
                            foregroundColor: Noct.n300,
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Ph.signOut, size: 15, color: Noct.n300),
                              SizedBox(width: 8),
                              Text('Sign out'),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: _busy ? null : _deleteAccount,
                        style: OutlinedButton.styleFrom(side: const BorderSide(color: Noct.n800), foregroundColor: Noct.n500),
                        child: Text(_busy ? 'Deleting…' : 'Delete account'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _StatDivider extends StatelessWidget {
  const _StatDivider({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.only(left: 14),
        decoration: const BoxDecoration(border: Border(left: BorderSide(color: Noct.n800, width: 1))),
        child: child,
      ),
    );
  }
}

class _AppearanceBlock<T> extends StatelessWidget {
  const _AppearanceBlock({
    required this.name,
    required this.hint,
    required this.options,
    required this.value,
    required this.onChanged,
    this.footnote,
    this.isLast = false,
  });

  final String name;
  final String hint;
  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onChanged;
  final String? footnote;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: isLast ? null : const BoxDecoration(border: Border(bottom: BorderSide(color: Noct.n900, width: 1))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name, style: const TextStyle(fontSize: 13.5, color: Noct.text, fontWeight: FontWeight.w400)),
          const SizedBox(height: 2),
          Text(hint, style: const TextStyle(fontSize: 11, color: Noct.n500)),
          const SizedBox(height: 11),
          NoctSegmentedControl<T>(value: value, onChanged: onChanged, options: options, wrap: true),
          if (footnote != null) ...[
            const SizedBox(height: 6),
            Text(footnote!, style: const TextStyle(fontSize: 10.5, color: Noct.n600)),
          ],
        ],
      ),
    );
  }
}

class _PreferenceRow extends StatelessWidget {
  const _PreferenceRow({required this.title, required this.subtitle, required this.trailing});
  final String title;
  final String subtitle;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Noct.n900, width: 1))),
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 13.5, color: Noct.text, fontWeight: FontWeight.w400)),
                const SizedBox(height: 2),
                Text(subtitle, style: const TextStyle(fontSize: 11, color: Noct.n500)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          trailing,
        ],
      ),
    );
  }
}
