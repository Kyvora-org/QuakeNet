import 'package:flutter_test/flutter_test.dart';
import 'package:quakenet/main.dart';
import 'package:quakenet/models/device_node.dart';

void main() {
  testWidgets('App loads smoke test', (WidgetTester tester) async {
    final dummyNode = DeviceNode(
      nodeId: 'test-node-1234',
      sessionId: 'test-session-5678',
      platform: 'android',
      createdAt: DateTime.utc(2026, 1, 1),
      sensorCapabilities: const {'accelerometer': true},
    );

    // Build our app and trigger a frame.
    await tester.pumpWidget(QuakeNetApp(deviceNode: dummyNode));

    // Verify that the title is present.
    expect(find.text('QUAKENET'), findsOneWidget);
  });
}
