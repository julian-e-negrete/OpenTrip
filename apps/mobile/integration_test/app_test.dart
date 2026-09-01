// Runs on a real device/emulator (flutter test integration_test/app_test.dart
// -d <device>), not the plain `flutter test` unit/widget suite under test/.
//
// Boots the real app (not just a screen in isolation) with no
// --dart-define values, same as a local `flutter run` — that makes
// AppConfig.isSupabaseConfigured false, so the guest path is always
// reachable and this test needs no backend, same guarantee
// auth/current_user.dart's own doc comment describes for on-device
// testing generally.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:opentrip_mobile/main.dart';
import 'package:opentrip_mobile/theme/ph_icons.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('guest can reach every tab and open Record', (tester) async {
    await tester.pumpWidget(const OpenTripApp());
    await tester.pumpAndSettle();

    // Login screen (no Supabase config in a plain test run) -> guest.
    expect(find.text('Continue without an account'), findsOneWidget);
    await tester.tap(find.text('Continue without an account'));
    await tester.pumpAndSettle();

    // Trips tab is the shell's default.
    expect(find.text('Trips'), findsWidgets);

    // Each of the other three tabs renders without throwing.
    for (final icon in [Ph.ranking, Ph.hexagon, Ph.motorcycle]) {
      await tester.tap(find.byIcon(icon));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }

    // The raised record control: first tap opens Record (idle state);
    // this is the interaction the redesign's "record does not work"
    // regression came from — a widget test can't tell us whether it's
    // *discoverable*, but it can guarantee the screen actually opens and
    // shows a real, tappable start control rather than nothing.
    await tester.tap(find.byIcon(Ph.path)); // back to the Trips tab group first
    await tester.pumpAndSettle();

    final recordControl = find.byKey(const Key('raisedRecordControl'));
    expect(recordControl, findsOneWidget);
    await tester.tap(recordControl);
    await tester.pumpAndSettle();

    expect(find.text('Start recording'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
