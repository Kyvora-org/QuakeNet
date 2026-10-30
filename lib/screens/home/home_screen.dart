import 'dart:io';
import '../../core/config/consensus_config.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/device_node.dart';
import '../../services/sensor_service.dart';
import '../../services/recording_service.dart';
import '../../services/processing_service.dart';
import '../../services/network_service.dart';
import '../../platform/ios_sensor_platform.dart';
import '../../platform/android_sensor_platform.dart';
import '../map/map_screen.dart';
import '../debug/debug_screen.dart';

class HomeScreen extends StatefulWidget {
  final SupabaseClient? supabaseClient;
  final DeviceNode deviceNode;

  const HomeScreen({super.key, this.supabaseClient, required this.deviceNode});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final RecordingService _recordingService;
  late final ProcessingService _processingService;
  late final SensorService _sensorService;
  late final NetworkService _networkService; 

  @override
  void initState() {
    super.initState();
    _recordingService = RecordingService();
    _networkService = NetworkService(
      client: widget.supabaseClient,
      node: widget.deviceNode,
    );
    _processingService = ProcessingService(
      sampleRateHz: ConsensusConfig.samplingRatesHz[PowerMode.normal]!,
      onMovementCandidate: (timestamp, peakMagnitude, staLtaRatio) {
        _networkService.publishMovementCandidate(
          timestamp: timestamp,
          peakMagnitude: peakMagnitude,
          staLtaRatio: staLtaRatio,
          samplingRateHz: _sensorService.actualRate,
        );
      },
    );
    
    if (Platform.isIOS) {
      _sensorService = SensorService(
        IOSSensorPlatform(), 
        recordingService: _recordingService,
        processingService: _processingService,
      );
    } else {
      _sensorService = SensorService(
        AndroidSensorPlatform(), 
        recordingService: _recordingService,
        processingService: _processingService,
      );
    }

    _networkService.connect();

    // Auto-start sensor silently
    _sensorService.startMonitoring(rate: ConsensusConfig.samplingRatesHz[PowerMode.normal]!.toInt());
  }

  @override
  void dispose() {
    _sensorService.dispose();
    _networkService.dispose();
    _processingService.dispose();
    _recordingService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sensors, color: Theme.of(context).colorScheme.primary, size: 22),
            const SizedBox(width: 8),
            const Text('QUAKENET'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.bug_report_outlined, size: 20),
            tooltip: 'Laboratorio',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => DebugScreen(
                    sensorService: _sensorService,
                    recordingService: _recordingService,
                    networkService: _networkService,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          const SizedBox(height: 12),
          // -- Earthquake feed header --
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Icon(Icons.public, size: 16, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 6),
                Text(
                  'Actividad Sísmica Reciente',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 14),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // -- Map --
          const Expanded(
            child: Padding(
              padding: EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: ClipRRect(
                borderRadius: BorderRadius.all(Radius.circular(12)),
                child: MapScreen(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
