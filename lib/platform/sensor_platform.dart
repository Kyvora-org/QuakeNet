import '../models/sensor_sample.dart';

/// Abstract interface for a sensor platform implementation.
abstract class SensorPlatform {
  /// Stream of raw sensor samples.
  Stream<SensorSample> get accelerometerStream;

  /// Starts the sensor with the requested sampling rate (in Hz).
  Future<void> startSensor(int requestedSamplingRate);

  /// Stops the sensor updates.
  Future<void> stopSensor();

  /// Gets the current status of the sensor (e.g. active, inactive, unavailable).
  Future<String> getSensorStatus();
}
