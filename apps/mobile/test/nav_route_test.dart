import 'package:flutter_test/flutter_test.dart';
import 'package:opentrip_mobile/crew/nav_route.dart';

Map<String, dynamic> _step(String type, String? modifier, String name, double lon, double lat, double distance) => {
      'name': name,
      'distance': distance,
      'maneuver': {
        'type': type,
        'modifier': modifier,
        'location': [lon, lat]
      },
    };

/// A straight east-bound road, then a left turn north.
final _osrm = {
  'code': 'Ok',
  'routes': [
    {
      'distance': 300.0,
      'duration': 40.0,
      'geometry': {
        'coordinates': [
          [0.0, 0.0],
          [0.001, 0.0],
          [0.002, 0.0],
          [0.002, 0.001],
        ],
      },
      'legs': [
        {
          'steps': [
            _step('depart', null, 'Main St', 0, 0, 220),
            _step('turn', 'left', 'Oak Ave', 0.002, 0, 110),
            _step('arrive', null, '', 0.002, 0.001, 0),
          ],
        },
      ],
    },
  ],
};

void main() {
  test('parses OSRM geometry as lat/lon and reads steps', () {
    final route = NavRoute.fromOsrmJson(_osrm)!;
    expect(route.geometry.first, (0.0, 0.0));
    expect(route.geometry.last, (0.001, 0.002));
    expect(route.steps.length, 3);
    expect(route.steps[1].instruction, 'Turn left onto Oak Ave');
    expect(route.steps.last.instruction, 'Arrive at your crewmate');
  });

  test('no route yields null', () {
    expect(NavRoute.fromOsrmJson({'code': 'NoRoute', 'routes': []}), isNull);
  });

  test('next step is the turn ahead, then arrival once past it', () {
    final route = NavRoute.fromOsrmJson(_osrm)!;
    final atStart = navProgress(route, (0.0, 0.0));
    expect(atStart.nextStepIndex, 1);
    expect(atStart.metersToNextStep, closeTo(222, 3));
    expect(atStart.metersOffRoute, closeTo(0, 0.1));

    final pastTurn = navProgress(route, (0.0005, 0.002));
    expect(pastTurn.nextStepIndex, 2);
  });

  test('reports distance off the route line', () {
    final route = NavRoute.fromOsrmJson(_osrm)!;
    expect(navProgress(route, (0.001, 0.001)).metersOffRoute, greaterThan(100));
  });

  test('instruction wording for roundabouts and u-turns', () {
    const r = NavStep(
        type: 'roundabout', modifier: 'right', name: 'Ruta 8', exit: 2, latitude: 0, longitude: 0, distanceMeters: 0);
    expect(r.instruction, 'At the roundabout, take exit 2 onto Ruta 8');
    const u = NavStep(
        type: 'continue', modifier: 'uturn', name: '', exit: null, latitude: 0, longitude: 0, distanceMeters: 0);
    expect(u.instruction, 'Make a U-turn');
  });
}
