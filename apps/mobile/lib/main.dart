import 'package:flutter/material.dart';

import 'screens/vehicle_screen.dart';

void main() {
  runApp(const OpenTripApp());
}

class OpenTripApp extends StatelessWidget {
  const OpenTripApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OpenTrip',
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true, brightness: Brightness.dark),
      // This app is currently just the vehicle-connector demo slice — see
      // /docs/ROADMAP.md. GPS trip recording, maps, and leaderboards are
      // not wired up yet, so the vehicle screen is the whole app for now.
      home: const VehicleScreen(),
    );
  }
}
