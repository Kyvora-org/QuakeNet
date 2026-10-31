import 'package:flutter_test/flutter_test.dart';
import 'package:quakenet/models/seismic_trigger.dart';
import 'package:quakenet/models/device_node.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

    test('toMap omits null optional fields including coordinates without GPS', () {
      final trigger = SeismicTrigger(
        triggerId: 'id',
        nodeId: 'node',
        sessionId: 'session',
        detectedAt: DateTime.utc(2026, 1, 1),
        latitude: null,
        longitude: null,
        ratio: 1.0,
        platform: 'android',
      );

      final map = trigger.toMap();

      expect(map.containsKey('latitude'), false);
      expect(map.containsKey('longitude'), false);
      expect(map.containsKey('location_accuracy_m'), false);
      expect(map.containsKey('peak_magnitude'), false);
      expect(map.containsKey('duration_ms'), false);
      expect(map.containsKey('sampling_rate_hz'), false);
      expect(map.containsKey('app_version'), false);
      expect(map.containsKey('event_id'), false);
    });

    test('fromMap round-trip preserves all values including null coordinates', () {
      final original = SeismicTrigger(
        triggerId: 'round-trip-null-geo',
        nodeId: 'node-abc',
        sessionId: 'session-xyz',
        detectedAt: DateTime.utc(2026, 6, 15, 12, 0, 0),
        latitude: null,
        longitude: null,
        ratio: 8.3,
        platform: 'ios',
      );

      final jsonMap = <String, dynamic>{
        'id': 'round-trip-null-geo',
        'node_id': 'node-abc',
        'session_id': 'session-xyz',
        'detected_at': '2026-06-15T12:00:00.000Z',
        'latitude': null,
        'longitude': null,
        'ratio': 8.3,
        'platform': 'ios',
      };

      final restored = SeismicTrigger.fromMap(jsonMap);

      expect(restored.triggerId, original.triggerId);
      expect(restored.nodeId, original.nodeId);
      expect(restored.sessionId, original.sessionId);
      expect(restored.latitude, null);
      expect(restored.longitude, null);
      expect(restored.ratio, 8.3);
      expect(restored.platform, 'ios');
    });
  });

  group('DeviceNode Identity', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('persists nodeId across multiple loadExperimental calls', () async {
      final first = await DeviceNode.loadExperimental(platform: 'android');
      expect(first.nodeId.isNotEmpty, true);
      expect(first.sessionId.isNotEmpty, true);

      // Simular apertura posterior de la app
      final second = await DeviceNode.loadExperimental(platform: 'android');
      expect(second.nodeId, first.nodeId, reason: 'Node ID debe conservarse entre reinicios');
      expect(second.sessionId != first.sessionId, true, reason: 'Session ID debe ser único para la nueva sesión');
    });

    test('renewSession creates new sessionId with identical nodeId', () async {
      final node = await DeviceNode.loadExperimental(platform: 'android');
      final renewed = node.renewSession();

      expect(renewed.nodeId, node.nodeId);
      expect(renewed.sessionId != node.sessionId, true);
      expect(renewed.platform, node.platform);
    });
  });
}
