import Foundation
import Combine

class DeviceManager: ObservableObject {
    @Published var availableDevices: [String] = []
    @Published var currentColor: (red: UInt8, green: UInt8, blue: UInt8) = (255, 0, 0)
    @Published var selectedDevice: String?
    @Published var statusMessage: String = ""
    @Published var needsElevation: Bool = false
    
    private var devices: [String: HIDDevice] = [:]
    private let queue = DispatchQueue(label: "com.orchestrator.device-manager", qos: .userInitiated)
    private var pendingColorRequest: (red: UInt8, green: UInt8, blue: UInt8)?
    private var colorFlushScheduled = false

    private enum AccessState {
        case unavailable
        case readableOnly
        case writable
    }
    
    init() {
        checkElevation()
        scanDevices()
    }
    
    func checkElevation() {
        needsElevation = false
    }
    
    func requestElevation() {
        PrivilegeHelper.shared.restartWithElevation()
    }
    
    func scanDevices() {
        queue.async { [weak self] in
            print("[DeviceManager] Scanning for devices (running as: \(PrivilegeHelper.shared.isRunningAsRoot() ? "root" : "user"))")
            var detected: [String: HIDDevice] = [:]
            var readableOnlyNames: [String] = []
            
            let g213 = LogitechG213()
            switch self?.testDeviceAccess(g213) ?? .unavailable {
            case .writable:
                detected[g213.name] = g213
                DispatchQueue.main.async {
                    self?.statusMessage = "Found: \(g213.name)"
                }
            case .readableOnly:
                readableOnlyNames.append(g213.name)
            case .unavailable:
                break
            }
            
            DispatchQueue.main.async {
                self?.devices = detected
                self?.availableDevices = Array(detected.keys).sorted()
                let requiresElevation = detected.isEmpty && !readableOnlyNames.isEmpty
                self?.needsElevation = requiresElevation
                
                if self?.selectedDevice == nil && !detected.isEmpty {
                    self?.selectedDevice = self?.availableDevices.first
                }
                
                if detected.isEmpty {
                    self?.statusMessage = requiresElevation
                        ? "Device found but not writable. Elevated access may be required."
                        : "No devices found"
                } else {
                    self?.statusMessage = "Ready"
                }
            }
        }
    }
    
    func setDeviceColor(red: UInt8, green: UInt8, blue: UInt8) {
        queue.async { [weak self] in
            guard let self else { return }
            self.pendingColorRequest = (red, green, blue)
            guard !self.colorFlushScheduled else { return }

            self.colorFlushScheduled = true
            self.queue.asyncAfter(deadline: .now() + 0.03) { [weak self] in
                self?.flushPendingColorRequest()
            }
        }
    }

    private func flushPendingColorRequest() {
        colorFlushScheduled = false
        guard let request = pendingColorRequest else { return }
        pendingColorRequest = nil

        guard let deviceName = selectedDevice, let device = devices[deviceName] else { return }

        let success = device.setColor(red: request.red, green: request.green, blue: request.blue)

        if success {
            DispatchQueue.main.async { [weak self] in
                self?.currentColor = (request.red, request.green, request.blue)
            }
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.statusMessage = "Failed to set color on \(deviceName)"
            }
        }

        if pendingColorRequest != nil {
            colorFlushScheduled = true
            queue.asyncAfter(deadline: .now() + 0.02) { [weak self] in
                self?.flushPendingColorRequest()
            }
        }
    }
    
    private func testDeviceAccess(_ device: HIDDevice) -> AccessState {
        let connection = HIDDeviceConnection(vendorID: device.vendorID, productID: device.productID)
        let connected = connection.connect()
        connection.disconnect()
        guard connected else { return .unavailable }

        if let writableProbe = device as? HIDWriteProbeCapable {
            return writableProbe.probeWriteAccess() ? .writable : .readableOnly
        }

        return .writable
    }

    func syncSelectedDeviceState() {
        return
    }
}
