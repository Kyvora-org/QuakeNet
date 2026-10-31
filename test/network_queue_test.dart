import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:quakenet/models/device_node.dart';
import 'package:quakenet/models/seismic_trigger.dart';
import 'package:quakenet/services/network_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NetworkService Offline Queue', () {
    late DeviceNode testNode;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      testNode = DeviceNode(
        nodeId: 'test-node-id',
        sessionId: 'test-session-id',
        platform: 'android',
        createdAt: DateTime.utc(2026, 1, 1),
        sensorCapabilities: const {'accelerometer': true},
      );
    });

    test('initializes with zero pending triggers when storage is empty', () {
      final service = NetworkService(node: testNode, client: null);
      expect(service.pendingCount, 0);
      expect(service.status, NetworkStatus.disabled);
    });

    test('reloads persisted triggers from SharedPreferences', () async {
      final trigger = SeismicTrigger(
        triggerId: 'persisted-uuid-999',
        nodeId: 'test-node-id',
        sessionId: 'test-session-id',
        detectedAt: DateTime.now().toUtc(),
        ratio: 4.5,
        platform: 'android',
      );

      final queuedItem = {
        'trigger': trigger.toMap(),
        'retryAttempts': 1,
        'queuedAt': DateTime.now().toUtc().toIso8601String(),
      };

      SharedPreferences.setMockInitialValues({
        'quakenet_offline_trigger_queue': [jsonEncode(queuedItem)],
      });

      // Creamos el servicio que leerá las preferencias
      final service = NetworkService(node: testNode, client: null);
      // Permitir que el constructor async termine de cargar
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(service.pendingCount, 1);
      expect(service.status, NetworkStatus.offlineQueue);
    });

    test('discards triggers older than 24 hours on load', () async {
      final expiredQueuedItem = {
        'trigger': SeismicTrigger(
          triggerId: 'expired-trigger',
          nodeId: 'test-node-id',
          sessionId: 'test-session-id',
          detectedAt: DateTime.now().toUtc().subtract(const Duration(hours: 48)),
          ratio: 4.5,
          platform: 'android',
        ).toMap(),
        'retryAttempts': 2,
        'queuedAt': DateTime.now().toUtc().subtract(const Duration(hours: 30)).toIso8601String(),
      };

      SharedPreferences.setMockInitialValues({
        'quakenet_offline_trigger_queue': [jsonEncode(expiredQueuedItem)],
      });

      final service = NetworkService(node: testNode, client: null);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(service.pendingCount, 0, reason: 'Triggers de más de 24 horas deben ser descartados');
    });
  });
}
