import 'package:flutter_test/flutter_test.dart';
import 'package:quakenet/core/utils/circular_buffer.dart';

void main() {
  group('CircularBuffer', () {
    test('adds items and keeps count', () {
      final buffer = CircularBuffer<int>(3);
      buffer.add(1);
      buffer.add(2);
      expect(buffer.length, 2);
      expect(buffer.toList(), [1, 2]);
    });

    test('drops oldest items when capacity is reached', () {
      final buffer = CircularBuffer<int>(3);
      buffer.add(1);
      buffer.add(2);
      buffer.add(3);
      buffer.add(4); // Should drop 1

      expect(buffer.length, 3);
      expect(buffer.toList(), [2, 3, 4]);
    });

    test('clears items', () {
      final buffer = CircularBuffer<int>(3);
      buffer.add(1);
      buffer.clear();
      expect(buffer.length, 0);
      expect(buffer.isEmpty, true);
    });
  });
}
