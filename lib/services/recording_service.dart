import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/sensor_session.dart';
import '../models/sensor_sample.dart';

class RecordingService extends ChangeNotifier {
  bool _isRecording = false;
  bool get isRecording => _isRecording;

  DateTime? _sessionStartTime;
  String? _sessionId;
  
  final List<SensorSample> _recordedSamples = [];

  void startRecording() {
    if (_isRecording) return;
    _isRecording = true;
    _sessionStartTime = DateTime.now();
    _sessionId = 'SESSION_${_sessionStartTime!.millisecondsSinceEpoch}';
    _recordedSamples.clear();
    notifyListeners();
  }

  void addSample(SensorSample sample) {
    if (!_isRecording) return;
    _recordedSamples.add(sample);
  }

  Future<SensorSession?> stopRecording(String device, String platform, int requestedRate, double actualRate) async {
    if (!_isRecording || _sessionStartTime == null) return null;
    
    _isRecording = false;
    final session = SensorSession(
      sessionId: _sessionId!,
      device: device,
      platform: platform,
      startTime: _sessionStartTime!,
      endTime: DateTime.now(),
      requestedSamplingRate: requestedRate,
      actualSamplingRate: actualRate,
      samples: List.unmodifiable(_recordedSamples),
    );
    
    _sessionStartTime = null;
    _sessionId = null;
    notifyListeners();
    
    return session;
  }

  Future<String> saveSessionToCsv(SensorSession session) async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/${session.sessionId}.csv');
    
    final sink = file.openWrite();
    // Write metadata
    sink.writeln('# QuakeNet Experimental Session');
    sink.writeln('# Session ID: ${session.sessionId}');
    sink.writeln('# Device: ${session.device}');
    sink.writeln('# Platform: ${session.platform}');
    sink.writeln('# Start Time: ${session.startTime.toIso8601String()}');
    sink.writeln('# End Time: ${session.endTime.toIso8601String()}');
    sink.writeln('# Requested Rate: ${session.requestedSamplingRate} Hz');
    sink.writeln('# Actual Rate: ${session.actualSamplingRate} Hz');
    
    // Write headers
    sink.writeln('timestamp,sensorTimestamp,x,y,z,magnitude');
    
    // Write data
    for (final sample in session.samples) {
      sink.writeln('${sample.timestamp.toIso8601String()},${sample.sensorTimestamp},${sample.x},${sample.y},${sample.z},${sample.magnitude}');
    }
    
    await sink.flush();
    await sink.close();
    
    return file.path;
  }

  Future<void> exportSession(String filePath) async {
    final file = File(filePath);
    if (await file.exists()) {
      await Share.shareXFiles([XFile(filePath)], text: 'Exported QuakeNet Session');
    }
  }
}
