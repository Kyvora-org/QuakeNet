import 'package:flutter/material.dart';
import '../../services/sensor_service.dart';

class SensorStatusCard extends StatelessWidget {
  final SensorService sensorService;

  const SensorStatusCard({super.key, required this.sensorService});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'QUAKENET EXPERIMENTAL',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.blueGrey,
                  ),
              textAlign: TextAlign.center,
            ),
            const Divider(),
            const SizedBox(height: 8),
            _buildRow('Estado del sensor', _statusText(sensorService.status)),
            _buildRow('Dispositivo', 'Android Device'), // Placeholder, can be updated with device_info_plus later
            _buildRow('Plataforma', 'Android'),
            _buildRow('Frecuencia solicitada', '${sensorService.requestedRate} Hz'),
            _buildRow('Frecuencia real', '${sensorService.actualRate.toStringAsFixed(2)} Hz'),
            _buildRow('Muestras', '${sensorService.sampleCount}'),
            _buildRow('Sesión', _formatDuration(sensorService.sessionDuration)),
            const Divider(),
            const SizedBox(height: 8),
            if (sensorService.latestSample != null) ...[
              _buildMetric('X', sensorService.latestSample!.x),
              _buildMetric('Y', sensorService.latestSample!.y),
              _buildMetric('Z', sensorService.latestSample!.z),
              const SizedBox(height: 8),
              _buildMetric('Magnitud', sensorService.latestSample!.magnitude, isBold: true),
            ] else ...[
              const Center(child: Text('Esperando datos...')),
            ]
          ],
        ),
      ),
    );
  }

  Widget _buildRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          Text(value),
        ],
      ),
    );
  }

  Widget _buildMetric(String label, double value, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontWeight: isBold ? FontWeight.bold : FontWeight.w500)),
          Text(value.toStringAsFixed(4), style: TextStyle(fontWeight: isBold ? FontWeight.bold : FontWeight.normal, fontFamily: 'monospace')),
        ],
      ),
    );
  }

  String _statusText(SensorStatus status) {
    switch (status) {
      case SensorStatus.active:
        return '● ACTIVO';
      case SensorStatus.inactive:
        return '○ INACTIVO';
      case SensorStatus.error:
        return '⚠ ERROR';
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$hours:$minutes:$seconds';
  }
}
