import 'package:flutter_test/flutter_test.dart';
import 'package:opentrip_mobile/main.dart';

void main() {
  testWidgets('app shows the setup screen when Supabase is not configured', (WidgetTester tester) async {
    // No --dart-define supplied in tests, so AppConfig.isSupabaseConfigured
    // is false — this is the defensive fallback path (see
    // auth/supabase_not_configured_screen.dart) that should show explicit
    // setup instructions instead of crashing or showing a blank screen.
    await tester.pumpWidget(const OpenTripApp());
    await tester.pump();

    expect(find.text('Login isn\'t configured yet'), findsOneWidget);
  });
}
