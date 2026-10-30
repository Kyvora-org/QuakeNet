import 'package:flutter/services.dart';
import '../models/sensor_sample.dart';
import 'sensor_platform.dart';

class AndroidSensorPlatform implements SensorPlatform {
  static const MethodChannel _methodChannel = MethodChannel('com.quakenet.sensor/methods');
  static const EventChannel _eventChannel = EventChannel('com.quakenet.sensor/events');

  Stream<SensorSample>? _accelerometerStream;

  @override
  Stream<SensorSample> get accelerometerStream {
    _accelerometerStream ??= _eventChannel
        .receiveBroadcastStream()
        .map((dynamic event) {
          final Map<String, dynamic> data = Map<String, dynamic>.from(event);
          return SensorSample.fromMap(data, 'Android');
        });
    return _accelerometerStream!;
  }

  @override
  Future<void> startSensor(int requestedSamplingRate) async {
    await _methodChannel.invokeMethod('startSensor', {
      'samplingRate': requestedSamplingRate,
    });
  }

  @override
  Future<void> stopSensor() async {
    await _methodChannel.invokeMethod('stopSensor');
  }

  @override
  Future<String> getSensorStatus() async {
    final String status = await _methodChannel.invokeMethod('getSensorStatus');
    return status;
  }
}
