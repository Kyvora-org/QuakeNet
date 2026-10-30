import 'package:flutter_test/flutter_test.dart';
import 'package:quakenet/core/algorithms/sta_lta.dart';

void main() {
  group('StaLta', () {
    test('does not trigger on constant low noise', () {
      final detector = StaLta(
        staSamples: 50, // 1 second at 50Hz
        ltaSamples: 500, // 10 seconds at 50Hz
        triggerThreshold: 4.0,
      );

      bool triggered = false;
      // Feed constant small noise
      for (int i = 0; i < 600; i++) {
        final result = detector.process(0.01);
        if (result.isTriggered) triggered = true;
      }

      expect(triggered, false);
    });

    test('triggers on sudden energy spike', () {
      final detector = StaLta(
        staSamples: 50,
        ltaSamples: 500,
        triggerThreshold: 4.0,
      );

      // 1. Establish background noise (LTA)
      for (int i = 0; i < 500; i++) {
        detector.process(0.01);
      }

      // 2. Introduce a sudden spike
      bool triggered = false;
      for (int i = 0; i < 10; i++) {
        final result = detector.process(0.5); // 50x the noise amplitude
        if (result.isTriggered) triggered = true;
      }

      expect(triggered, true);
    });
  });
}
