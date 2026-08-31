import 'package:flutter/material.dart';

import '../auth/current_user.dart';
import '../data/data_events.dart';
import '../data/models/trip.dart';
import '../data/models/vehicle.dart';
import '../data/repositories/gamification_repository.dart';
import '../data/repositories/trip_repository.dart';
import '../data/repositories/vehicle_repository.dart';
import '../friends/friends_screen.dart';
import '../theme/app_theme.dart';
import '../theme/date_fmt.dart';
import '../theme/layout_prefs.dart';
import '../theme/ph_icons.dart';
import '../theme/primitives.dart';
import '../trip/recording_controller.dart';
import 'route_thumbnail.dart';
import 'trip_detail_screen.dart';

class TripHistoryScreen extends StatefulWidget {
  const TripHistoryScreen({super.key});

  @override
  State<TripHistoryScreen> createState() => _TripHistoryScreenState();
}

class _TripHistoryScreenState extends State<TripHistoryScreen> {
  List<Trip> _trips = [];
  Map<String, Vehicle> _vehiclesById = {};
  bool _loading = true;
  int _newAreasThisMonth = 0;

  bool _searching = false;
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
    // This screen lives inside HomeShell's Trips tab navigator, mounted
    // for the app's lifetime — reload whenever a trip is started/
    // finished/deleted anywhere. See data/data_events.dart.
    DataEvents.instance.listenable.addListener(_load);
  }

  @override
  void dispose() {
    DataEvents.instance.listenable.removeListener(_load);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final userId = await CurrentUser.instance.id();
    final trips = await TripRepository.instance.listForUser(userId);
    final vehicles = await VehicleRepository.instance.listForUser(userId);
    final now = DateTime.now();
    final newAreas = await GamificationRepository.instance.territoryCellCountInRange(
      userId,
      start: DateTime(now.year, now.month, 1),
      end: now,
    );
    if (!mounted) return;
    setState(() {
      _trips = trips;
      _vehiclesById = {for (final v in vehicles) v.id: v};
      _newAreasThisMonth = newAreas;
      _loading = false;
    });
  }

  String _fmtDuration(int seconds) {
    final d = Duration(seconds: seconds);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.inHours)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
  }

  Future<bool> _confirmDelete(Trip trip) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete trip?'),
        content: Text('This ${trip.distanceKm.toStringAsFixed(2)} km trip will be permanently deleted.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  void _openTrip(Trip trip, Vehicle? vehicle) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => TripDetailScreen(trip: trip, vehicle: vehicle)));
  }

  List<Trip> get _visibleTrips {
    if (_query.trim().isEmpty) return _trips;
    final q = _query.trim().toLowerCase();
    return _trips.where((t) => (_vehiclesById[t.vehicleId]?.name.toLowerCase() ?? '').contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    final tripsThisMonth = _trips.where((t) => !t.startedAt.isBefore(monthStart)).toList();
    final kmThisMonth = tripsThisMonth.fold<double>(0, (sum, t) => sum + t.distanceKm);

    return ListenableBuilder(
      listenable: LayoutPrefs.instance,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: _searching
                ? TextField(
                    controller: _searchController,
                    autofocus: true,
                    style: const TextStyle(fontSize: 17, color: Noct.text),
                    cursorColor: Noct.accent,
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      hintText: 'Find a trip by vehicle',
                      hintStyle: TextStyle(fontSize: 17, color: Noct.n500),
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  )
                : const Text('Trips'),
            actions: [
              IconButton(
                icon: Icon(_searching ? Ph.x : Ph.magnifyingGlass),
                tooltip: _searching ? 'Close search' : 'Search',
                onPressed: () => setState(() {
                  _searching = !_searching;
                  if (!_searching) {
                    _query = '';
                    _searchController.clear();
                  }
                }),
              ),
              IconButton(
                icon: const Icon(Ph.users),
                tooltip: 'Friends',
                onPressed: () =>
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FriendsScreen())),
              ),
            ],
          ),
          body: _loading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: CustomScrollView(
                    slivers: [
                      SliverToBoxAdapter(
                        child: Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(18, 4, 18, 16),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: NoctStat(
                                      value: kmThisMonth.toStringAsFixed(0),
                                      suffix: ' km',
                                      label: 'This month',
                                    ),
                                  ),
                                  Expanded(
                                    child: _SummaryColumn(
                                      child: NoctStat(value: '${tripsThisMonth.length}', label: 'Rides'),
                                    ),
                                  ),
                                  Expanded(
                                    child: _SummaryColumn(
                                      child: NoctStat(
                                        value: '$_newAreasThisMonth',
                                        label: 'New areas',
                                        valueColor: Noct.a300,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const FadingRule(),
                          ],
                        ),
                      ),
                      if (_trips.isEmpty)
                        const SliverFillRemaining(hasScrollBody: false, child: _EmptyTrips())
                      else if (_visibleTrips.isEmpty)
                        const SliverFillRemaining(
                          hasScrollBody: false,
                          child: Center(
                            child: Text('No trips match that search.', style: TextStyle(fontSize: 13, color: Noct.n500)),
                          ),
                        )
                      else if (LayoutPrefs.instance.tripList == TripListVariant.cards)
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                          sliver: SliverList.separated(
                            itemCount: _visibleTrips.length,
                            separatorBuilder: (context, index) => const SizedBox(height: 10),
                            itemBuilder: (context, i) {
                              final trip = _visibleTrips[i];
                              return _RouteCardRow(
                                trip: trip,
                                vehicle: _vehiclesById[trip.vehicleId],
                                fmtDuration: _fmtDuration,
                                onTap: () => _openTrip(trip, _vehiclesById[trip.vehicleId]),
                                onConfirmDelete: () => _confirmDelete(trip),
                                onDelete: () => TripRepository.instance.deleteTrip(trip.id),
                              );
                            },
                          ),
                        )
                      else
                        SliverPadding(
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          sliver: SliverList.builder(
                            itemCount: _visibleTrips.length,
                            itemBuilder: (context, i) {
                              final trip = _visibleTrips[i];
                              return _DenseLogRow(
                                trip: trip,
                                vehicle: _vehiclesById[trip.vehicleId],
                                fmtDuration: _fmtDuration,
                                onTap: () => _openTrip(trip, _vehiclesById[trip.vehicleId]),
                                onConfirmDelete: () => _confirmDelete(trip),
                                onDelete: () => TripRepository.instance.deleteTrip(trip.id),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),
        );
      },
    );
  }
}

