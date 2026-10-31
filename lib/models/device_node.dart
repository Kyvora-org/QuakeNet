import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Identidad anónima y de sesión para un nodo experimental de QuakeNet.
///
/// Conserva el anonimato (nodeId persiste pero no se vincula a datos personales).
/// No utiliza IMEI, MAC, teléfono ni cuentas de usuario.
class DeviceNode {
  final String nodeId;
  final String sessionId;
  final String platform;
  final DateTime createdAt;
  final Map<String, bool> sensorCapabilities;

  const DeviceNode({
    required this.nodeId,
    required this.sessionId,
    required this.platform,
    required this.createdAt,
    required this.sensorCapabilities,
  });

  /// Carga el nodeId desde preferencias persistentes o crea uno si no existe.
  /// Además, genera un nuevo sessionId para la ejecución actual.
  static Future<DeviceNode> loadExperimental({required String platform}) async {
    final prefs = await SharedPreferences.getInstance();
    
    String? existingNodeId = prefs.getString('quakenet_node_id');
    if (existingNodeId == null) {
      existingNodeId = const Uuid().v4();
      await prefs.setString('quakenet_node_id', existingNodeId);
    }
    
    final currentSessionId = const Uuid().v4();
    
    return DeviceNode(
      nodeId: existingNodeId,
      sessionId: currentSessionId,
      platform: platform,
      createdAt: DateTime.now().toUtc(),
      sensorCapabilities: const {'accelerometer': true},
    );
  }

  /// Renueva el Session ID para una nueva sesión de monitoreo conservando el mismo Node ID.
  DeviceNode renewSession() {
    return DeviceNode(
      nodeId: nodeId,
      sessionId: const Uuid().v4(),
      platform: platform,
      createdAt: DateTime.now().toUtc(),
      sensorCapabilities: sensorCapabilities,
    );
  }

  Map<String, dynamic> toMap() => {
        'nodeId': nodeId,
        'sessionId': sessionId,
        'platform': platform,
        'createdAt': createdAt.toIso8601String(),
        'sensorCapabilities': sensorCapabilities,
      };
}
