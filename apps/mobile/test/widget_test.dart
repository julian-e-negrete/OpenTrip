import 'package:flutter_test/flutter_test.dart';

import 'package:opentrip_mobile/main.dart';

void main() {
  testWidgets('app boots to the vehicle screen', (WidgetTester tester) async {
    await tester.pumpWidget(const OpenTripApp());
    await tester.pump();

    expect(find.text('Vehicle'), findsOneWidget);
    expect(find.text('Scan & connect'), findsOneWidget);
  });
}
