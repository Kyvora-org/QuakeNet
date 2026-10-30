import CoreMotion
import Foundation

class IOSSensorService {
    private let motionManager = CMMotionManager()
    private var timer: Timer?
    
    // Callback to send data back to Flutter via EventSink
    var onDataReceived: (([String: Any]) -> Void)?
    
    private var previousTimestamp: TimeInterval = 0
    
    var isActive: Bool {
        return motionManager.isAccelerometerActive
    }
    
    func start(samplingRate: Int) throws {
        guard motionManager.isAccelerometerAvailable else {
            throw NSError(domain: "SensorService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Accelerometer not available"])
        }
        
        let interval = 1.0 / Double(samplingRate)
        motionManager.accelerometerUpdateInterval = interval
        
        previousTimestamp = ProcessInfo.processInfo.systemUptime
        
        motionManager.startAccelerometerUpdates(to: .main) { [weak self] (data, error) in
            guard let self = self, let data = data else { return }
            
            let currentTimestamp = ProcessInfo.processInfo.systemUptime
            let samplingInterval = currentTimestamp - self.previousTimestamp
            self.previousTimestamp = currentTimestamp
            
            let sampleData: [String: Any] = [
                "x": data.acceleration.x,
                "y": data.acceleration.y,
                "z": data.acceleration.z,
                "sensorTimestamp": data.timestamp,
                "samplingInterval": samplingInterval
            ]
            
            self.onDataReceived?(sampleData)
        }
    }
    
    func stop() {
        motionManager.stopAccelerometerUpdates()
    }
}
