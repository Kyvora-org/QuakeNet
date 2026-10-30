import 'package:flutter_test/flutter_test.dart';
import 'package:quakenet/services/recording_service.dart';
import 'package:quakenet/models/sensor_sample.dart';

void main() {
  group('RecordingService', () {
    test('starts and stops recording correctly', () async {
      final service = RecordingService();
      expect(service.isRecording, false);

      service.startRecording();
      expect(service.isRecording, true);

      final sample = SensorSample(
        timestamp: DateTime.now(),
        sensorTimestamp: 1000,
        x: 1.0,
        y: 2.0,
        z: 3.0,
        samplingInterval: 0.02,
        devicePlatform: 'test',
      );

      service.addSample(sample);

      final session = await service.stopRecording('TestDevice', 'TestPlatform', 50, 48.5);
      expect(service.isRecording, false);
      
      expect(session, isNotNull);
      expect(session!.samples.length, 1);
      expect(session.samples.first.x, 1.0);
    });
  });
}
