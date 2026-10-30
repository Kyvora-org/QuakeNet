import 'package:flutter/foundation.dart';
import 'dart:math';
import '../models/sensor_sample.dart';
import '../core/dsp/high_pass_filter.dart';
import '../core/algorithms/sta_lta.dart';

class ProcessingService extends ChangeNotifier {
  late HighPassFilter _highPassFilter;
  late StaLta _staLta;

  double _sampleRateHz = 50.0;
  
  bool _isTriggered = false;
  double _currentRatio = 1.0;
  final void Function(DateTime timestamp, double peakMagnitude, double staLtaRatio)?
      _onMovementCandidate;

  bool get isTriggered => _isTriggered;
  double get currentRatio => _currentRatio;

  ProcessingService({
    double sampleRateHz = 50.0,
    void Function(DateTime timestamp, double peakMagnitude, double staLtaRatio)?
        onMovementCandidate,
  }) : _onMovementCandidate = onMovementCandidate {
    _sampleRateHz = sampleRateHz;
    _highPassFilter = HighPassFilter.fromCutoff(_sampleRateHz, 0.5);
    _staLta = StaLta(
      staSamples: _sampleRateHz * 1.0, 
      ltaSamples: _sampleRateHz * 10.0, 
      triggerThreshold: 4.0,
      detriggerThreshold: 1.5,
    );
  }

  void updateSampleRate(double newRate) {
    if (newRate != _sampleRateHz && newRate > 0) {
      _sampleRateHz = newRate;
      _highPassFilter = HighPassFilter.fromCutoff(_sampleRateHz, 0.5);
      _staLta = StaLta(
        staSamples: _sampleRateHz * 1.0, 
        ltaSamples: _sampleRateHz * 10.0, 
        triggerThreshold: 4.0,
        detriggerThreshold: 1.5,
      );
      reset();
    }
  }

  /// Process a new incoming sensor sample.
  void processSample(SensorSample sample) {
    // 1. Filter out gravity using High-Pass IIR
    final filtered = _highPassFilter.process(sample.x, sample.y, sample.z);
    
    // 2. Compute magnitude of filtered (dynamic-only) acceleration
    final dx = filtered[0];
    final dy = filtered[1];
    final dz = filtered[2];
    final dynamicMagnitude = sqrt(dx * dx + dy * dy + dz * dz);

    // 3. Feed into STA/LTA (which squares internally)
    final result = _staLta.process(dynamicMagnitude);

    bool stateChanged = false;
    final wasTriggered = _isTriggered;
    if (_isTriggered != result.isTriggered) {
      _isTriggered = result.isTriggered;
      stateChanged = true;
    }

    if (!wasTriggered && result.isTriggered) {
      _onMovementCandidate?.call(sample.timestamp, dynamicMagnitude, result.ratio);
    }

    // Only notify on meaningful changes to avoid 50 rebuilds/sec
    if ((_currentRatio - result.ratio).abs() > 0.1 || stateChanged) {
      _currentRatio = result.ratio;
      notifyListeners();
    }
  }

  void reset() {
    _highPassFilter.reset();
    _staLta.reset();
    _isTriggered = false;
    _currentRatio = 1.0;
    notifyListeners();
  }
}
