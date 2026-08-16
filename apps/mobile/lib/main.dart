import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'logging/log_buffer.dart';
import 'screens/vehicle_screen.dart';

void main() {
  // Capture every print() in the app — including flutter_blue_plus's own
  // verbose BLE-stack logging below — into logBuffer, in addition to the
  // normal console output. This is what makes the in-app Logs screen show
  // low-level connection/GATT activity, not just our own log lines.
  runZonedGuarded(
    () {
      FlutterBluePlus.setLogLevel(LogLevel.verbose, color: false);
      runApp(const OpenTripApp());
    },
    (error, stack) => logBuffer.add('UNCAUGHT ERROR: $error\n$stack'),
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) {
        parent.print(zone, line);
        logBuffer.add(line);
      },
    ),
  );
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
