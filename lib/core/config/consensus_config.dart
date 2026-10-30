/// Configuración central de parámetros de consenso para QuakeNet.
/// 
/// Estos valores determinan cómo los múltiples triggers independientes (nodos) 
/// se interpretan colectivamente para generar un evento correlacionado de alta confianza.
class ConsensusConfig {
  /// INITIAL HIGH-CONFIDENCE CONSENSUS THRESHOLD
  /// 
  /// Cantidad mínima inicial de nodos INDEPENDIENTES requeridos 
  /// para considerar un grupo de triggers como un "High Confidence Event".
  /// NOTA: No es una regla rígida, es un parámetro base para futuras pruebas.
  static const int minNodesHighConfidence = 100;

  /// El tiempo máximo en milisegundos para agrupar múltiples triggers 
  /// y considerarlos parte del mismo evento sísmico candidato.
  static const int clusteringTimeWindowMs = 15000; // 15 segundos

  /// La distancia máxima en kilómetros para agrupar múltiples triggers
  /// y considerarlos del mismo origen espacial.
  static const double clusteringDistanceRadiusKm = 50.0;

  /// Modos operativos conceptuales del sensor.
  /// Define la estrategia de muestreo (sampling rate) para equilibrar 
  /// consumo de batería vs. fidelidad científica.
  static const Map<PowerMode, double> samplingRatesHz = {
    PowerMode.lowPower: 25.0,  // Consume poca batería, suficiente para sismos fuertes.
    PowerMode.normal: 50.0,    // Muestreo recomendado (balanceado).
    PowerMode.research: 100.0, // Solo para pruebas, drena rápido la batería.
  };
}

/// Modos de operación para QuakeNet
enum PowerMode {
  /// Monitoreo activo de fondo con el menor consumo de energía posible.
  lowPower,
  
  /// Monitoreo general
  normal,
  
  /// Monitoreo de alta fidelidad, desactiva protecciones de batería
  research,
  
  /// Nodo inactivo (no aporta datos a la red)
  disabled,
}
