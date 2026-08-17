import 'package:flutter/material.dart';

import 'account/account_screen.dart';
import 'gamification/territory_map_screen.dart';
import 'screens/vehicle_screen.dart';
import 'trip/recording_screen.dart';
import 'trips/trip_history_screen.dart';
import 'vehicles/vehicle_list_screen.dart';

/// Post-login (or post-guest) shell. Tabs: trip history, recording,
/// vehicle management, the Kawasaki BLE telemetry demo, the global/
/// friends territory map, and account.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _pages = [
    TripHistoryScreen(),
    RecordingScreen(),
    VehicleListScreen(),
    VehicleScreen(),
    TerritoryMapScreen(),
    AccountScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.route_outlined), label: 'Trips'),
          NavigationDestination(icon: Icon(Icons.fiber_manual_record_outlined), label: 'Record'),
          NavigationDestination(icon: Icon(Icons.two_wheeler_outlined), label: 'Vehicles'),
          NavigationDestination(icon: Icon(Icons.bluetooth), label: 'BLE'),
          NavigationDestination(icon: Icon(Icons.map_outlined), label: 'Map'),
          NavigationDestination(icon: Icon(Icons.person_outline), label: 'Account'),
        ],
      ),
    );
  }
}
