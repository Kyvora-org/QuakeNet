package com.quakenet.quakenet

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val METHODS_CHANNEL = "com.quakenet.sensor/methods"
    private val EVENTS_CHANNEL = "com.quakenet.sensor/events"

    private lateinit var sensorService: AndroidSensorService
    private var eventSink: EventChannel.EventSink? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        sensorService = AndroidSensorService(this)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHODS_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startSensor" -> {
                    val rate = call.argument<Int>("samplingRate") ?: 50
                    try {
                        sensorService.start(rate)
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("START_FAILED", e.message, null)
                    }
                }
                "stopSensor" -> {
                    sensorService.stop()
                    result.success(null)
                }
                "getSensorStatus" -> {
                    result.success(if (sensorService.isActive) "active" else "inactive")
                }
                else -> {
                    result.notImplemented()
                }
            }
        }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENTS_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                    sensorService.onDataReceived = { data ->
                        events?.success(data)
                    }
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                    sensorService.onDataReceived = null
                    sensorService.stop()
                }
            }
        )
    }
}
