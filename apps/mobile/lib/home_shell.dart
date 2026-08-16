import 'package:flutter/material.dart';

import 'auth/auth_service.dart';
import 'auth/current_user.dart';
import 'auth/login_screen.dart';
import 'screens/vehicle_screen.dart';
import 'trip/recording_screen.dart';
import 'trips/trip_history_screen.dart';
import 'vehicles/vehicle_list_screen.dart';

/// Post-login (or post-guest) shell. Tabs: trip history, recording,
/// vehicle management, the Kawasaki BLE telemetry demo, and account.
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

class _AccountTab extends StatefulWidget {
  const _AccountTab();

  @override
  State<_AccountTab> createState() => _AccountTabState();
}

class _AccountTabState extends State<_AccountTab> {
  Future<void> _signIn() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LoginScreen(onContinueAsGuest: () => Navigator.of(context).pop()),
      ),
    );
    if (mounted) setState(() {}); // reflect a sign-in that happened on the pushed screen
  }

  @override
  Widget build(BuildContext context) {
    final guest = CurrentUser.instance.isGuest;
    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(guest ? 'Status' : 'Signed in as', style: Theme.of(context).textTheme.labelMedium),
            Text(CurrentUser.instance.displayLabel, style: Theme.of(context).textTheme.titleMedium),
            if (guest) ...[
              const SizedBox(height: 4),
              const Text(
                'Vehicles and trips on this device won\'t follow you to another '
                'device until you sign in.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
            const SizedBox(height: 24),
            if (guest)
              OutlinedButton.icon(
                onPressed: _signIn,
                icon: const Icon(Icons.login),
                label: const Text('Sign in'),
              )
            else
              OutlinedButton.icon(
                onPressed: () async {
                  await AuthService.instance.signOut();
                  if (mounted) setState(() {});
                },
                icon: const Icon(Icons.logout),
                label: const Text('Sign out'),
              ),
          ],
        ),
      ),
    );
  }
}
