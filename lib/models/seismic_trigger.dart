/// A local movement candidate produced by one experimental node.
///
/// This is not a confirmed earthquake and is never an alert to the user.
/// Representa la tabla `triggers` de Supabase PostgreSQL.
class SeismicTrigger {
  final String triggerId;
  final String nodeId;
  final String sessionId;
  final DateTime detectedAt;
  final double? latitude;
  final double? longitude;
  final double? locationAccuracyM;
  final double ratio;
  final double? peakMagnitude;
  final int? durationMs;
  final double? samplingRateHz;
  final String platform;
  final String? appVersion;
  final String? eventId;

  const SeismicTrigger({
    required this.triggerId,
    required this.nodeId,
    required this.sessionId,
    required this.detectedAt,
    this.latitude,
    this.longitude,
    this.locationAccuracyM,
    required this.ratio,
    this.peakMagnitude,
    this.durationMs,
    this.samplingRateHz,
    required this.platform,
    this.appVersion,
    this.eventId,
  });

  /// Serialización para inserción en la tabla `triggers` de Supabase.
  /// No envía campos nulos ni inventa coordenadas.
  /// event_id nunca se envía desde el cliente (el correlador backend lo asigna).
  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'id': triggerId,
      'node_id': nodeId,
      'session_id': sessionId,
      'detected_at': detectedAt.toUtc().toIso8601String(),
      'ratio': ratio,
      'platform': platform,
    };
    if (latitude != null) map['latitude'] = latitude;
    if (longitude != null) map['longitude'] = longitude;
    if (locationAccuracyM != null) map['location_accuracy_m'] = locationAccuracyM;
    if (peakMagnitude != null) map['peak_magnitude'] = peakMagnitude;
    if (durationMs != null) map['duration_ms'] = durationMs;
    if (samplingRateHz != null) map['sampling_rate_hz'] = samplingRateHz;
    if (appVersion != null) map['app_version'] = appVersion;
    return map;
  }

  factory SeismicTrigger.fromMap(Map<String, dynamic> map) => SeismicTrigger(
        triggerId: map['id'] as String,
        nodeId: map['node_id'] as String,
        sessionId: map['session_id'] as String,
        detectedAt: DateTime.parse(map['detected_at'] as String).toLocal(),
        latitude: map['latitude'] != null ? (map['latitude'] as num).toDouble() : null,
        longitude: map['longitude'] != null ? (map['longitude'] as num).toDouble() : null,
        locationAccuracyM: map['location_accuracy_m'] != null ? (map['location_accuracy_m'] as num).toDouble() : null,
        ratio: (map['ratio'] as num).toDouble(),
        peakMagnitude: map['peak_magnitude'] != null ? (map['peak_magnitude'] as num).toDouble() : null,
        durationMs: map['duration_ms'] as int?,
        samplingRateHz: map['sampling_rate_hz'] != null ? (map['sampling_rate_hz'] as num).toDouble() : null,
        platform: map['platform'] as String,
        appVersion: map['app_version'] as String?,
        eventId: map['event_id'] as String?,
      );
}
