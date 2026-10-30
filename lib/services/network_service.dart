import 'dart:async';
import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/device_node.dart';
import '../models/seismic_trigger.dart';

enum NetworkStatus { disabled, connecting, connected, error, offlineQueue }

/// Servicio encargado de reportar los candidatos sísmicos locales 
/// hacia la tabla 'triggers' de Supabase (Fase 2B).
class NetworkService extends ChangeNotifier {
  final SupabaseClient? _client;
  final DeviceNode node;

  NetworkStatus _status;
  String? _errorMessage;
  int _uploadCount = 0;

  // Anti-spam configuration
  static const int _triggerCooldownMs = 15000;
  DateTime? _lastTriggerTime;

  // Offline queue
  final Queue<SeismicTrigger> _offlineQueue = Queue<SeismicTrigger>();
  static const int _maxQueueSize = 50;

  NetworkService({required this.node, SupabaseClient? client})
      : _client = client,
        _status = client == null ? NetworkStatus.disabled : NetworkStatus.connected;

  NetworkStatus get status => _status;
  String? get errorMessage => _errorMessage;
  int get uploadCount => _uploadCount;
  DateTime? get lastTriggerTime => _lastTriggerTime;

  Future<void> connect() async {
    // Para Fase 2B, la conexión de HTTP no es persistente como WebSocket, 
    // pero podemos hacer un chequeo de estado o vaciar la cola.
    if (_client == null) return;
    _flushQueue();
  }

  Future<void> publishMovementCandidate({
    required DateTime timestamp,
    required double peakMagnitude,
    required double staLtaRatio,
    double? samplingRateHz,
  }) async {
    if (_client == null || _status == NetworkStatus.disabled) return;

    // Cooldown Anti-spam
    if (_lastTriggerTime != null) {
      final elapsed = timestamp.difference(_lastTriggerTime!).inMilliseconds;
      if (elapsed < _triggerCooldownMs) {
        debugPrint('[TRIGGER] Ignorado por cooldown anti-spam ($elapsed ms < $_triggerCooldownMs ms)');
        return;
      }
    }
    _lastTriggerTime = timestamp;

    double lat = 0.0;
    double lon = 0.0;
    double? accuracy;

    // GPS: Fetch location gracefully
    try {
      final hasPerm = await Geolocator.checkPermission();
      if (hasPerm == LocationPermission.whileInUse || hasPerm == LocationPermission.always) {
        final pos = await Geolocator.getLastKnownPosition() ?? await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(timeLimit: Duration(seconds: 3), accuracy: LocationAccuracy.low),
        );
        lat = pos.latitude;
        lon = pos.longitude;
        accuracy = pos.accuracy;
      }
    } catch (e) {
      debugPrint('[GPS] Error obteniendo ubicación: $e');
    }

    final trigger = SeismicTrigger(
      triggerId: const Uuid().v4(),
      nodeId: node.nodeId,
      sessionId: node.sessionId,
      detectedAt: timestamp,
      latitude: lat,
      longitude: lon,
      locationAccuracyM: accuracy,
      ratio: staLtaRatio,
      peakMagnitude: peakMagnitude,
      platform: node.platform,
      samplingRateHz: samplingRateHz,
    );

    _offlineQueue.addLast(trigger);
    if (_offlineQueue.length > _maxQueueSize) {
      _offlineQueue.removeFirst(); // Limitar el tamaño de la cola
    }

    _flushQueue();
  }

  Future<void> _flushQueue() async {
    if (_client == null || _offlineQueue.isEmpty) return;

    final trigger = _offlineQueue.first;

    try {
      debugPrint('[NETWORK] Uploading trigger ${trigger.triggerId}...');
      await _client!.from('triggers').insert(trigger.toMap());
      debugPrint('[SUPABASE] Trigger inserted successfully');
      
      _uploadCount++;
      _offlineQueue.removeFirst();
      
      _status = NetworkStatus.connected;
      _errorMessage = null;
      notifyListeners();

      // Procesar recursivamente si hay más
      if (_offlineQueue.isNotEmpty) {
        _flushQueue();
      }
    } catch (error) {
      debugPrint('[SUPABASE] Failed to insert trigger: $error');
      _status = NetworkStatus.offlineQueue;
      _errorMessage = 'Guardado localmente. Error red: $error';
      notifyListeners();
    }
  }

  @override
  void dispose() {
    super.dispose();
  }
}
