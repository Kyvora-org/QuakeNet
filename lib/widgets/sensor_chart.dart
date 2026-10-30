import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../models/sensor_sample.dart';

class SensorChart extends StatelessWidget {
  final List<SensorSample> samples;

  const SensorChart({super.key, required this.samples});

  @override
  Widget build(BuildContext context) {
    if (samples.isEmpty) {
      return const Center(child: Text('Esperando datos del sensor...'));
    }

    final double startTime = samples.first.timestamp.millisecondsSinceEpoch.toDouble();

    // Map samples to spots for FlChart
    final List<FlSpot> xSpots = [];
    final List<FlSpot> ySpots = [];
    final List<FlSpot> zSpots = [];
    final List<FlSpot> magSpots = [];

    // Optional visual downsampling: limit the number of drawn points if necessary
    // Currently, taking every sample up to the capacity of the buffer
    for (var i = 0; i < samples.length; i++) {
      final sample = samples[i];
      final double time = (sample.timestamp.millisecondsSinceEpoch - startTime) / 1000.0;
      
      xSpots.add(FlSpot(time, sample.x));
      ySpots.add(FlSpot(time, sample.y));
      zSpots.add(FlSpot(time, sample.z));
      magSpots.add(FlSpot(time, sample.magnitude));
    }

    return LineChart(
      LineChartData(
        minY: -20, // Example scale for typical movement (-2G to 2G)
        maxY: 20,
        lineTouchData: const LineTouchData(enabled: false), // Disable touch for performance
        titlesData: const FlTitlesData(
          show: true,
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 22)),
          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40)),
        ),
        borderData: FlBorderData(show: true),
        gridData: const FlGridData(show: true, drawVerticalLine: false),
        lineBarsData: [
          _createLine(xSpots, Colors.red),
          _createLine(ySpots, Colors.green),
          _createLine(zSpots, Colors.blue),
          _createLine(magSpots, Colors.purple),
        ],
      ),
      duration: Duration.zero, // Disable animations for performance
    );
  }

  LineChartBarData _createLine(List<FlSpot> spots, Color color) {
    return LineChartBarData(
      spots: spots,
      isCurved: false,
      color: color,
      barWidth: 1.5,
      isStrokeCapRound: true,
      dotData: const FlDotData(show: false),
    );
  }
}
