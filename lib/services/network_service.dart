import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/device_node.dart';
import '../models/seismic_trigger.dart';

enum NetworkStatus { disabled, connecting, connected, error, offlineQueue }

/// Envoltura interna para la cola persistente con métricas de reintento.
class _QueuedTrigger {
  final SeismicTrigger trigger;
  int retryAttempts;
  final DateTime queuedAt;

  _QueuedTrigger({
    required this.trigger,
    this.retryAttempts = 0,
    DateTime? queuedAt,
  }) : queuedAt = queuedAt ?? DateTime.now().toUtc();

  Map<String, dynamic> toJson() => {
        'trigger': trigger.toMap(),
        'retryAttempts': retryAttempts,
        'queuedAt': queuedAt.toIso8601String(),
      };

  factory _QueuedTrigger.fromJson(Map<String, dynamic> json) => _QueuedTrigger(
        trigger: SeismicTrigger.fromMap(Map<String, dynamic>.from(json['trigger'] as Map)),
        retryAttempts: json['retryAttempts'] as int? ?? 0,
        queuedAt: json['queuedAt'] != null
            ? DateTime.parse(json['queuedAt'] as String).toUtc()
            : DateTime.now().toUtc(),
      );
}

/// Servicio encargado de reportar los candidatos sísmicos locales 
/// hacia la tabla 'triggers' de Supabase (Fase 2B y 2B.1).
///
/// Implementa cola persistente con SharedPreferences, backoff exponencial,
/// límite de antigüedad y no inventa coordenadas si el GPS está apagado.
class NetworkService extends ChangeNotifier {
  final SupabaseClient? _client;
  DeviceNode node;

  NetworkStatus _status;
  String? _errorMessage;
  int _uploadCount = 0;
  DateTime? _lastUploadTime;
  DateTime? _lastTriggerTime;

  // Anti-spam configuration (cooldown experimental de 15s por nodo)
  static const int _triggerCooldownMs = 15000;

  // Persistent offline queue configuration
  static const String _prefsQueueKey = 'quakenet_offline_trigger_queue';
  static const int _maxQueueSize = 50;
  static const int _maxAgeMs = 86400000; // 24 horas
  static const int _maxRetries = 5;

  final List<_QueuedTrigger> _queue = [];
  bool _isFlushing = false;
  int _backoffSeconds = 2;
  DateTime? _nextAllowedFlushTime;

  NetworkService({required this.node, SupabaseClient? client})
      : _client = client,
        _status = client == null ? NetworkStatus.disabled : NetworkStatus.connected {
    _loadPersistedQueue();
  }

  NetworkStatus get status => _status;
  String? get errorMessage => _errorMessage;
  int get uploadCount => _uploadCount;
  DateTime? get lastUploadTime => _lastUploadTime;
  DateTime? get lastTriggerTime => _lastTriggerTime;
  int get pendingCount => _queue.length;

  /// Actualiza el nodo (ej. cuando se renueva el sessionId al iniciar monitoreo)
  void updateNode(DeviceNode newNode) {
    node = newNode;
    notifyListeners();
  }

