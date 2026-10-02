import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opentrip_mobile/data/models/trip.dart';
import 'package:opentrip_mobile/data/models/trip_point.dart';
import 'package:opentrip_mobile/trips/stat_card_screen.dart';
import 'package:opentrip_mobile/crew/crew_navigation_screen.dart';

void main() {
  final points = [
    for (var i = 0; i < 120; i++)
      TripPoint(
        tripId: 't',
        seq: i,
        latitude: -34.6 + i * 0.0002,
        longitude: -58.4 + math.sin(i / 10) * 0.002,
        speedKph: 40 + 30 * math.sin(i / 7).abs(),
        phoneLeanDeg: 35 * math.sin(i / 10).abs(),
        timestamp: DateTime(2026, 1, 1).add(Duration(seconds: i * 2)),
      ),
  ];
  final trip = Trip(
      id: 't',
      userId: 'u',
      vehicleId: 'v',
      startedAt: DateTime(2026, 1, 1),
      distanceMeters: 12345,
      durationSeconds: 900,
      avgSpeedKph: 50,
      maxSpeedKph: 92,
      phoneLeanMaxDeg: 41);

  testWidgets('every share template renders', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    await tester.pumpWidget(MaterialApp(home: StatCardScreen(trip: trip, vehicle: null, points: points)));
    for (final name in ['Route', 'Lean', 'Story', 'Classic']) {
      await tester.tap(find.text(name));
      await tester.pump();
      expect(tester.takeException(), isNull, reason: name);
    }
    addTearDown(tester.view.reset);
  });

  testWidgets('crew marker renders', (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Center(
            child: SizedBox(width: 130, height: 54, child: CrewMarker(name: 'Ana', speedKph: 88, leanDeg: 30)))));
    expect(find.text('Ana · 88 km/h · 30°'), findsOneWidget);
  });
}
