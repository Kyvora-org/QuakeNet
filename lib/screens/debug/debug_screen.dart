import 'package:flutter/material.dart';
import '../../services/sensor_service.dart';
import '../../services/recording_service.dart';
import '../../services/network_service.dart';
import '../../widgets/sensor_chart.dart';
import 'package:geolocator/geolocator.dart';

class DebugScreen extends StatefulWidget {
  final SensorService sensorService;
  final RecordingService recordingService;
  final NetworkService networkService;

  const DebugScreen({
    super.key,
    required this.sensorService,
    required this.recordingService,
    required this.networkService,
  });

  @override
  State<DebugScreen> createState() => _DebugScreenState();
}

class _DebugScreenState extends State<DebugScreen> {
  String _gpsStatus = 'Checking...';
  String _gpsAccuracy = '-';

  @override
  void initState() {
    super.initState();
    _checkGps();
  }

  Future<void> _checkGps() async {
    try {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        setState(() => _gpsStatus = 'UNAVAILABLE (Perm denied)');
        return;
      }
      
      final pos = await Geolocator.getLastKnownPosition();
      if (pos != null) {
        setState(() {
          _gpsStatus = 'AVAILABLE';
          _gpsAccuracy = '${pos.accuracy.toStringAsFixed(1)} m';
        });
      } else {
        setState(() => _gpsStatus = 'AVAILABLE (No fix yet)');
      }
    } catch (e) {
      setState(() => _gpsStatus = 'ERROR');
    }
  }

  String _formatDate(DateTime? time) {
    if (time == null) return 'N/A';
    final local = time.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    final s = local.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  String _maskId(String id) {
    if (id.length <= 8) return id;
    return '${id.substring(0, 4)}...${id.substring(id.length - 4)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Laboratorio & Diagnóstico'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // PANEL DE DIAGNÓSTICO
              ListenableBuilder(
                listenable: Listenable.merge([widget.sensorService, widget.networkService]),
                builder: (context, child) {
                  final node = widget.networkService.node;
                  
                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('DIAGNÓSTICO DEL NODO (Fase 2B)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blueAccent)),
                        const SizedBox(height: 8),
                        Text('Sensor: ${widget.sensorService.status.name.toUpperCase()}'),
                        Text('Power Mode: NORMAL'), // Fixed for now
                        Text('Requested rate: ${widget.sensorService.requestedRate} Hz'),
                        Text('Actual rate: ≈ ${widget.sensorService.actualRate.toStringAsFixed(2)} Hz'),
                        const Divider(height: 16),
                        Text('Node ID: ${_maskId(node.nodeId)}'),
                        Text('Session ID: ${_maskId(node.sessionId)}'),
                        const Divider(height: 16),
                        Text('GPS: $_gpsStatus'),
                        Text('GPS accuracy: $_gpsAccuracy'),
                        const Divider(height: 16),
                        Text('Supabase: ${widget.networkService.status.name.toUpperCase()}'),
                        Text('Upload count: ${widget.networkService.uploadCount}'),
                        Text('Last trigger: ${_formatDate(widget.networkService.lastTriggerTime)}'),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              
              const Text('Gráfica en Tiempo Real', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Expanded(
                child: ListenableBuilder(
                  listenable: widget.sensorService,
                  builder: (context, child) {
                    return SensorChart(samples: widget.sensorService.bufferedSamples);
                  },
                ),
              ),
              const SizedBox(height: 16),
              ListenableBuilder(
                listenable: Listenable.merge([widget.sensorService, widget.recordingService]),
                builder: (context, child) {
                  final isActive = widget.sensorService.status == SensorStatus.active;
                  final isRecording = widget.recordingService.isRecording;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () {
                                if (isActive) {
                                  widget.sensorService.stopMonitoring();
                                } else {
                                  widget.sensorService.startMonitoring(rate: 50);
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                backgroundColor: isActive ? Colors.red.shade100 : Colors.green.shade100,
                                foregroundColor: isActive ? Colors.red.shade900 : Colors.green.shade900,
                              ),
                              child: Text(
                                isActive ? 'DETENER SENSOR' : 'INICIAR SENSOR',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
