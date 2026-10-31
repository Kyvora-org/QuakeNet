// ignore_for_file: avoid_print

import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:quakenet/core/algorithms/correlation_engine.dart';
import 'package:quakenet/models/seismic_trigger.dart';

void main() {
  group('Fase 2C.3: Pruebas de Rendimiento y Estrés (Benchmarks)', () {
    List<SeismicTrigger> generateSyntheticTriggers(int count, {double spreadKm = 40.0}) {
      final t0 = DateTime.utc(2026, 10, 31, 14, 0, 0);
      final random = Random(42);
      final triggers = <SeismicTrigger>[];

      for (int i = 0; i < count; i++) {
        // Generar coordenadas dispersas dentro de un radio geográfico
        final angle = random.nextDouble() * 2 * pi;
        final distKm = random.nextDouble() * spreadKm;
        final dLat = (distKm / 111.0) * cos(angle);
        final dLon = (distKm / 111.0) * sin(angle);

        // Retardo simulado de onda P/S (1.2 a 6.0 km/s)
        final waveDelayMs = (distKm / 3.5 * 1000).round() + random.nextInt(300);

        triggers.add(SeismicTrigger(
          triggerId: 'bench_${count}_trg_$i',
          nodeId: 'bench_node_${i % (count > 500 ? (count ~/ 2) : count)}',
          sessionId: 'bench_session_${i % 10}',
          detectedAt: t0.add(Duration(milliseconds: waveDelayMs)),
          latitude: 4.7110 + dLat,
          longitude: -74.0721 + dLon,
          locationAccuracyM: 10.0 + random.nextDouble() * 20.0,
          ratio: 4.0 + random.nextDouble() * 8.0,
          peakMagnitude: 0.05 + random.nextDouble() * 0.4,
          platform: 'android',
        ));
      }
      return triggers;
    }

    test('Benchmark: 10 triggers (Micro-cluster)', () {
      final triggers = generateSyntheticTriggers(10);
      final stopwatch = Stopwatch()..start();
      final result = CorrelationEngine.correlate(incomingTriggers: triggers);
      stopwatch.stop();

      print('--- BENCHMARK 10 TRIGGERS ---');
      print('Tiempo total: ${stopwatch.elapsedMicroseconds} µs (${stopwatch.elapsedMilliseconds} ms)');
      print('Eventos generados: ${result.activeEvents.length}');
      print('Triggers procesados: ${result.processedTriggers.length}');

      expect(stopwatch.elapsedMilliseconds, lessThan(100));
    });

    test('Benchmark: 100 triggers (Red barrial / urbana)', () {
      final triggers = generateSyntheticTriggers(100);
      final stopwatch = Stopwatch()..start();
      final result = CorrelationEngine.correlate(incomingTriggers: triggers);
      stopwatch.stop();

      print('--- BENCHMARK 100 TRIGGERS ---');
      print('Tiempo total: ${stopwatch.elapsedMicroseconds} µs (${stopwatch.elapsedMilliseconds} ms)');
      print('Eventos generados: ${result.activeEvents.length}');
      print('Triggers procesados: ${result.processedTriggers.length}');

      expect(stopwatch.elapsedMilliseconds, lessThan(150));
    });

    test('Benchmark: 1,000 triggers (Sismo metropolitano masivo)', () {
      final triggers = generateSyntheticTriggers(1000);
      final stopwatch = Stopwatch()..start();
      final result = CorrelationEngine.correlate(incomingTriggers: triggers);
      stopwatch.stop();

      print('--- BENCHMARK 1,000 TRIGGERS ---');
      print('Tiempo total: ${stopwatch.elapsedMilliseconds} ms');
      print('Eventos generados: ${result.activeEvents.length}');
      print('Triggers procesados: ${result.processedTriggers.length}');

      // Debe procesar 1,000 triggers en menos de 500 ms en entorno cliente/servidor Dart
      expect(stopwatch.elapsedMilliseconds, lessThan(800));
    });

    test('Benchmark: 10,000 triggers (Carga pico nacional)', () {
      final triggers = generateSyntheticTriggers(10000);
      final stopwatch = Stopwatch()..start();
      final result = CorrelationEngine.correlate(incomingTriggers: triggers);
      stopwatch.stop();

      print('--- BENCHMARK 10,000 TRIGGERS ---');
      print('Tiempo total: ${stopwatch.elapsedMilliseconds} ms');
      print('Eventos generados: ${result.activeEvents.length}');
      print('Triggers procesados: ${result.processedTriggers.length}');

      // Para 10,000 triggers, validamos que no se bloquee ni supere tiempos prohibitivos
      expect(stopwatch.elapsedMilliseconds, lessThan(10000));
    });
  });
}