  /// Carga la cola desde almacenamiento local (SharedPreferences)
  Future<void> _loadPersistedQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_prefsQueueKey);
      if (list != null && list.isNotEmpty) {
        final now = DateTime.now().toUtc();
        _queue.clear();
        for (final item in list) {
          try {
            final decoded = jsonDecode(item) as Map<String, dynamic>;
            final queued = _QueuedTrigger.fromJson(decoded);
            // Descartar registros expirados (> 24h)
            if (now.difference(queued.queuedAt).inMilliseconds < _maxAgeMs) {
              _queue.add(queued);
            }
          } catch (e) {
            debugPrint('[QUEUE] Error deserializando trigger persistido: $e');
          }
        }
        if (_queue.isNotEmpty) {
          _status = NetworkStatus.offlineQueue;
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('[QUEUE] Error leyendo cola persistente: $e');
    }
  }

  /// Guarda el estado actual de la cola en SharedPreferences
  Future<void> _savePersistedQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = _queue.map((q) => jsonEncode(q.toJson())).toList();
      await prefs.setStringList(_prefsQueueKey, list);
    } catch (e) {
      debugPrint('[QUEUE] Error persistiendo cola: $e');
    }
  }

  Future<void> connect() async {
    if (_client == null) {
      _status = NetworkStatus.disabled;
      notifyListeners();
      return;
    }
    await _flushQueue();
  }

  /// Publica un candidato de movimiento local generado por STA/LTA.
  Future<void> publishMovementCandidate({
    required DateTime timestamp,
    required double peakMagnitude,
    required double staLtaRatio,
    double? samplingRateHz,
  }) async {
    if (_client == null || _status == NetworkStatus.disabled) return;

    // Cooldown Anti-spam de 15 segundos
    if (_lastTriggerTime != null) {
      final elapsed = timestamp.difference(_lastTriggerTime!).inMilliseconds;
      if (elapsed < _triggerCooldownMs) {
        debugPrint('[TRIGGER] Ignorado por cooldown anti-spam ($elapsed ms < $_triggerCooldownMs ms)');
        return;
      }
    }
    _lastTriggerTime = timestamp;

    double? lat;
    double? lon;
    double? accuracy;

    // GPS: Consulta no bloqueante con timeout estricto sin inventar coordenadas
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (serviceEnabled) {
        final hasPerm = await Geolocator.checkPermission();
        if (hasPerm == LocationPermission.whileInUse || hasPerm == LocationPermission.always) {
          final pos = await Geolocator.getLastKnownPosition() ??
              await Geolocator.getCurrentPosition(
                locationSettings: const LocationSettings(
                  timeLimit: Duration(seconds: 2),
                  accuracy: LocationAccuracy.low,
                ),
              );
          lat = pos.latitude;
          lon = pos.longitude;
          accuracy = pos.accuracy;
        }
      }
    } catch (e) {
      debugPrint('[GPS] Sin ubicación para el trigger: $e');
      lat = null;
      lon = null;
      accuracy = null;
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

    // Encolar y limitar tamaño máximo
    _queue.add(_QueuedTrigger(trigger: trigger));
    if (_queue.length > _maxQueueSize) {
      _queue.removeAt(0); // Eliminar el más antiguo
    }
    await _savePersistedQueue();

    notifyListeners();
    _flushQueue();
  }

  /// Procesa la cola de envíos de forma secuencial y segura (sin recursión desbocada)
  Future<void> _flushQueue() async {
    if (_client == null || _queue.isEmpty || _isFlushing) return;

    if (_nextAllowedFlushTime != null && DateTime.now().isBefore(_nextAllowedFlushTime!)) {
      return;
    }

    _isFlushing = true;

    try {
      while (_queue.isNotEmpty) {
        final current = _queue.first;

        // Comprobar intentos máximos para evitar poison-pill
        if (current.retryAttempts >= _maxRetries) {
          debugPrint('[QUEUE] Trigger ${current.trigger.triggerId} descartado por exceder $_maxRetries reintentos.');
          _queue.removeAt(0);
          await _savePersistedQueue();
          continue;
        }

        try {
          debugPrint('[NETWORK] Uploading trigger ${current.trigger.triggerId}...');
          await _client.from('triggers').insert(current.trigger.toMap());
          debugPrint('[SUPABASE] Trigger inserted successfully');

          _uploadCount++;
          _lastUploadTime = DateTime.now();
          _queue.removeAt(0);
          await _savePersistedQueue();

          _status = _queue.isEmpty ? NetworkStatus.connected : NetworkStatus.offlineQueue;
          _errorMessage = null;
          _backoffSeconds = 2; // Reset backoff on success
          notifyListeners();
        } catch (error) {
          current.retryAttempts++;
          await _savePersistedQueue();

          debugPrint('[SUPABASE] Failed to insert trigger: $error');
          _status = NetworkStatus.offlineQueue;
          _errorMessage = 'Guardado localmente. Error red: $error';

          // Aplicar backoff exponencial (2s, 4s, 8s, max 60s)
          _nextAllowedFlushTime = DateTime.now().add(Duration(seconds: _backoffSeconds));
          _backoffSeconds = min(_backoffSeconds * 2, 60);

          notifyListeners();
          break; // Detener flush hasta el próximo ciclo
        }
      }
    } finally {
      _isFlushing = false;
    }
  }
}
