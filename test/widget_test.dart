import 'package:flutter_test/flutter_test.dart';
import 'package:kizuna_veda/app/app.dart';

void main() {
  testWidgets('Kizuna Veda app loads login screen smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const KizunaVedaApp());
    await tester.pumpAndSettle();

    // Verify that the Kizuna Veda header and login form are rendered.
    expect(find.text('KIZUNA VEDA'), findsOneWidget);
    expect(find.text('Sign In to Enterprise Portal'), findsOneWidget);
  });
}
