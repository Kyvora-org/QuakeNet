import 'dart:math';

/// Represents a single reading from the device accelerometer.
class SensorSample {
  /// System timestamp when the sample was received in Flutter.
  final DateTime timestamp;

  /// Relative timestamp provided by the native sensor.
  final double sensorTimestamp;

  /// Accelerometer X-axis value (G-force).
  final double x;

  /// Accelerometer Y-axis value (G-force).
  final double y;

  /// Accelerometer Z-axis value (G-force).
  final double z;

  /// Calculated magnitude: sqrt(x² + y² + z²).
  final double magnitude;

  /// Estimated time between this sample and the previous one (in seconds).
  final double samplingInterval;

  /// Platform from which this sample originated ('iOS' or 'Android').
  final String devicePlatform;

  /// Optional session identifier to group samples.
  final String? sessionId;

  SensorSample({
    required this.timestamp,
    required this.sensorTimestamp,
    required this.x,
    required this.y,
    required this.z,
    required this.samplingInterval,
    required this.devicePlatform,
    this.sessionId,
  }) : magnitude = sqrt(x * x + y * y + z * z);

  factory SensorSample.fromMap(Map<String, dynamic> map, String platform, {String? sessionId}) {
    final double x = map['x'] as double;
    final double y = map['y'] as double;
    final double z = map['z'] as double;
    return SensorSample(
      timestamp: DateTime.now(),
      sensorTimestamp: map['sensorTimestamp'] as double,
      x: x,
      y: y,
      z: z,
      samplingInterval: map['samplingInterval'] as double,
      devicePlatform: platform,
      sessionId: sessionId,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'sensorTimestamp': sensorTimestamp,
      'x': x,
      'y': y,
      'z': z,
      'magnitude': magnitude,
      'samplingInterval': samplingInterval,
      'devicePlatform': devicePlatform,
      'sessionId': sessionId,
    };
  }
}
