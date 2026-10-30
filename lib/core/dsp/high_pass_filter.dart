/// A simple First-Order IIR High-Pass Filter.
/// Used to isolate dynamic acceleration (movement) from static acceleration (gravity).
class HighPassFilter {
  // Alpha is the filter coefficient (0 < alpha < 1).
  // Alpha = tau / (tau + dt), where tau = 1 / (2 * pi * fc), fc is cutoff frequency, dt is sample rate interval.
  final double alpha;

  double _prevX = 0;
  double _prevY = 0;
  double _prevZ = 0;

  double _filteredX = 0;
  double _filteredY = 0;
  double _filteredZ = 0;

  bool _initialized = false;

  /// Creates a high-pass filter with the given [alpha] coefficient.
  /// A typical value for 50Hz and ~0.5Hz cutoff is around 0.8 - 0.9.
  HighPassFilter(this.alpha);

  /// Creates a high-pass filter by specifying the sample rate and cutoff frequency.
  factory HighPassFilter.fromCutoff(double sampleRateHz, double cutoffHz) {
    final dt = 1.0 / sampleRateHz;
    final rc = 1.0 / (2 * 3.141592653589793 * cutoffHz);
    final alpha = rc / (rc + dt);
    return HighPassFilter(alpha);
  }

  /// Processes a new raw sample (x, y, z) and returns the filtered (x, y, z).
  List<double> process(double x, double y, double z) {
    if (!_initialized) {
      _prevX = x;
      _prevY = y;
      _prevZ = z;
      _filteredX = 0;
      _filteredY = 0;
      _filteredZ = 0;
      _initialized = true;
      return [_filteredX, _filteredY, _filteredZ];
    }

    _filteredX = alpha * (_filteredX + x - _prevX);
    _filteredY = alpha * (_filteredY + y - _prevY);
    _filteredZ = alpha * (_filteredZ + z - _prevZ);

    _prevX = x;
    _prevY = y;
    _prevZ = z;

    return [_filteredX, _filteredY, _filteredZ];
  }

  /// Resets the filter state.
  void reset() {
    _initialized = false;
  }
}
