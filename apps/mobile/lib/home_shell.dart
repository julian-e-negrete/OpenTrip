import 'package:flutter/material.dart';

import 'gamification/territory_map_screen.dart';
import 'leaderboard/leaderboard_screen.dart';
import 'theme/app_theme.dart';
import 'theme/ph_icons.dart';
import 'trip/recording_controller.dart';
import 'trip/recording_screen.dart';
import 'trips/trip_history_screen.dart';
import 'vehicles/vehicle_list_screen.dart';

enum _Tab { trips, ranks, map, garage }

/// Post-login (or post-guest) shell.
///
/// Four bottom destinations, each its own [Navigator] with an independent
/// stack — pushing a child screen (trip detail, friends, vehicle detail,
/// account, ...) from within a tab keeps that tab lit, for free, because
/// `Navigator.of(context)` inside those screens resolves to the tab's own
/// nested Navigator rather than this shell's. See the design handoff's
/// "Tab-group highlighting" section.
///
/// Record isn't a fifth tab — it's a raised control on the bar itself
/// (see [_RaisedRecordControl]) that shows [RecordingScreen] as an overlay
/// above the current tab, with the bar (and the control's own idle/
/// recording glyph) staying visible the whole time.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  _Tab _tab = _Tab.trips;
  bool _showingRecord = false;

  final _navigatorKeys = {
    _Tab.trips: GlobalKey<NavigatorState>(),
    _Tab.ranks: GlobalKey<NavigatorState>(),
    _Tab.map: GlobalKey<NavigatorState>(),
    _Tab.garage: GlobalKey<NavigatorState>(),
  };

  static const _roots = {
    _Tab.trips: TripHistoryScreen(),
    _Tab.ranks: LeaderboardScreen(),
    _Tab.map: TerritoryMapScreen(),
    _Tab.garage: VehicleListScreen(),
  };

  void _selectTab(_Tab tab) {
    setState(() => _showingRecord = false);
    if (tab == _tab) {
      // Tapping the already-active tab returns it to its root screen.
      _navigatorKeys[tab]!.currentState?.popUntil((route) => route.isFirst);
      return;
    }
    setState(() => _tab = tab);
  }

  void _toggleRecord() => setState(() => _showingRecord = !_showingRecord);

  Widget _buildTabNavigator(_Tab tab) {
    return Navigator(
      key: _navigatorKeys[tab],
      onGenerateRoute: (settings) => MaterialPageRoute(builder: (_) => _roots[tab]!),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_showingRecord,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _showingRecord) setState(() => _showingRecord = false);
      },
      child: Scaffold(
        body: Stack(
          children: [
            IndexedStack(
              index: _Tab.values.indexOf(_tab),
              children: [for (final tab in _Tab.values) _buildTabNavigator(tab)],
            ),
            if (_showingRecord) const RecordingScreen(),
          ],
        ),
        bottomNavigationBar: _NocturneBottomBar(
          activeTab: _tab,
          onSelectTab: _selectTab,
          onTapRecord: _toggleRecord,
        ),
      ),
    );
  }
}

class _NocturneBottomBar extends StatelessWidget {
  const _NocturneBottomBar({
    required this.activeTab,
    required this.onSelectTab,
    required this.onTapRecord,
  });

  final _Tab activeTab;
  final ValueChanged<_Tab> onSelectTab;
  final VoidCallback onTapRecord;

  static const _destinations = {
    _Tab.trips: (icon: Ph.path, label: 'Trips'),
    _Tab.ranks: (icon: Ph.ranking, label: 'Ranks'),
    _Tab.map: (icon: Ph.hexagon, label: 'Map'),
    _Tab.garage: (icon: Ph.motorcycle, label: 'Garage'),
  };

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 62 + MediaQuery.of(context).padding.bottom,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            decoration: const BoxDecoration(
              color: Noct.surface,
              border: Border(top: BorderSide(color: Noct.n800, width: 1)),
            ),
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
            child: SizedBox(
              height: 62,
              child: Row(
                children: [
                  _destination(_Tab.trips),
                  _destination(_Tab.ranks),
                  const SizedBox(width: 60),
                  _destination(_Tab.map),
                  _destination(_Tab.garage),
                ],
              ),
            ),
          ),
          Positioned(
            top: -24,
            left: 0,
            right: 0,
            child: Center(
              child: _RaisedRecordControl(onTap: onTapRecord),
            ),
          ),
        ],
      ),
    );
  }

  Widget _destination(_Tab tab) {
    final d = _destinations[tab]!;
    final active = tab == activeTab;
    final color = active ? Noct.accent : Noct.n500;
    return Expanded(
      child: InkWell(
        onTap: () => onSelectTab(tab),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 150),
              style: TextStyle(color: color),
              child: Icon(d.icon, size: 20, color: color),
            ),
            const SizedBox(height: 3),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 150),
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w400, color: color),
              child: Text(d.label),
            ),
          ],
        ),
      ),
    );
  }
}

/// The 60px raised circle centred on the bottom bar. Idle: a plain accent
/// circle. Recording: an accent square (the "stop" affordance) with an
/// infinite pulsing ring, per the handoff's Shell & navigation spec.
class _RaisedRecordControl extends StatefulWidget {
  const _RaisedRecordControl({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_RaisedRecordControl> createState() => _RaisedRecordControlState();
}

class _RaisedRecordControlState extends State<_RaisedRecordControl>
    with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );

  @override
  void initState() {
    super.initState();
    RecordingController.instance.isRecording.addListener(_syncPulse);
    _syncPulse();
  }

  void _syncPulse() {
    if (RecordingController.instance.isRecording.value) {
      _pulse.repeat();
    } else {
      _pulse.stop();
      _pulse.reset();
    }
  }

  @override
  void dispose() {
    RecordingController.instance.isRecording.removeListener(_syncPulse);
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Noct.bg,
          border: Border.all(color: Noct.accent, width: 1.5),
          boxShadow: [BoxShadow(color: Noct.accent.withValues(alpha: 0.35), blurRadius: 22)],
        ),
        child: ValueListenableBuilder<bool>(
          valueListenable: RecordingController.instance.isRecording,
          builder: (context, recording, _) {
            return Stack(
              alignment: Alignment.center,
              children: [
                AnimatedBuilder(
                  animation: _pulse,
                  builder: (context, _) {
                    if (!recording) return const SizedBox.shrink();
                    final t = Curves.easeOut.transform(_pulse.value);
                    return Opacity(
                      opacity: (0.45 * (1 - t)).clamp(0.0, 1.0),
                      child: Transform.scale(
                        scale: 1.0 + 0.35 * t,
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.fromBorderSide(BorderSide(color: Noct.accent, width: 1.5)),
                          ),
                        ),
                      ),
                    );
                  },
                ),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 150),
                  child: recording
                      ? Container(
                          key: const ValueKey('square'),
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: Noct.accent,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        )
                      : Container(
                          key: const ValueKey('circle'),
                          width: 26,
                          height: 26,
                          decoration: const BoxDecoration(color: Noct.accent, shape: BoxShape.circle),
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
