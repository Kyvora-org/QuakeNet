import 'package:flutter_test/flutter_test.dart';
import 'package:quakenet/core/config/consensus_config.dart';

void main() {
  group('ConsensusConfig', () {
    test('minNodesHighConfidence is 100', () {
      expect(ConsensusConfig.minNodesHighConfidence, 100);
    });

    test('clusteringTimeWindowMs is 15 seconds', () {
      expect(ConsensusConfig.clusteringTimeWindowMs, 15000);
    });

    test('clusteringDistanceRadiusKm is 50 km', () {
      expect(ConsensusConfig.clusteringDistanceRadiusKm, 50.0);
    });

    test('all PowerMode values have defined sampling rates', () {
      expect(ConsensusConfig.samplingRatesHz.containsKey(PowerMode.lowPower), true);
      expect(ConsensusConfig.samplingRatesHz.containsKey(PowerMode.normal), true);
      expect(ConsensusConfig.samplingRatesHz.containsKey(PowerMode.research), true);
    });

    test('lowPower rate is 25 Hz', () {
      expect(ConsensusConfig.samplingRatesHz[PowerMode.lowPower], 25.0);
    });

    test('normal rate is 50 Hz', () {
      expect(ConsensusConfig.samplingRatesHz[PowerMode.normal], 50.0);
    });

    test('research rate is 100 Hz', () {
      expect(ConsensusConfig.samplingRatesHz[PowerMode.research], 100.0);
    });
  });
}
