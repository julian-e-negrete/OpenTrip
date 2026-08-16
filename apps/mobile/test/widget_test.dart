import 'package:flutter_test/flutter_test.dart';
import 'package:opentrip_mobile/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    // auth/current_user.dart reads/writes a guest id via shared_preferences;
    // without a mocked backend the plugin's method channel just hangs
    // waiting for a platform reply that never arrives in a widget test.
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('unconfigured build still shows a usable login screen with a guest option', (
    WidgetTester tester,
  ) async {
    // No --dart-define supplied in tests, so AppConfig.isSupabaseConfigured
    // is false. The app should degrade gracefully — showing a notice about
    // login instead of crashing — while still offering a way in.
    //
    // Tapping "Continue without an account" is intentionally not exercised
    // here: it navigates into HomeShell, which immediately touches sqflite
    // and geolocator platform channels that only exist on a real device —
    // that path is covered by manual/on-device testing instead, not a
    // host-side widget test.
    await tester.pumpWidget(const OpenTripApp());
    await tester.pump();

    expect(find.textContaining('isn\'t configured'), findsOneWidget);
    expect(find.text('Continue without an account'), findsOneWidget);
  });
}
