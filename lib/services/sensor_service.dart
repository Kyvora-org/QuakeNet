import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/sensor_sample.dart';
import '../platform/sensor_platform.dart';
import '../core/utils/circular_buffer.dart';
import 'recording_service.dart';
import 'processing_service.dart';

enum SensorStatus {
  inactive,
  active,
  error,
}

class SensorService extends ChangeNotifier {
  final SensorPlatform _platform;
  final RecordingService? _recordingService;
  final ProcessingService? _processingService;

  SensorService(
    this._platform, {
    RecordingService? recordingService,
    ProcessingService? processingService,
  })  : _recordingService = recordingService,
        _processingService = processingService;

  SensorStatus _status = SensorStatus.inactive;
  SensorStatus get status => _status;

  int _requestedRate = 50;
  int get requestedRate => _requestedRate;

  double _actualRate = 0.0;
  double get actualRate => _actualRate;

  int _sampleCount = 0;
  int get sampleCount => _sampleCount;

  DateTime? _sessionStartTime;
  Duration get sessionDuration => _sessionStartTime != null 
      ? DateTime.now().difference(_sessionStartTime!) 
      : Duration.zero;

  SensorSample? _latestSample;
  SensorSample? get latestSample => _latestSample;

  // Circular buffer to keep the last 500 samples (10 seconds at 50Hz) for visualization
  final CircularBuffer<SensorSample> _buffer = CircularBuffer<SensorSample>(500);
  List<SensorSample> get bufferedSamples => _buffer.toList();

  StreamSubscription<SensorSample>? _subscription;

  Future<void> startMonitoring({int rate = 50}) async {
    if (_status == SensorStatus.active) return;
    
    _requestedRate = rate;
    _sampleCount = 0;
    _actualRate = 0.0;
    _sessionStartTime = DateTime.now();
    _buffer.clear();
    _processingService?.updateSampleRate(rate.toDouble());

    try {
      await _platform.startSensor(rate);
      _status = SensorStatus.active;
      notifyListeners();

      _subscription = _platform.accelerometerStream.listen(
        (sample) {
          _sampleCount++;
          _latestSample = sample;
          _buffer.add(sample);
          
          _recordingService?.addSample(sample);
          _processingService?.processSample(sample);
          
          // Calculate actual rate periodically or continuously
          final duration = sessionDuration;
          if (duration.inMilliseconds > 0) {
            _actualRate = _sampleCount / (duration.inMilliseconds / 1000.0);
          }

          notifyListeners();
        },
        onError: (error) {
          _status = SensorStatus.error;
          notifyListeners();
          stopMonitoring();
        },
      );
    } catch (e) {
      _status = SensorStatus.error;
      notifyListeners();
    }
  }

  Future<void> stopMonitoring() async {
    if (_status != SensorStatus.active) return;

    await _subscription?.cancel();
    _subscription = null;
    
    try {
      await _platform.stopSensor();
    } catch (_) {}

    _status = SensorStatus.inactive;
    notifyListeners();
  }

  @override
  void dispose() {
    stopMonitoring();
    super.dispose();
  }
}
