import 'package:flutter/material.dart';
import '../../services/sensor_service.dart';
import '../../services/recording_service.dart';
import '../../services/network_service.dart';
import '../../core/config/consensus_config.dart';
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
  String _gpsAccuracy = 'NOT AVAILABLE';
  bool _isLoadingEvents = false;
  List<Map<String, dynamic>> _correlatedEvents = [];

  @override
  void initState() {
    super.initState();
    _checkGps();
    _fetchCorrelatedEvents();
  }

  Future<void> _fetchCorrelatedEvents() async {
    if (!mounted) return;
    setState(() => _isLoadingEvents = true);
    try {
      final events = await widget.networkService.fetchRecentCorrelatedEvents();
      if (mounted) {
        setState(() {
          _correlatedEvents = events;
          _isLoadingEvents = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingEvents = false);
      }
    }
  }

  Future<void> _checkGps() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) setState(() => _gpsStatus = 'UNAVAILABLE (GPS deshabilitado)');
        return;
      }

      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        if (mounted) setState(() => _gpsStatus = 'UNAVAILABLE (Permiso denegado)');
        return;
      }
      
      final pos = await Geolocator.getLastKnownPosition();
      if (pos != null) {
        if (mounted) {
          setState(() {
            _gpsStatus = 'AVAILABLE';
            _gpsAccuracy = '${pos.accuracy.toStringAsFixed(1)} m';
          });
        }
      } else {
        if (mounted) setState(() => _gpsStatus = 'AVAILABLE (Esperando fix)');
      }
    } catch (e) {
      if (mounted) setState(() => _gpsStatus = 'ERROR: $e');
    }
  }

  String _formatDate(DateTime? time) {
    if (time == null) return 'NOT AVAILABLE';
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
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reintentar GPS',
            onPressed: _checkGps,
          )
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // PANEL DE DIAGNÓSTICO (FASE 2B.1)
              ListenableBuilder(
                listenable: Listenable.merge([widget.sensorService, widget.networkService]),
                builder: (context, child) {
                  final node = widget.networkService.node;
                  final net = widget.networkService;
                  final sensor = widget.sensorService;
                  
                  return Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.monitor_heart, size: 18, color: Colors.blueAccent),
                            SizedBox(width: 8),
                            Text(
                              'DIAGNÓSTICO DEL NODO (Fase 2B.1)',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blueAccent),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text('SENSOR: ${sensor.status.name.toUpperCase()}'),
                        Text('POWER MODE: ${sensor.powerMode.name.toUpperCase()}'),
                        Text('REQUESTED RATE: ${sensor.requestedRate} Hz'),
                        Text('ACTUAL RATE: ${sensor.actualRate > 0 ? "≈ ${sensor.actualRate.toStringAsFixed(1)} Hz" : "CALCULATING..."}'),
                        const Divider(height: 16),
                        Text('NODE ID: ${_maskId(node.nodeId)}'),
                        Text('SESSION ID: ${_maskId(node.sessionId)}'),
                        const Divider(height: 16),
                        Text('GPS: $_gpsStatus'),
                        Text('GPS ACCURACY: $_gpsAccuracy'),
                        const Divider(height: 16),
                        Text('NETWORK: ${net.status.name.toUpperCase()}'),
                        Text('PENDING TRIGGERS: ${net.pendingCount}'),
                        Text('UPLOAD COUNT: ${net.uploadCount}'),
                        Text('LAST TRIGGER: ${_formatDate(net.lastTriggerTime)}'),
                        Text('LAST UPLOAD: ${_formatDate(net.lastUploadTime)}'),
                        Text('LAST ERROR: ${net.errorMessage ?? "NONE"}'),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 14),

              // SELECTOR DE MODO DE ENERGÍA
              const Text('Selector de Modo de Consumo', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 8),
              ListenableBuilder(
                listenable: widget.sensorService,
                builder: (context, child) {
                  return Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('Low Power (25 Hz)'),
                        selected: widget.sensorService.powerMode == PowerMode.lowPower,
                        onSelected: (val) {
                          if (val) widget.sensorService.setPowerMode(PowerMode.lowPower);
                        },
                      ),
                      ChoiceChip(
                        label: const Text('Normal (50 Hz)'),
                        selected: widget.sensorService.powerMode == PowerMode.normal,
                        onSelected: (val) {
                          if (val) widget.sensorService.setPowerMode(PowerMode.normal);
                        },
                      ),
                      ChoiceChip(
                        label: const Text('Research (100 Hz)'),
                        selected: widget.sensorService.powerMode == PowerMode.research,
                        onSelected: (val) {
                          if (val) widget.sensorService.setPowerMode(PowerMode.research);
                        },
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 14),

              // GRÁFICA EN TIEMPO REAL
              const Text('Gráfica en Tiempo Real', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 8),
              SizedBox(
                height: 180,
                child: ListenableBuilder(
                  listenable: widget.sensorService,
                  builder: (context, child) {
                    return SensorChart(samples: widget.sensorService.bufferedSamples);
                  },
                ),
              ),
              const SizedBox(height: 14),

              // CONTROLES DE ACCIÓN
              ListenableBuilder(
                listenable: widget.sensorService,
                builder: (context, child) {
                  final isActive = widget.sensorService.status == SensorStatus.active;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ElevatedButton(
                        onPressed: () {
                          if (isActive) {
                            widget.sensorService.stopMonitoring();
                          } else {
                            widget.sensorService.startMonitoring();
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          backgroundColor: isActive ? Colors.red.shade900 : Colors.green.shade800,
                          foregroundColor: Colors.white,
                        ),
                        child: Text(
                          isActive ? 'DETENER SENSOR' : 'INICIAR SENSOR',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.flash_on, size: 18),
                        label: const Text('GENERAR TRIGGER SINTÉTICO (TEST)'),
                        onPressed: () {
                          // Genera un trigger sintético controlado para verificar el pipeline Supabase
                          widget.networkService.publishMovementCandidate(
                            timestamp: DateTime.now().toUtc(),
                            peakMagnitude: 0.15,
                            staLtaRatio: 5.5,
                            samplingRateHz: widget.sensorService.actualRate > 0 
                                ? widget.sensorService.actualRate 
                                : widget.sensorService.requestedRate.toDouble(),
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Trigger sintético encolado para verificación de transporte.'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        },
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),

              // SECCIÓN DE EVENTOS CORRELACIONADOS (FASE 2C)
              _buildCorrelatedEventsSection(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCorrelatedEventsSection() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
      ),
      child: ExpansionTile(
        initiallyExpanded: false,
        leading: const Icon(Icons.hub_outlined, color: Colors.amberAccent),
        title: const Text(
          'EVENTOS CORRELACIONADOS (Fase 2C)',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.amberAccent),
        ),
        subtitle: Text(
          '${_correlatedEvents.length} evento(s) detectados por el motor de consenso',
          style: const TextStyle(fontSize: 11, color: Colors.white70),
        ),
        childrenPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        children: [
          // Banner de descargo de responsabilidad obligatorio
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.amber.shade900.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.amber.shade700),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'DATOS EXPERIMENTALES — NO CONSTITUYE ALERTA PÚBLICA NI CONFIRMACIÓN OFICIAL. '
                    'Los resultados reflejan correlaciones estadísticas internas de nodos ciudadanos.',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.amber),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Barra de actualización
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Eventos en red (Supabase)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              IconButton(
                icon: const Icon(Icons.refresh, size: 20),
                tooltip: 'Actualizar eventos',
                onPressed: _isLoadingEvents ? null : _fetchCorrelatedEvents,
              ),
            ],
          ),
          if (_isLoadingEvents) const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: LinearProgressIndicator(),
          ),

          if (!_isLoadingEvents && _correlatedEvents.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              alignment: Alignment.center,
              child: const Text(
                'No hay eventos sísmicos correlacionados activos en la base de datos.\n'
                'Los eventos se forman cuando múltiples nodos independientes detectan un frente de onda coherente.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: Colors.white54, fontStyle: FontStyle.italic),
              ),
            ),

          ..._correlatedEvents.map((ev) {
            final status = ev['status']?.toString() ?? 'candidate';
            final confidence = (ev['confidence'] as num?)?.toDouble() ?? 0.0;
            final indepNodes = (ev['independent_node_count'] as num?)?.toDouble() ?? 0.0;
            final nodeCount = ev['node_count'] ?? 0;
            final clusters = ev['spatial_cluster_count'] ?? 1;
            final lat = (ev['latitude'] as num?)?.toDouble();
            final lon = (ev['longitude'] as num?)?.toDouble();
            final radiusKm = (ev['estimated_radius_km'] as num?)?.toDouble() ?? 0.0;
            final avgRatio = (ev['avg_sta_lta'] as num?)?.toDouble();
            final maxPeak = (ev['max_peak_magnitude'] as num?)?.toDouble();
            final reason = ev['rejection_reason']?.toString();
            final detectedAt = DateTime.tryParse(ev['detected_at']?.toString() ?? '')?.toLocal();

            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              color: Colors.black26,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(color: _statusColor(status).withValues(alpha: 0.5)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: _statusColor(status),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            status.toUpperCase(),
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                        ),
                        Text(
                          _formatDate(detectedAt),
                          style: const TextStyle(fontSize: 11, color: Colors.white70),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Centroide: ${lat != null ? "${lat.toStringAsFixed(4)}, ${lon?.toStringAsFixed(4)}" : "Sin GPS"} (r ≈ ${radiusKm.toStringAsFixed(1)} km)',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Nodos: $nodeCount (Indep: ${indepNodes.toStringAsFixed(1)}) | Celdas: $clusters',
                      style: const TextStyle(fontSize: 11, color: Colors.white70),
                    ),
                    Text(
                      'Confianza: ${confidence.toStringAsFixed(1)}% | STA/LTA Prom: ${avgRatio?.toStringAsFixed(1) ?? "N/A"} | Pico: ${maxPeak != null ? "${maxPeak.toStringAsFixed(3)}g" : "N/A"}',
                      style: const TextStyle(fontSize: 11, color: Colors.white70),
                    ),
                    if (reason != null && reason.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Descarte: $reason',
                        style: TextStyle(fontSize: 10, color: Colors.red.shade300, fontStyle: FontStyle.italic),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'high_confidence':
        return Colors.green.shade800;
      case 'correlated':
        return Colors.amber.shade900;
      case 'discarded':
        return Colors.red.shade900;
      case 'candidate':
      default:
        return Colors.blueGrey.shade700;
    }
  }
}