class _SummaryColumn extends StatelessWidget {
  const _SummaryColumn({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(left: 14),
      decoration: const BoxDecoration(border: Border(left: BorderSide(color: Noct.n800, width: 1))),
      child: child,
    );
  }
}

class _EmptyTrips extends StatelessWidget {
  const _EmptyTrips();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'No trips recorded yet.',
              style: TextStyle(fontSize: 13, color: Noct.n500),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            NoctOutlinedButton(
              label: 'Start your first ride',
              expand: false,
              onPressed: () => RecordingController.instance.openRecordScreen?.call(),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeleteBackground extends StatelessWidget {
  const _DeleteBackground();

  @override
  Widget build(BuildContext context) {
    final error = Theme.of(context).colorScheme.error;
    return Container(
      decoration: BoxDecoration(color: error, borderRadius: BorderRadius.circular(Noct.rMd)),
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Icon(Ph.trash, color: Theme.of(context).colorScheme.onError),
    );
  }
}

/// Variant A — the default: a route thumbnail, distance/date, the
/// vehicle, and a tag row. Design handoff §1.
class _RouteCardRow extends StatelessWidget {
  const _RouteCardRow({
    required this.trip,
    required this.vehicle,
    required this.fmtDuration,
    required this.onTap,
    required this.onConfirmDelete,
    required this.onDelete,
  });

  final Trip trip;
  final Vehicle? vehicle;
  final String Function(int) fmtDuration;
  final VoidCallback onTap;
  final Future<bool> Function() onConfirmDelete;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final leanDeg = trip.bleMaxLeanDeg ?? trip.phoneLeanMaxDeg;
    return Dismissible(
      key: ValueKey(trip.id),
      direction: DismissDirection.endToStart,
      background: const _DeleteBackground(),
      confirmDismiss: (_) => onConfirmDelete(),
      onDismissed: (_) => onDelete(),
      child: NoctPanel(
        onTap: onTap,
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Container(
                width: 76,
                height: 76,
                color: Noct.canvas,
                child: RouteThumbnail(tripId: trip.id),
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: trip.distanceKm.toStringAsFixed(2), style: Noct.stat(23)),
                            const TextSpan(
                              text: ' km',
                              style: TextStyle(fontSize: 11.5, color: Noct.n500, fontWeight: FontWeight.w400),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      Text(fmtDayMonth(trip.startedAt), style: const TextStyle(fontSize: 11, color: Noct.n500)),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    vehicle?.name ?? 'Unknown vehicle',
                    style: const TextStyle(fontSize: 11.5, color: Noct.n400),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      NoctTagChip(fmtDuration(trip.durationSeconds)),
                      if (trip.avgSpeedKph != null) NoctTagChip('ø ${trip.avgSpeedKph!.toStringAsFixed(0)} km/h'),
                      if (leanDeg != null) NoctTagChip('${leanDeg.toStringAsFixed(0)}° lean', accent: true),
                      if (!trip.isFinished) const NoctTagChip('In progress', accent: true),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Variant B — no card, a compact scannable log. Design handoff §1.
class _DenseLogRow extends StatelessWidget {
  const _DenseLogRow({
    required this.trip,
    required this.vehicle,
    required this.fmtDuration,
    required this.onTap,
    required this.onConfirmDelete,
    required this.onDelete,
  });

  final Trip trip;
  final Vehicle? vehicle;
  final String Function(int) fmtDuration;
  final VoidCallback onTap;
  final Future<bool> Function() onConfirmDelete;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey(trip.id),
      direction: DismissDirection.endToStart,
      background: const _DeleteBackground(),
      confirmDismiss: (_) => onConfirmDelete(),
      onDismissed: (_) => onDelete(),
      child: InkWell(
        onTap: onTap,
        overlayColor: WidgetStatePropertyAll(Noct.accent.withValues(alpha: 0.05)),
        child: Container(
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Noct.n900, width: 1))),
          padding: const EdgeInsets.symmetric(vertical: 15),
          child: Row(
            children: [
              SizedBox(
                width: 38,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${trip.startedAt.day}', style: Noct.stat(17)),
                    Text(
                      monthAbbrev(trip.startedAt.month).toUpperCase(),
                      style: const TextStyle(fontSize: 9.5, letterSpacing: 1.0, color: Noct.n500),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: trip.distanceKm.toStringAsFixed(1), style: Noct.stat(18)),
                          const TextSpan(
                            text: ' km',
                            style: TextStyle(fontSize: 11, color: Noct.n500, fontWeight: FontWeight.w400),
                          ),
                          TextSpan(
                            text: trip.isFinished ? ' · ${fmtDuration(trip.durationSeconds)}' : ' · live',
                            style: const TextStyle(fontSize: 11, color: Noct.n600, fontWeight: FontWeight.w400),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      vehicle?.name ?? 'Unknown vehicle',
                      style: const TextStyle(fontSize: 11.5, color: Noct.n500),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 34,
                height: 34,
                child: RouteThumbnail(tripId: trip.id, strokeWidth: 4, color: Noct.a400, opacity: 0.8, inset: 4),
              ),
              const SizedBox(width: 8),
              const Icon(Ph.caretRight, size: 14, color: Noct.n600),
            ],
          ),
        ),
      ),
    );
  }
}
