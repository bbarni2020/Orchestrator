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
            case .readableOnly:
                readableOnlyNames.append(g213.name)
            case .unavailable:
                break
            }

            let fireflyV2 = RazerFireflyV2()
            switch self?.testDeviceAccess(fireflyV2) ?? .unavailable {
            case .writable:
                detected[fireflyV2.name] = fireflyV2
            case .readableOnly:
                readableOnlyNames.append(fireflyV2.name)
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
            self.queue.asyncAfter(deadline: .now() + 0.008) { [weak self] in
                self?.flushPendingColorRequest()
            }
        }
    }

    func setAllDevicesMode(
        logitech: (red: UInt8, green: UInt8, blue: UInt8),
        razer: (red: UInt8, green: UInt8, blue: UInt8),
        fallback: (red: UInt8, green: UInt8, blue: UInt8)
    ) {
        queue.async { [weak self] in
            guard let self else { return }

            var failures: [String] = []
            var remaining = self.devices.count

            guard remaining > 0 else {
                DispatchQueue.main.async {
                    self.statusMessage = "No devices found"
                }
                return
            }

            for (name, device) in self.devices {
                let family = name.lowercased()
                let rgb: (red: UInt8, green: UInt8, blue: UInt8)
                let delay: TimeInterval

                if family.contains("logitech") {
                    rgb = logitech
                    delay = 3.0
                } else if family.contains("razer") {
                    rgb = razer
                    delay = 0
                } else {
                    rgb = fallback
                    delay = 0
                }

                self.queue.asyncAfter(deadline: .now() + delay) {
                    if !device.setColor(red: rgb.red, green: rgb.green, blue: rgb.blue) {
                        failures.append(name)
                    }

                    remaining -= 1
                    if remaining == 0 {
                        DispatchQueue.main.async {
                            if failures.isEmpty {
                                self.statusMessage = "Applied mode to all devices"
                            } else {
                                self.statusMessage = "Mode failed on: \(failures.joined(separator: ", "))"
                            }
                        }
                    }
                }
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
            queue.asyncAfter(deadline: .now() + 0.004) { [weak self] in
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
