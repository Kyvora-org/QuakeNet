package com.quakenet.quakenet

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.SystemClock

class AndroidSensorService(context: Context) : SensorEventListener {
    private val sensorManager = context.getSystemService(Context.SENSOR_SERVICE) as SensorManager
    private val accelerometer = sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
    
    var onDataReceived: ((Map<String, Any>) -> Unit)? = null
    
    var isActive: Boolean = false
        private set
        
    private var previousTimestamp: Long = 0

    fun start(samplingRate: Int) {
        if (accelerometer == null) {
            throw Exception("Accelerometer not available")
        }
        
        // Convert Hz to microseconds delay
        val delayUs = (1000000 / samplingRate)
        
        previousTimestamp = SystemClock.elapsedRealtimeNanos()
        
        val registered = sensorManager.registerListener(this, accelerometer, delayUs)
        if (!registered) {
            throw Exception("Failed to register sensor listener")
        }
        isActive = true
    }

    fun stop() {
        sensorManager.unregisterListener(this)
        isActive = false
    }

    override fun onSensorChanged(event: SensorEvent?) {
        if (event == null || event.sensor.type != Sensor.TYPE_ACCELEROMETER) return
        
        val currentTimestamp = SystemClock.elapsedRealtimeNanos()
        val samplingIntervalNs = currentTimestamp - previousTimestamp
        previousTimestamp = currentTimestamp
        
        // Convert to seconds
        val samplingIntervalSeconds = samplingIntervalNs / 1_000_000_000.0
        
        val data = mapOf(
            "x" to event.values[0].toDouble(),
            "y" to event.values[1].toDouble(),
            "z" to event.values[2].toDouble(),
            "sensorTimestamp" to event.timestamp.toDouble(),
            "samplingInterval" to samplingIntervalSeconds
        )
        
        onDataReceived?.invoke(data)
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {
        // No-op for now
    }
}
