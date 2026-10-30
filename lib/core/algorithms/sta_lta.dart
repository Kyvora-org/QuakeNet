import 'dart:math';

/// State of the STA/LTA algorithm.
class StaLtaResult {
  final double sta;
  final double lta;
  final double ratio;
  final bool isTriggered;

  StaLtaResult(this.sta, this.lta, this.ratio, this.isTriggered);
}

/// A recursive implementation of the Short-Term Average / Long-Term Average algorithm.
/// This implementation uses exponential moving averages (EMA) to avoid the memory
/// overhead of keeping large circular buffers of square values.
class StaLta {
  final double staSamples;
  final double ltaSamples;
  final double triggerThreshold;
  final double detriggerThreshold;

  double _sta = 0;
  double _lta = 0;
  bool _isTriggered = false;
  int _samplesProcessed = 0;

  /// Creates a recursive STA/LTA calculator.
  /// [staSamples] is the number of samples in the Short-Term window.
  /// [ltaSamples] is the number of samples in the Long-Term window.
  /// [triggerThreshold] is the STA/LTA ratio above which a trigger is declared.
  /// [detriggerThreshold] is the ratio below which a trigger is cleared.
  StaLta({
    required this.staSamples,
    required this.ltaSamples,
    required this.triggerThreshold,
    this.detriggerThreshold = 1.0,
  });

  /// Processes a single filtered data point (usually one axis or magnitude).
  StaLtaResult process(double filteredValue) {
    // Characteristic Function: Energy (amplitude squared) or absolute amplitude.
    // Squared amplitude is standard in seismology to emphasize peaks.
    final double cf = filteredValue * filteredValue;

    if (_samplesProcessed == 0) {
      _sta = cf;
      _lta = cf;
    } else {
      // Recursive calculation using EMA
      // new_average = old_average + (new_value - old_average) / window_size
      _sta = _sta + (cf - _sta) / staSamples;
      _lta = _lta + (cf - _lta) / ltaSamples;
    }

    _samplesProcessed++;

    // Guard against division by zero in the very beginning or perfect silence
    final ratio = _lta > 1e-10 ? _sta / _lta : 1.0;

    // Trigger logic
    if (!_isTriggered && ratio >= triggerThreshold) {
      // For accurate LTA background preservation during an event, 
      // traditional STA/LTA freezes the LTA while triggered. 
      // We will freeze LTA updates by not updating it while triggered.
      _isTriggered = true;
    } else if (_isTriggered && ratio <= detriggerThreshold) {
      _isTriggered = false;
    }

    return StaLtaResult(sqrt(_sta), sqrt(_lta), ratio, _isTriggered);
  }

  void reset() {
    _sta = 0;
    _lta = 0;
    _isTriggered = false;
    _samplesProcessed = 0;
  }
}
