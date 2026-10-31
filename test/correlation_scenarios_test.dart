import 'package:flutter_test/flutter_test.dart';
import 'package:quakenet/core/algorithms/correlation_engine.dart';
import 'package:quakenet/models/seismic_trigger.dart';

void main() {
  group('Fase 2C.3: Pruebas Unitarias del Motor de Consenso', () {
    test('Cálculo de Distancia Haversine precisa', () {
      // Bogotá a Medellín: ~240 km
      final dist = CorrelationEngine.calculateDistanceKm(4.7110, -74.0721, 6.2442, -75.5812);
      expect(dist, greaterThan(230.0));
      expect(dist, lessThan(250.0));
    });

    test('Spatial Hashing discretiza celdas de ~500m', () {
      final cell1 = CorrelationEngine.getSpatialCell(4.7111, -74.0721, 'node1');
      final cell2 = CorrelationEngine.getSpatialCell(4.7113, -74.0723, 'node2');
      final cellFar = CorrelationEngine.getSpatialCell(4.8500, -74.1500, 'node3');

      expect(cell1, equals(cell2)); // Mismo edificio / cuadra
      expect(cell1, isNot(equals(cellFar)));
    });

    test('Atenuación Anti-Edificio: 50 teléfonos en el mismo edificio no alcanzan 3 nodos independientes', () {
      final triggers = List<SeismicTrigger>.generate(50, (i) => SeismicTrigger(
        triggerId: 'trg_$i',
        nodeId: 'phone_$i',
        sessionId: 'ses_$i',
        detectedAt: DateTime.utc(2026, 10, 31, 12, 0, 0),
        latitude: 4.7110, // Mismo punto
        longitude: -74.0720,
        ratio: 5.5,
        peakMagnitude: 0.15,
        platform: 'android',
      ));

      final nIndep = CorrelationEngine.calculateIndependentNodes(triggers);
      // w(50) = 1.0 + 0.3 * ln(50) = 1.0 + 0.3 * 3.912 = 2.17
      expect(nIndep, greaterThan(2.0));
      expect(nIndep, lessThan(2.5));
    });

    test('Validación Cinemática de Velocidad de Onda Sísmica', () {
      final t0 = DateTime.utc(2026, 10, 31, 12, 0, 0);

      final triggerA = SeismicTrigger(
        triggerId: 'trg_a',
        nodeId: 'node_a',
        sessionId: 'ses_a',
        detectedAt: t0,
        latitude: 4.7000,
        longitude: -74.0000,
        ratio: 6.0,
        platform: 'android',
      );

      // Trigger B a 15 km de distancia, detectado 4 segundos después (v_app = 3.75 km/s -> onda S física)
      final triggerB = SeismicTrigger(
        triggerId: 'trg_b',
        nodeId: 'node_b',
        sessionId: 'ses_b',
        detectedAt: t0.add(const Duration(seconds: 4)),
        latitude: 4.8350,
        longitude: -74.0000,
        ratio: 5.8,
        platform: 'android',
      );

      // Trigger C a 30 km de distancia, detectado 0.01 segundos después (v_app = 3000 km/s -> físicamente imposible)
      final triggerC = SeismicTrigger(
        triggerId: 'trg_c',
        nodeId: 'node_c',
        sessionId: 'ses_c',
        detectedAt: t0.add(const Duration(milliseconds: 10)),
        latitude: 4.9700,
        longitude: -74.0000,
        ratio: 5.8,
        platform: 'android',
      );

      expect(CorrelationEngine.isKinematicallyConsistent(triggerA, triggerB), isTrue);
      expect(CorrelationEngine.isKinematicallyConsistent(triggerA, triggerC), isFalse);
    });
  });

  group('Fase 2C.3: Simulaciones Sintéticas (Escenarios A hasta I)', () {
    // ESCENARIO A: Evento Coherente (Multi-Nodo Distribuido)
    test('Escenario A - Evento coherente progresa a estado correlated', () {
      final t0 = DateTime.utc(2026, 10, 31, 12, 0, 0);
      final triggers = <SeismicTrigger>[];

      // 12 nodos independientes en 12 ubicaciones distintas (separadas por ~2.5 km)
      for (int i = 0; i < 12; i++) {
        triggers.add(SeismicTrigger(
          triggerId: 'trg_a_$i',
          nodeId: 'node_a_$i',
          sessionId: 'ses_a',
          detectedAt: t0.add(Duration(milliseconds: i * 600)),
          latitude: 4.7000 + (i * 0.018),
          longitude: -74.0000 + (i * 0.015),
          locationAccuracyM: 20.0,
          ratio: 6.5,
          peakMagnitude: 0.25,
          platform: 'android',
        ));
      }

      final result = CorrelationEngine.correlate(incomingTriggers: triggers, now: t0.add(const Duration(seconds: 10)));

      expect(result.activeEvents.length, equals(1));
      final event = result.activeEvents.first;
      expect(event.status, equals('correlated'));
      expect(event.spatialClusterCount, greaterThanOrEqualTo(10));
      expect(event.independentNodeCount, greaterThanOrEqualTo(10.0));
      expect(event.confidence, greaterThanOrEqualTo(40.0));
    });

    // ESCENARIO B: Movimiento Local (Mismo Edificio)
    test('Escenario B — 50 teléfonos en la misma sala no generan falso consenso', () {
      final t0 = DateTime.utc(2026, 10, 31, 12, 0, 0);
      final triggers = List<SeismicTrigger>.generate(50, (i) => SeismicTrigger(
        triggerId: 'trg_b_$i',
        nodeId: 'node_b_$i',
        sessionId: 'ses_b_$i',
        detectedAt: t0.add(Duration(milliseconds: i * 50)),
        latitude: 4.71100 + (i * 0.00001), // Máx 50 metros de separación
        longitude: -74.07200 + (i * 0.00001),
        ratio: 7.0,
        peakMagnitude: 0.3,
        platform: 'android',
      ));

      // Evaluación inicial
      final result = CorrelationEngine.correlate(incomingTriggers: triggers, now: t0.add(const Duration(seconds: 5)));
      expect(result.activeEvents.length, equals(1));
      final event = result.activeEvents.first;

      // NO debe ser ni correlated ni high_confidence
      expect(event.status, equals('candidate'));
      expect(event.spatialClusterCount, equals(1));
      expect(event.independentNodeCount, lessThan(3.0));
      expect(event.confidence, lessThan(35.0));

      // Tras 95 segundos sin propagación espacial, debe descartarse
      final agedResult = CorrelationEngine.correlate(
        incomingTriggers: [],
        existingEvents: [event],
        now: t0.add(const Duration(seconds: 95)),
      );
      expect(agedResult.activeEvents.first.status, equals('discarded'));
      expect(agedResult.activeEvents.first.rejectionReason, contains('Falsa alarma local'));
    });

    // ESCENARIO C: Actividad Aleatoria (Ruido No Correlacionado)
    test('Escenario C — Dispositivos dispersos en horarios y lugares incompatibles no forman clusters', () {
      final t0 = DateTime.utc(2026, 10, 31, 12, 0, 0);
      final triggers = [
        // Bogotá
        SeismicTrigger(
          triggerId: 'trg_c_1',
          nodeId: 'node_c_1',
          sessionId: 'ses_c_1',
          detectedAt: t0,
          latitude: 4.7110,
          longitude: -74.0721,
          ratio: 4.0,
          platform: 'android',
        ),
        // Medellín (a 240 km)
        SeismicTrigger(
          triggerId: 'trg_c_2',
          nodeId: 'node_c_2',
          sessionId: 'ses_c_2',
          detectedAt: t0.add(const Duration(seconds: 3)),
          latitude: 6.2442,
          longitude: -75.5812,
          ratio: 4.2,
          platform: 'android',
        ),
        // Cali (a 300 km y 5 minutos después)
        SeismicTrigger(
          triggerId: 'trg_c_3',
          nodeId: 'node_c_3',
          sessionId: 'ses_c_3',
          detectedAt: t0.add(const Duration(minutes: 5)),
          latitude: 3.4516,
          longitude: -76.5320,
          ratio: 4.5,
          platform: 'android',
        ),
      ];

      final result = CorrelationEngine.correlate(
        incomingTriggers: triggers,
        now: t0.add(const Duration(minutes: 7)),
      );

      // No se forma ningún evento
      expect(result.activeEvents.isEmpty, isTrue);
      // Todos los triggers aislados caducados se marcan como descartados
      expect(result.discardedTriggers.length, equals(3));
    });

    // ESCENARIO D: Triggers Duplicados (Spam / Replay Attack)
    test('Escenario D — Un nodo enviando repetidamente no incrementa artificialmente el consenso', () {
      final t0 = DateTime.utc(2026, 10, 31, 12, 0, 0);
      // Mismo nodo enviando 10 triggers en 2 segundos
      final spamTriggers = List<SeismicTrigger>.generate(10, (i) => SeismicTrigger(
        triggerId: 'spam_$i',
        nodeId: 'spammer_node_99',
        sessionId: 'ses_99',
        detectedAt: t0.add(Duration(milliseconds: i * 200)),
        latitude: 4.7110,
        longitude: -74.0721,
        ratio: 8.0,
        platform: 'android',
      ));

      final result = CorrelationEngine.correlate(incomingTriggers: spamTriggers, now: t0.add(const Duration(seconds: 5)));

      // 9 triggers deben ser descartados por filtro anti-cooldown
      expect(result.discardedTriggers.length, equals(9));
      // No debe formarse ningún evento (se requiere al menos 3 nodos)
      expect(result.activeEvents.isEmpty, isTrue);
    });

    // ESCENARIO E: Datos GPS Ausentes
    test('Escenario E — Nodos sin GPS se asocian temporalmente sin alterar centroide geográfico', () {
      final t0 = DateTime.utc(2026, 10, 31, 12, 0, 0);
      final triggers = [
        SeismicTrigger(
          triggerId: 'trg_gps_1',
          nodeId: 'node_gps_1',
          sessionId: 'ses_1',
          detectedAt: t0,
          latitude: 4.7000,
          longitude: -74.0000,
          ratio: 6.0,
          platform: 'android',
        ),
        SeismicTrigger(
          triggerId: 'trg_gps_2',
          nodeId: 'node_gps_2',
          sessionId: 'ses_2',
          detectedAt: t0.add(const Duration(milliseconds: 500)),
          latitude: 4.7100,
          longitude: -74.0100,
          ratio: 6.2,
          platform: 'android',
        ),
        SeismicTrigger(
          triggerId: 'trg_gps_3',
          nodeId: 'node_gps_3',
          sessionId: 'ses_3',
          detectedAt: t0.add(const Duration(milliseconds: 800)),
          latitude: 4.7050,
          longitude: -74.0050,
          ratio: 5.9,
          platform: 'android',
        ),
        // Nodo sin GPS
        SeismicTrigger(
          triggerId: 'trg_no_gps',
          nodeId: 'node_indoor',
          sessionId: 'ses_indoor',
          detectedAt: t0.add(const Duration(seconds: 1)),
          latitude: null,
          longitude: null,
          ratio: 5.5,
          platform: 'android',
        ),
      ];

      final result = CorrelationEngine.correlate(incomingTriggers: triggers, now: t0.add(const Duration(seconds: 2)));
      expect(result.activeEvents.length, equals(1));
      final event = result.activeEvents.first;

      expect(event.nodeCount, equals(4));
      // El centroide debe basarse únicamente en los 3 nodos con GPS
      expect(event.latitude, closeTo(4.7050, 0.005));
      expect(event.longitude, closeTo(-74.0050, 0.005));
    });

    // ESCENARIO F: Datos Anómalos (Filtro de Outliers)
    test('Escenario F — Picos anómalos o extremos son amortiguados en la calidad', () {
      final normalTrg = SeismicTrigger(
        triggerId: 'norm',
        nodeId: 'n1',
        sessionId: 's1',
        detectedAt: DateTime.utc(2026, 10, 31),
        latitude: 4.7,
        longitude: -74.0,
        ratio: 6.0,
        peakMagnitude: 0.15,
        locationAccuracyM: 20.0,
        platform: 'android',
      );

      final anomalousShockTrg = SeismicTrigger(
        triggerId: 'shock',
        nodeId: 'n2',
        sessionId: 's2',
        detectedAt: DateTime.utc(2026, 10, 31),
        latitude: 4.7,
        longitude: -74.0,
        ratio: 45.0,
        peakMagnitude: 12.0, // Golpe directo al teléfono (12g)
        locationAccuracyM: 20.0,
        platform: 'android',
      );

      final qNormal = CorrelationEngine.calculateTriggerQuality(normalTrg);
      final qShock = CorrelationEngine.calculateTriggerQuality(anomalousShockTrg);

      // La calidad del shock mecánico cae drásticamente debido a la penalización de amplitud extrema
      expect(qNormal, greaterThan(0.6));
      expect(qShock, lessThan(qNormal));
    });

    // ESCENARIO G: Llegada Tardía (Late-Arrival Triggers)
    test('Escenario G — Trigger que llega tarde actualiza evento sin duplicarlo', () {
      final t0 = DateTime.utc(2026, 10, 31, 12, 0, 0);

      // Evento inicial con 3 triggers
      final initialTriggers = List<SeismicTrigger>.generate(3, (i) => SeismicTrigger(
        triggerId: 'init_$i',
        nodeId: 'node_init_$i',
        sessionId: 'ses_init',
        detectedAt: t0.add(Duration(milliseconds: i * 300)),
        latitude: 4.700 + (i * 0.01),
        longitude: -74.000 + (i * 0.01),
        ratio: 5.5,
        platform: 'android',
      ));

      final initialResult = CorrelationEngine.correlate(incomingTriggers: initialTriggers, now: t0.add(const Duration(seconds: 2)));
      expect(initialResult.activeEvents.length, equals(1));
      final eventId = initialResult.activeEvents.first.id;
      expect(initialResult.activeEvents.first.nodeCount, equals(3));

      // Trigger que llega 8 segundos después pero con timestamp compatible
      final lateTrigger = SeismicTrigger(
        triggerId: 'late_1',
        nodeId: 'node_late_1',
        sessionId: 'ses_late',
        detectedAt: t0.add(const Duration(seconds: 4)),
        latitude: 4.720,
        longitude: -74.020,
        ratio: 6.0,
        platform: 'android',
      );

      final updatedResult = CorrelationEngine.correlate(
        incomingTriggers: [lateTrigger],
        existingEvents: initialResult.activeEvents,
        now: t0.add(const Duration(seconds: 10)),
      );

      // Debe mantenerse exactamente 1 evento con el mismo ID
      expect(updatedResult.activeEvents.length, equals(1));
      expect(updatedResult.activeEvents.first.id, equals(eventId));
      expect(updatedResult.activeEvents.first.nodeCount, equals(4));
    });

    // ESCENARIO H: Alta Densidad de Nodos (Comparación 100 en edificio vs 100 distribuidos)
    test('Escenario H — 120 nodos en un edificio NO logran alta confianza; 120 distribuidos SÍ', () {
      final t0 = DateTime.utc(2026, 10, 31, 12, 0, 0);

      // H.1: 120 nodos en un solo edificio
      final buildingTriggers = List<SeismicTrigger>.generate(120, (i) => SeismicTrigger(
        triggerId: 'bld_$i',
        nodeId: 'node_bld_$i',
        sessionId: 'ses_bld',
        detectedAt: t0.add(Duration(milliseconds: (i % 20) * 100)),
        latitude: 4.7110,
        longitude: -74.0720,
        ratio: 7.0,
        platform: 'android',
      ));

      final resultBld = CorrelationEngine.correlate(incomingTriggers: buildingTriggers, now: t0.add(const Duration(seconds: 5)));
      final eventBld = resultBld.activeEvents.first;

      // N_indep no supera ~2.5 y NO alcanza high_confidence
      expect(eventBld.independentNodeCount, lessThan(3.0));
      expect(eventBld.status, isNot(equals('high_confidence')));

      // H.2: 120 nodos distribuidos en 12 cuadrículas geográficas diferentes (> 20 km de extensión)
      final distributedTriggers = <SeismicTrigger>[];
      for (int cell = 0; cell < 12; cell++) {
        for (int i = 0; i < 10; i++) {
          distributedTriggers.add(SeismicTrigger(
            triggerId: 'dist_${cell}_$i',
            nodeId: 'node_dist_${cell}_$i',
            sessionId: 'ses_dist',
            detectedAt: t0.add(Duration(milliseconds: cell * 800 + i * 50)),
            latitude: 4.600 + (cell * 0.03),
            longitude: -74.100 + (cell * 0.02),
            locationAccuracyM: 15.0,
            ratio: 8.0,
            peakMagnitude: 0.35,
            platform: 'android',
          ));
        }
      }

      final resultDist = CorrelationEngine.correlate(incomingTriggers: distributedTriggers, now: t0.add(const Duration(seconds: 12)));
      final eventDist = resultDist.activeEvents.first;

      // Debe alcanzar high_confidence debido a la dispersión espacial real y alto consenso
      expect(eventDist.spatialClusterCount, greaterThanOrEqualTo(10));
      expect(eventDist.independentNodeCount, greaterThan(15.0));
      expect(eventDist.confidence, greaterThanOrEqualTo(45.0));
    });

    // ESCENARIO I: Concurrencia e Idempotencia
    test('Escenario I — Ejecutar dos veces la misma lista de triggers produce resultado idempotente', () {
      final t0 = DateTime.utc(2026, 10, 31, 12, 0, 0);
      final triggers = List<SeismicTrigger>.generate(5, (i) => SeismicTrigger(
        triggerId: 'idem_$i',
        nodeId: 'node_idem_$i',
        sessionId: 'ses_idem',
        detectedAt: t0.add(Duration(milliseconds: i * 200)),
        latitude: 4.700 + (i * 0.01),
        longitude: -74.000 + (i * 0.01),
        ratio: 6.0,
        platform: 'android',
      ));

      // Primera ejecución
      final run1 = CorrelationEngine.correlate(incomingTriggers: triggers, now: t0.add(const Duration(seconds: 2)));
      expect(run1.activeEvents.length, equals(1));
      final event1 = run1.activeEvents.first;

      // Segunda ejecución simultánea con los mismos triggers sobre el evento existente
      final run2 = CorrelationEngine.correlate(
        incomingTriggers: triggers,
        existingEvents: [event1],
        now: t0.add(const Duration(seconds: 2)),
      );

      // No se duplica el evento
      expect(run2.activeEvents.length, equals(1));
      expect(run2.activeEvents.first.id, equals(event1.id));
    });
  });
}
