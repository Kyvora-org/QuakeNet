import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/sensor_sample.dart';
import '../platform/sensor_platform.dart';
import '../core/utils/circular_buffer.dart';
import '../core/config/consensus_config.dart';
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

  PowerMode _powerMode = PowerMode.normal;
  PowerMode get powerMode => _powerMode;

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

  // Circular buffer to keep the last 500 samples for visualization
  final CircularBuffer<SensorSample> _buffer = CircularBuffer<SensorSample>(500);
  List<SensorSample> get bufferedSamples => _buffer.toList();

  StreamSubscription<SensorSample>? _subscription;

  // Windowed calculation for instantaneous actual rate
  DateTime? _rateWindowStart;
  int _rateWindowSamples = 0;

  Future<void> setPowerMode(PowerMode mode) async {
    _powerMode = mode;
    if (mode == PowerMode.disabled) {
      await stopMonitoring();
      return;
    }

    final targetRate = ConsensusConfig.samplingRatesHz[mode]?.toInt() ?? 50;
    _requestedRate = targetRate;
    _processingService?.updateSampleRate(targetRate.toDouble());

    if (_status == SensorStatus.active) {
      // Reconfigurar sensor nativo
      try {
        await _platform.startSensor(targetRate);
        _rateWindowStart = DateTime.now();
        _rateWindowSamples = 0;
        notifyListeners();
      } catch (e) {
        debugPrint('[SENSOR] Error reconfigurando sampling rate: $e');
      }
    } else {
      notifyListeners();
    }
  }

  Future<void> startMonitoring({int? rate}) async {
    final effectiveRate = rate ?? ConsensusConfig.samplingRatesHz[_powerMode]?.toInt() ?? 50;
    
    // Si ya está activo con la misma frecuencia, ignorar
    if (_status == SensorStatus.active && _requestedRate == effectiveRate) return;

    _requestedRate = effectiveRate;
    _sampleCount = 0;
    _actualRate = 0.0;
    _rateWindowStart = DateTime.now();
    _rateWindowSamples = 0;
    _sessionStartTime = DateTime.now();
    _buffer.clear();
    _processingService?.updateSampleRate(effectiveRate.toDouble());

    try {
      await _platform.startSensor(effectiveRate);
      _status = SensorStatus.active;
      notifyListeners();

      _subscription ??= _platform.accelerometerStream.listen(
        (sample) {
          _sampleCount++;
          _rateWindowSamples++;
          _latestSample = sample;
          _buffer.add(sample);
          
          _recordingService?.addSample(sample);
          _processingService?.processSample(sample);
          
          // Cálculo de frecuencia real en ventana deslizante (cada 1.5s)
          final now = DateTime.now();
          final windowElapsed = now.difference(_rateWindowStart ?? now).inMilliseconds;
          if (windowElapsed >= 1500) {
            _actualRate = (_rateWindowSamples / (windowElapsed / 1000.0));
            _rateWindowStart = now;
            _rateWindowSamples = 0;
          }

          // Notificación UI con moderación (cada 5 muestras o 100ms) para evitar jank
          if (_sampleCount % 5 == 0) {
            notifyListeners();
          }
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
    _actualRate = 0.0;
    notifyListeners();
  }

  @override
  void dispose() {
    stopMonitoring();
    super.dispose();
  }
}
