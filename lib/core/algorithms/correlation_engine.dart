import 'dart:math';
import '../../models/seismic_trigger.dart';

/// Resultado de una corrida de correlación y consenso sísmico distribuido.
class CorrelationResult {
  final List<CorrelatedEvent> activeEvents;
  final List<SeismicTrigger> processedTriggers;
  final List<SeismicTrigger> discardedTriggers;
  final int evaluatedCount;
  final Duration executionDuration;

  const CorrelationResult({
    required this.activeEvents,
    required this.processedTriggers,
    required this.discardedTriggers,
    required this.evaluatedCount,
    required this.executionDuration,
  });
}

/// Representación en memoria de un evento correlacionado (Fase 2C).
class CorrelatedEvent {
  final String id;
  String status; // 'candidate', 'correlated', 'high_confidence', 'discarded'
  DateTime detectedAt;
  double latitude;
  double longitude;
  double estimatedRadiusKm;
  int nodeCount;
  double independentNodeCount;
  int spatialClusterCount;
  double confidence;
  double avgStaLta;
  double maxPeakMagnitude;
  String? rejectionReason;
  DateTime lastCorrelatedAt;
  final List<SeismicTrigger> triggers;

  CorrelatedEvent({
    required this.id,
    required this.status,
    required this.detectedAt,
    required this.latitude,
    required this.longitude,
    required this.estimatedRadiusKm,
    required this.nodeCount,
    required this.independentNodeCount,
    required this.spatialClusterCount,
    required this.confidence,
    required this.avgStaLta,
    required this.maxPeakMagnitude,
    this.rejectionReason,
    DateTime? lastCorrelatedAt,
    List<SeismicTrigger>? triggers,
  })  : lastCorrelatedAt = lastCorrelatedAt ?? DateTime.now().toUtc(),
        triggers = triggers ?? [];

  Map<String, dynamic> toMap() => {
        'id': id,
        'status': status,
        'detected_at': detectedAt.toIso8601String(),
        'latitude': latitude,
        'longitude': longitude,
        'estimated_radius_km': estimatedRadiusKm,
        'node_count': nodeCount,
        'independent_node_count': independentNodeCount,
        'spatial_cluster_count': spatialClusterCount,
        'confidence': confidence,
        'avg_sta_lta': avgStaLta,
        'max_peak_magnitude': maxPeakMagnitude,
        'rejection_reason': rejectionReason,
        'last_correlated_at': lastCorrelatedAt.toIso8601String(),
      };
}

/// Motor de Consenso y Correlación Distribuida de QuakeNet (Fase 2C).
///
/// Implementa las reglas del modelo matemático formal:
/// 1. Agrupamiento espacio-temporal (ΔT <= 15s, ΔD <= 50km).
/// 2. Entropía espacial y atenuación anti-edificio (Spatial Hashing ~500m).
/// 3. Ponderación multicriterio de calidad de señal (STA/LTA, magnitud, GPS).
/// 4. Puntuación de confianza C ∈ [0, 100].
/// 5. Coherencia cinemática de propagación de ondas elásticas (1.2 km/s <= v_app <= 9.5 km/s).
class CorrelationEngine {
  /// Ventana temporal máxima para agrupar triggers en el mismo evento (15 segundos)
  static const int temporalWindowSeconds = 15;

  /// Radio geodésico máximo para agrupar triggers en el mismo evento (50 km)
  static const double spatialRadiusKm = 50.0;

  /// Umbral mínimo de nodos independientes para alcanzar alta confianza
  static const double minNodesHighConfidence = 100.0;

  /// Umbral mínimo de celdas espaciales para alta confianza
  static const int minCellsHighConfidence = 10;

  /// Umbral de confianza compuesto para alta confianza
  static const double minConfidenceScoreHigh = 80.0;

  /// Umbral de nodos independientes para evento correlacionado
  static const double minNodesCorrelated = 10.0;

  /// Umbral de celdas espaciales para evento correlacionado
  static const int minCellsCorrelated = 3;

