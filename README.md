# QuakeNet

Red sísmica distribuida para la detección de eventos telúricos mediante sensores móviles y consenso de nodos.

## Descripción

QuakeNet es una plataforma móvil desarrollada en Flutter para Android e iOS que busca construir una red de consenso ciudadano para la detección distribuida de eventos sísmicos. Mediante el acelerómetro interno de los dispositivos, procesamiento digital de señales local (filtros pasa-altas, STA/LTA) y un backend distribuido en Supabase, QuakeNet procesa triggers en tiempo real sin requerir hardware sismológico costoso.

> **Principio fundamental:** QuakeNet no "predice" terremotos. Detecta anomalías compatibles con señales sísmicas, agrupa triggers distribuidos espacial y temporalmente, y genera candidatos de consenso cuando múltiples nodos independientes reportan actividad simultánea.

## Arquitectura y Componentes

- **Adquisición de Sensores**:
  - Android: `SensorManager` con delay en microsegundos vía Kotlin MethodChannel.
  - iOS: `CMMotionManager` vía CoreMotion en Swift.
- **Procesamiento de Señal (Local)**:
  - Filtro IIR Pasa-Altas (Butterworth 2do orden, fc = 0.5 Hz).
  - Buffer circular de muestras.
  - Algoritmo STA/LTA (*Short-Term Average / Long-Term Average*) para detección de envolventes de ondas P/S.
- **Red y Consenso (Supabase)**:
  - Inserción anónima de triggers sísmicos individuales (`triggers`).
  - Correlación espacial y temporal en backend para agrupar en `seismic_events`.
  - Umbral configurable de alta confianza (ej. 100 nodos independientes).
- **Monitoreo Externo**:
  - Integración en tiempo real con datos oficiales del SGC (Servicio Geológico Colombiano).

## Modos de Consumo

- **Low Power (25 Hz)**: Optimizado para monitoreo continuo con bajo impacto de batería.
- **Normal (50 Hz)**: Frecuencia de muestreo estándar recomendada.
- **Research (100 Hz)**: Alta resolución para análisis detallado de forma de onda.

## Licencia

Desarrollado para la comunidad de Kyvora.
