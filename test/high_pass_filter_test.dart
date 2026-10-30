import 'package:flutter_test/flutter_test.dart';
import 'package:quakenet/core/dsp/high_pass_filter.dart';

void main() {
  group('HighPassFilter', () {
    test('filters out constant static signals like gravity', () {
      // High pass filter designed for 50Hz and 0.5Hz cutoff
      final filter = HighPassFilter.fromCutoff(50.0, 0.5);
      
      // Send a constant 9.8m/s^2 acceleration (gravity)
      for (int i = 0; i < 100; i++) {
        filter.process(0, 0, 9.8);
      }
      
      // After 100 samples (2 seconds), the output should be close to 0
      final result = filter.process(0, 0, 9.8);
      
      expect(result[0], closeTo(0.0, 0.1));
      expect(result[1], closeTo(0.0, 0.1));
      expect(result[2], closeTo(0.0, 0.1));
    });

    test('preserves high frequency dynamic signals', () {
      final filter = HighPassFilter.fromCutoff(50.0, 0.5);
      
      // Stabilize the filter
      for (int i = 0; i < 100; i++) {
        filter.process(0, 0, 9.8);
      }
      
      // Introduce a sudden spike (e.g. an earthquake shock)
      final result = filter.process(0, 0, 15.0);
      
      // The sudden change (15 - 9.8 = 5.2) should be mostly preserved
      expect(result[2], greaterThan(4.0));
    });
  });
}
