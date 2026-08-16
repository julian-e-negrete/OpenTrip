import 'package:flutter/material.dart';

import 'auth/auth_service.dart';
import 'screens/vehicle_screen.dart';
import 'trip/recording_screen.dart';
import 'trips/trip_history_screen.dart';
import 'vehicles/vehicle_list_screen.dart';

/// Post-login shell. Tabs: trip history, recording, vehicle management,
/// the existing Kawasaki BLE telemetry demo, and account/sign-out.
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
    _AccountTab(),
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
          NavigationDestination(icon: Icon(Icons.person_outline), label: 'Account'),
        ],
      ),
    );
  }
}

class _AccountTab extends StatelessWidget {
  const _AccountTab();

  @override
  Widget build(BuildContext context) {
    final user = AuthService.instance.currentUser;
    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Signed in as', style: Theme.of(context).textTheme.labelMedium),
            Text(user?.email ?? user?.id ?? 'unknown', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: () => AuthService.instance.signOut(),
              icon: const Icon(Icons.logout),
              label: const Text('Sign out'),
            ),
          ],
        ),
      ),
    );
  }
}
