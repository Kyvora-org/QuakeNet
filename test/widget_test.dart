import 'package:flutter_test/flutter_test.dart';
import 'package:quakenet/main.dart';

void main() {
  testWidgets('App loads smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const QuakeNetApp());

    // Verify that the title is present.
    expect(find.text('QuakeNet'), findsOneWidget);
  });
}