  /// Umbral de confianza compuesto para evento correlacionado
  static const double minConfidenceScoreCorrelated = 40.0;

  /// Tiempo de caducidad para descartar triggers aislados que no logran consenso
  static const int triggerExpirationSeconds = 60;

  /// Calcula la distancia geodésica ortodrómica en kilómetros (Fórmula de Haversine).
  static double calculateDistanceKm(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const double earthRadiusKm = 6371.0;
    final dLat = (lat2 - lat1) * (pi / 180.0);
    final dLon = (lon2 - lon1) * (pi / 180.0);

    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * (pi / 180.0)) *
            cos(lat2 * (pi / 180.0)) *
            sin(dLon / 2) *
            sin(dLon / 2);

    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadiusKm * c;
  }

  /// Discretiza coordenadas en una celda espacial de resolución aproximada de 500m.
  static String getSpatialCell(double? latitude, double? longitude, String fallbackId) {
    if (latitude == null || longitude == null) {
      return 'NO_GPS_$fallbackId';
    }
    final latCell = (latitude * 100).round() / 100;
    final lonCell = (longitude * 100).round() / 100;
    return '${latCell.toStringAsFixed(2)}:${lonCell.toStringAsFixed(2)}';
  }

  /// Calcula la cantidad de Nodos Independientes (N_indep) aplicando
  /// atenuación sublineal sobre nodos acumulados en la misma célula geográfica.
  ///
  /// w(n_c) = 1.0 si n_c == 1; w(n_c) = 1.0 + 0.3 * ln(n_c) si n_c > 1.
  static double calculateIndependentNodes(List<SeismicTrigger> triggers) {
    if (triggers.isEmpty) return 0.0;

    // Agrupar nodos por célula geográfica (evitando duplicados del mismo nodo)
    final Map<String, Set<String>> cellNodes = {};

    for (final trg in triggers) {
      final cell = getSpatialCell(trg.latitude, trg.longitude, trg.nodeId);
      cellNodes.putIfAbsent(cell, () => {}).add(trg.nodeId);
    }

    double nIndep = 0.0;
    for (final entry in cellNodes.entries) {
      final int count = entry.value.length;
      if (count <= 1) {
        nIndep += 1.0;
      } else {
        nIndep += 1.0 + 0.3 * log(count);
      }
    }

    return (nIndep * 100).round() / 100.0;
  }

  /// Evalúa el factor de calidad individual de una detección (Q_i ∈ [0, 1]).
  static double calculateTriggerQuality(SeismicTrigger trg) {
    // 1. Ratio STA/LTA (peso 0.40)
    // Ratios normales de sismos: 3.0 a 15.0. Ratios > 30 sin correlación suelen ser impulsos
    double ratioScore = min(1.0, max(0.1, (trg.ratio - 3.0) / 12.0));
    if (trg.ratio > 30.0) {
      ratioScore *= 0.5; // Penalización por pico impulsivo anómalo
    }

    // 2. Magnitud pico (peso 0.30)
    final mag = trg.peakMagnitude ?? 0.1;
    double magScore = 1.0;
    if (mag < 0.01) {
      magScore = 0.3;
    } else if (mag > 1.2) {
      magScore = max(0.05, 1.0 - (mag - 1.2) / 1.8);
    }

    // 3. Precisión GPS (peso 0.30)
    double gpsScore = 0.2;
    if (trg.latitude != null && trg.longitude != null) {
      final acc = trg.locationAccuracyM;
      if (acc != null && acc <= 50.0) {
        gpsScore = 1.0;
      } else if (acc != null && acc <= 200.0) {
        gpsScore = 0.8;
      } else if (acc != null && acc <= 1000.0) {
        gpsScore = 0.5;
      } else {
        gpsScore = 0.4;
      }
    }

    double baseQuality = 0.40 * ratioScore + 0.30 * magScore + 0.30 * gpsScore;

    // Si la aceleración supera 3.0g (típico impacto o caída de teléfono), penalizar fuertemente
    if (mag > 3.0) {
      baseQuality *= 0.3;
    }

    return (baseQuality * 100).round() / 100.0;
  }

  /// Valida la coherencia cinemática de propagación de onda elástica entre dos triggers.
  /// Retorna false si la velocidad aparente es físicamente imposible para un sismo.
  static bool isKinematicallyConsistent(SeismicTrigger a, SeismicTrigger b) {
    if (a.latitude == null || a.longitude == null || b.latitude == null || b.longitude == null) {
      return true; // Sin GPS suficiente para refutar
    }

    final distKm = calculateDistanceKm(a.latitude!, a.longitude!, b.latitude!, b.longitude!);
    final dtSeconds = (a.detectedAt.difference(b.detectedAt).inMilliseconds.abs()) / 1000.0;

    // Si están a menos de 2 km, permitimos hasta 3 segundos por jitter de reloj NTP
    if (distKm <= 2.0) {
      return dtSeconds <= 3.0;
    }

    if (dtSeconds < 0.05) {
      // Detección simultánea a más de 2 km indica sincronía artificial/red (velocidad infinita)
      return false;
    }

    final vApp = distKm / dtSeconds;
    // Ondas sísmicas reales: entre 1.2 km/s y 9.5 km/s
    return vApp >= 1.2 && vApp <= 9.5;
  }

  /// Calcula la puntuación compuesta de confianza C ∈ [0, 100].
  static double calculateConfidenceScore({
    required double independentNodes,
    required int distinctCells,
    required double maxRadiusKm,
    required double avgQuality,
    required double timeSpreadSeconds,
  }) {
    // 1. Factor de volumen independiente (35%)
    final phiVol = min(1.0, independentNodes / minNodesHighConfidence);

    // 2. Factor de dispersión espacial (30%)
    final phiSpace = 0.5 * min(1.0, distinctCells / minCellsHighConfidence.toDouble()) +
        0.5 * min(1.0, maxRadiusKm / 30.0);

    // 3. Factor de calidad media de señal (20%)
    final phiQuality = avgQuality.clamp(0.0, 1.0);

    // 4. Factor de coherencia temporal (15%)
    final phiTime = max(0.1, 1.0 - (timeSpreadSeconds / 7.5));

    final rawScore = 100.0 * (
      0.35 * phiVol +
      0.30 * phiSpace +
      0.20 * phiQuality +
      0.15 * phiTime
    );

    return (rawScore * 10).round() / 10.0;
  }

  /// Ejecuta el proceso de correlación sobre una lista de triggers no procesados,
  /// integrándolos con eventos existentes o generando nuevos clusters.
  static CorrelationResult correlate({
    required List<SeismicTrigger> incomingTriggers,
    List<CorrelatedEvent>? existingEvents,
    DateTime? now,
  }) {
    final stopwatch = Stopwatch()..start();
    final currentTime = now ?? DateTime.now().toUtc();
    final events = List<CorrelatedEvent>.from(existingEvents ?? []);
    final List<SeismicTrigger> processed = [];
    final List<SeismicTrigger> discarded = [];

    // 1. Filtrar triggers duplicados del mismo nodo en la misma ventana de 15s (anti-replay)
    final List<SeismicTrigger> dedupedTriggers = [];
    final Map<String, DateTime> nodeLatestSeen = {};

    // Ordenar cronológicamente
    final sortedTriggers = List<SeismicTrigger>.from(incomingTriggers)
      ..sort((a, b) => a.detectedAt.compareTo(b.detectedAt));

    for (final trg in sortedTriggers) {
      final lastSeen = nodeLatestSeen[trg.nodeId];
      if (lastSeen != null &&
          trg.detectedAt.difference(lastSeen).inMilliseconds.abs() < 15000) {
        // Trigger duplicado o enviado en ráfaga dentro del cooldown: descartar
        discarded.add(trg);
        continue;
      }
      nodeLatestSeen[trg.nodeId] = trg.detectedAt;
      dedupedTriggers.add(trg);
    }

    // 2. Correlacionar cada trigger desduplicado
    final List<SeismicTrigger> unclustered = [];

    for (final trg in dedupedTriggers) {
      CorrelatedEvent? matchedEvent;

      // Buscar si encaja en algún evento activo existente
      for (final ev in events.where((e) => e.status == 'candidate' || e.status == 'correlated')) {
        final dt = (trg.detectedAt.difference(ev.detectedAt).inSeconds).abs();
        if (dt <= temporalWindowSeconds) {
          if (trg.latitude != null && trg.longitude != null) {
            final dist = calculateDistanceKm(
              trg.latitude!,
              trg.longitude!,
              ev.latitude,
              ev.longitude,
            );
            if (dist <= spatialRadiusKm) {
              matchedEvent = ev;
              break;
            }
          } else {
            // Trigger sin GPS se asocia solo si la ventana temporal es muy estricta (<= 5s)
            if (dt <= 5) {
              matchedEvent = ev;
              break;
            }
          }
        }
      }

      if (matchedEvent != null) {
        matchedEvent.triggers.add(trg);
        processed.add(trg);
      } else {
        unclustered.add(trg);
      }
    }

    // 3. Agrupar triggers no asociados para formar nuevos eventos candidatos
    final List<SeismicTrigger> stillUnclustered = [];
    final Set<String> assignedIds = {};

    for (int i = 0; i < unclustered.length; i++) {
      final anchor = unclustered[i];
      if (assignedIds.contains(anchor.triggerId)) continue;

      if (anchor.latitude == null || anchor.longitude == null) {
        stillUnclustered.add(anchor);
        continue;
      }

      final cluster = <SeismicTrigger>[anchor];

      for (int j = i + 1; j < unclustered.length; j++) {
        final candidate = unclustered[j];
        if (assignedIds.contains(candidate.triggerId)) continue;
        if (candidate.latitude == null || candidate.longitude == null) continue;

        final dt = (candidate.detectedAt.difference(anchor.detectedAt).inSeconds).abs();
        if (dt <= temporalWindowSeconds) {
          final dist = calculateDistanceKm(
            anchor.latitude!,
            anchor.longitude!,
            candidate.latitude!,
            candidate.longitude!,
          );
          if (dist <= spatialRadiusKm) {
            cluster.add(candidate);
          }
        }
      }

      // Si el cluster contiene al menos 3 triggers compatibles, nace un evento candidato
      if (cluster.length >= 3) {
        for (final c in cluster) {
          assignedIds.add(c.triggerId);
        }

        final newEvent = CorrelatedEvent(
          id: 'evt_${anchor.detectedAt.millisecondsSinceEpoch}_${events.length + 1}',
          status: 'candidate',
          detectedAt: anchor.detectedAt,
          latitude: anchor.latitude!,
          longitude: anchor.longitude!,
          estimatedRadiusKm: 1.0,
          nodeCount: cluster.length,
          independentNodeCount: calculateIndependentNodes(cluster),
          spatialClusterCount: 1,
          confidence: 10.0,
          avgStaLta: anchor.ratio,
          maxPeakMagnitude: anchor.peakMagnitude ?? 0.1,
          triggers: List.from(cluster),
        );

        events.add(newEvent);
        processed.addAll(cluster);
      } else {
        stillUnclustered.add(anchor);
      }
    }

    // 3.1. Asociar triggers sin GPS compatibles con eventos recién creados
    final List<SeismicTrigger> remainingUnclustered = [];
    for (final trg in stillUnclustered) {
      bool matched = false;
      if (trg.latitude == null || trg.longitude == null) {
        for (final ev in events.where((e) => e.status == 'candidate' || e.status == 'correlated')) {
          final dt = (trg.detectedAt.difference(ev.detectedAt).inSeconds).abs();
          if (dt <= 5) {
            ev.triggers.add(trg);
            processed.add(trg);
            matched = true;
            break;
          }
        }
      }
      if (!matched) {
        remainingUnclustered.add(trg);
      }
    }

    // 4. Manejo de triggers aislados: si superan triggerExpirationSeconds, descartar
    for (final trg in remainingUnclustered) {
      if (currentTime.difference(trg.detectedAt).inSeconds > triggerExpirationSeconds) {
        discarded.add(trg);
      }
    }

    // 5. Recalcular métricas de consenso y actualizar estados en todos los eventos
    for (final ev in events) {
      if (ev.status == 'discarded') continue;

      final trgs = ev.triggers;
      if (trgs.isEmpty) continue;

      // Calcular centroide con triggers que tengan GPS
      final gpsTriggers = trgs.where((t) => t.latitude != null && t.longitude != null).toList();
      if (gpsTriggers.isNotEmpty) {
        ev.latitude = gpsTriggers.map((t) => t.latitude!).reduce((a, b) => a + b) / gpsTriggers.length;
        ev.longitude = gpsTriggers.map((t) => t.longitude!).reduce((a, b) => a + b) / gpsTriggers.length;

        // Calcular radio máximo
        double maxDist = 0.5;
        for (final t in gpsTriggers) {
          final d = calculateDistanceKm(ev.latitude, ev.longitude, t.latitude!, t.longitude!);
          if (d > maxDist) maxDist = d;
        }
        ev.estimatedRadiusKm = (maxDist * 10).round() / 10.0;
      }

      // Conteo de nodos independientes y células
      ev.nodeCount = trgs.length;
      ev.independentNodeCount = calculateIndependentNodes(trgs);

      final distinctCells = trgs
          .map((t) => getSpatialCell(t.latitude, t.longitude, t.nodeId))
          .toSet()
          .length;
      ev.spatialClusterCount = distinctCells;

      // Métricas de señal agregadas
      ev.avgStaLta = ((trgs.map((t) => t.ratio).reduce((a, b) => a + b) / trgs.length) * 10).round() / 10.0;
      ev.maxPeakMagnitude = trgs.map((t) => t.peakMagnitude ?? 0.0).reduce(max);

      // Calidad promedio
      final avgQuality = trgs.map(calculateTriggerQuality).reduce((a, b) => a + b) / trgs.length;

      // Dispersión temporal
      final minTime = trgs.map((t) => t.detectedAt).reduce((a, b) => a.isBefore(b) ? a : b);
      final maxTime = trgs.map((t) => t.detectedAt).reduce((a, b) => a.isAfter(b) ? a : b);
      final timeSpread = (maxTime.difference(minTime).inMilliseconds) / 1000.0;

      // Confianza compuesta
      ev.confidence = calculateConfidenceScore(
        independentNodes: ev.independentNodeCount,
        distinctCells: distinctCells,
        maxRadiusKm: ev.estimatedRadiusKm,
        avgQuality: avgQuality,
        timeSpreadSeconds: timeSpread,
      );

      // Transición de estados
      if (ev.independentNodeCount >= minNodesHighConfidence &&
          distinctCells >= minCellsHighConfidence &&
          ev.confidence >= minConfidenceScoreHigh) {
        ev.status = 'high_confidence';
      } else if (ev.independentNodeCount >= minNodesCorrelated &&
          distinctCells >= minCellsCorrelated &&
          ev.confidence >= minConfidenceScoreCorrelated) {
        ev.status = 'correlated';
      } else {
        // Evaluar si debe ser descartado tras expirar la ventana
        final age = currentTime.difference(ev.detectedAt).inSeconds;
        if (age > 90) {
          // Si pasaron 90s y quedó confinado a una sola célula o < 3 nodos
          if (distinctCells <= 1 || ev.independentNodeCount < 3.0) {
            ev.status = 'discarded';
            ev.rejectionReason = 'Falsa alarma local: señal confinada espacialmente sin propagación';
          }
        }
      }

      ev.lastCorrelatedAt = currentTime;
    }

    stopwatch.stop();

    return CorrelationResult(
      activeEvents: events,
      processedTriggers: processed,
      discardedTriggers: discarded,
      evaluatedCount: incomingTriggers.length,
      executionDuration: stopwatch.elapsed,
    );
  }
}
