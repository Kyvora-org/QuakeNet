import 'package:flutter_test/flutter_test.dart';
import 'package:quakenet/models/seismic_trigger.dart';

void main() {
  group('SeismicTrigger', () {
    test('toMap produces correct column names for Supabase', () {
      final trigger = SeismicTrigger(
        triggerId: 'test-uuid-1234',
        nodeId: 'node-uuid-5678',
        sessionId: 'session-uuid-9012',
        detectedAt: DateTime.utc(2026, 10, 3, 15, 30, 0),
        latitude: 4.571,
        longitude: -74.297,
        locationAccuracyM: 12.5,
        ratio: 5.2,
        peakMagnitude: 0.08,
        samplingRateHz: 50.0,
        platform: 'android',
      );

      final map = trigger.toMap();

      expect(map['id'], 'test-uuid-1234');
      expect(map['node_id'], 'node-uuid-5678');
      expect(map['session_id'], 'session-uuid-9012');
      expect(map['detected_at'], '2026-10-03T15:30:00.000Z');
      expect(map['latitude'], 4.571);
      expect(map['longitude'], -74.297);
      expect(map['location_accuracy_m'], 12.5);
      expect(map['ratio'], 5.2);
      expect(map['peak_magnitude'], 0.08);
      expect(map['sampling_rate_hz'], 50.0);
      expect(map['platform'], 'android');
      // event_id should never be sent from client
      expect(map.containsKey('event_id'), false);
    });

    test('toMap omits null optional fields', () {
      final trigger = SeismicTrigger(
        triggerId: 'id',
        nodeId: 'node',
        sessionId: 'session',
        detectedAt: DateTime.utc(2026, 1, 1),
        latitude: 0.0,
        longitude: 0.0,
        ratio: 1.0,
        platform: 'android',
      );

      final map = trigger.toMap();

      expect(map.containsKey('location_accuracy_m'), false);
      expect(map.containsKey('peak_magnitude'), false);
      expect(map.containsKey('duration_ms'), false);
      expect(map.containsKey('sampling_rate_hz'), false);
      expect(map.containsKey('app_version'), false);
      expect(map.containsKey('event_id'), false);
    });

    test('fromMap round-trip preserves all values', () {
      final original = SeismicTrigger(
        triggerId: 'round-trip-id',
        nodeId: 'node-abc',
        sessionId: 'session-xyz',
        detectedAt: DateTime.utc(2026, 6, 15, 12, 0, 0),
        latitude: 7.123,
        longitude: -73.456,
        locationAccuracyM: 25.0,
        ratio: 8.3,
        peakMagnitude: 0.12,
        durationMs: 3000,
        samplingRateHz: 100.0,
        platform: 'ios',
        appVersion: '1.0.0',
      );

      // Simulate what Supabase would return 
      final jsonMap = <String, dynamic>{
        'id': 'round-trip-id',
        'node_id': 'node-abc',
        'session_id': 'session-xyz',
        'detected_at': '2026-06-15T12:00:00.000Z',
        'latitude': 7.123,
        'longitude': -73.456,
        'location_accuracy_m': 25.0,
        'ratio': 8.3,
        'peak_magnitude': 0.12,
        'duration_ms': 3000,
        'sampling_rate_hz': 100.0,
        'platform': 'ios',
        'app_version': '1.0.0',
        'event_id': null,
      };

      final restored = SeismicTrigger.fromMap(jsonMap);

      expect(restored.triggerId, original.triggerId);
      expect(restored.nodeId, original.nodeId);
      expect(restored.sessionId, original.sessionId);
      expect(restored.latitude, original.latitude);
      expect(restored.longitude, original.longitude);
      expect(restored.locationAccuracyM, original.locationAccuracyM);
      expect(restored.ratio, original.ratio);
      expect(restored.peakMagnitude, original.peakMagnitude);
      expect(restored.durationMs, original.durationMs);
      expect(restored.samplingRateHz, original.samplingRateHz);
      expect(restored.platform, original.platform);
      expect(restored.appVersion, original.appVersion);
    });
  });
}
