import Flutter
import UIKit

class IOSSensorBridge: NSObject, FlutterStreamHandler {
    private let sensorService = IOSSensorService()
    private var eventSink: FlutterEventSink?

    func register(with registrar: FlutterPluginRegistrar) {
        let methodChannel = FlutterMethodChannel(name: "com.quakenet.sensor/methods", binaryMessenger: registrar.messenger())
        
        methodChannel.setMethodCallHandler { [weak self] (call, result) in
            guard let self = self else { return }
            
            switch call.method {
            case "startSensor":
                if let args = call.arguments as? [String: Any],
                   let rate = args["samplingRate"] as? Int {
                    do {
                        try self.sensorService.start(samplingRate: rate)
                        result(nil)
                    } catch {
                        result(FlutterError(code: "START_FAILED", message: error.localizedDescription, details: nil))
                    }
                } else {
                    result(FlutterError(code: "INVALID_ARGS", message: "Missing samplingRate", details: nil))
                }
            case "stopSensor":
                self.sensorService.stop()
                result(nil)
            case "getSensorStatus":
                result(self.sensorService.isActive ? "active" : "inactive")
            default:
                result(FlutterMethodNotImplemented)
            }
        }
        
        let eventChannel = FlutterEventChannel(name: "com.quakenet.sensor/events", binaryMessenger: registrar.messenger())
        eventChannel.setStreamHandler(self)
    }

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        sensorService.onDataReceived = { data in
            events(data)
        }
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil
        sensorService.onDataReceived = nil
        sensorService.stop()
        return nil
    }
}
