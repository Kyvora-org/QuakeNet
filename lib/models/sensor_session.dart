import 'sensor_sample.dart';

class SensorSession {
  final String sessionId;
  final String device;
  final String platform;
  final DateTime startTime;
  final DateTime endTime;
  final int requestedSamplingRate;
  final double actualSamplingRate;
  final List<SensorSample> samples;

  SensorSession({
    required this.sessionId,
    required this.device,
    required this.platform,
    required this.startTime,
    required this.endTime,
    required this.requestedSamplingRate,
    required this.actualSamplingRate,
    required this.samples,
  });

  Map<String, dynamic> toMap() {
    return {
      'sessionId': sessionId,
      'device': device,
      'platform': platform,
      'startTime': startTime.toIso8601String(),
      'endTime': endTime.toIso8601String(),
      'requestedSamplingRate': requestedSamplingRate,
      'actualSamplingRate': actualSamplingRate,
      'samples': samples.map((s) => s.toMap()).toList(),
    };
  }
}
