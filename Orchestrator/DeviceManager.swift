import Foundation
import Combine

class DeviceManager: ObservableObject {
    enum RazerModeSelection: String, CaseIterable, Identifiable {
        case `static`
        case spectrum
        case breathe
        case waveLeft
        case waveRight
        case none

        var id: String { rawValue }

        var title: String {
            switch self {
            case .static: return "Static"
            case .spectrum: return "Spectrum"
            case .breathe: return "Breathe"
            case .waveLeft: return "Wave Left"
            case .waveRight: return "Wave Right"
            case .none: return "Off"
            }
        }
    }

    @Published var availableDevices: [String] = []
    @Published var currentColor: (red: UInt8, green: UInt8, blue: UInt8) = (255, 0, 0)
    @Published var selectedDevice: String?
    @Published var statusMessage: String = ""
    @Published var needsElevation: Bool = false
    @Published var selectedRazerMode: RazerModeSelection = .static
    @Published var availableRazerModes: [RazerModeSelection] = RazerModeSelection.allCases
    
    private var devices: [String: HIDDevice] = [:]
    private let queue = DispatchQueue(label: "com.orchestrator.device-manager", qos: .userInitiated)
    private var pendingColorRequest: (red: UInt8, green: UInt8, blue: UInt8)?
    private var colorFlushScheduled = false
    private struct SavedRazerState: Codable {
        let mode: String
        let args: [UInt8]?
    }
    private var savedRazerStates: [String: SavedRazerState] = [:]
    private let razerStateDefaultsKey = "orchestrator.razer.states"

    private enum AccessState {
        case unavailable
        case readableOnly
        case writable
    }
    
    init() {
        loadSavedRazerStates()
        checkElevation()
        scanDevices()
    }

    var isSelectedDeviceRazer: Bool {
        guard let deviceName = selectedDevice, let device = devices[deviceName] else { return false }
        return device is RazerDevice || device is RazerKeyboardDevice
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
            
            for model in RazerDevice.RazerModel.allCases {
                let razer = RazerDevice(model: model)
                switch self?.testDeviceAccess(razer) ?? .unavailable {
                case .writable:
                    detected[razer.name] = razer
                    DispatchQueue.main.async {
                        self?.statusMessage = "Found: \(razer.name)"
                    }
                case .readableOnly:
                    readableOnlyNames.append(razer.name)
                case .unavailable:
                    break
                }
            }

            for model in RazerKeyboardDevice.Model.allCases {
                let razerKeyboard = RazerKeyboardDevice(model: model)
                switch self?.testDeviceAccess(razerKeyboard) ?? .unavailable {
                case .writable:
                    detected[razerKeyboard.name] = razerKeyboard
                    DispatchQueue.main.async {
                        self?.statusMessage = "Found: \(razerKeyboard.name)"
                    }
                case .readableOnly:
                    readableOnlyNames.append(razerKeyboard.name)
                case .unavailable:
                    break
                }
            }
            
            DispatchQueue.main.async {
                self?.devices = detected
                self?.availableDevices = Array(detected.keys).sorted()
                let requiresElevation = detected.isEmpty && !readableOnlyNames.isEmpty
                self?.needsElevation = requiresElevation
                
                if self?.selectedDevice == nil && !detected.isEmpty {
                    self?.selectedDevice = self?.availableDevices.first
                }

                self?.syncSelectedDeviceState()
                
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

        let success: Bool
        if let razerDevice = device as? RazerDevice {
            switch selectedRazerMode {
            case .static:
                success = razerDevice.setModeStatic([request.red, request.green, request.blue])
            case .breathe:
                success = razerDevice.setBreathe([request.red, request.green, request.blue])
            case .spectrum:
                success = razerDevice.setSpectrum()
            case .waveLeft:
                success = razerDevice.setWaveSimple(direction: .left)
            case .waveRight:
                success = razerDevice.setWaveSimple(direction: .right)
            case .none:
                success = razerDevice.setModeNone()
            }
            if success {
                saveRazerState(for: deviceName, state: razerDevice.getState())
            }
        } else if let razerKeyboardDevice = device as? RazerKeyboardDevice {
            switch selectedRazerMode {
            case .none:
                success = razerKeyboardDevice.setModeNone()
            default:
                success = razerKeyboardDevice.setModeStatic([request.red, request.green, request.blue])
            }
            if success {
                saveRazerState(for: deviceName, state: razerKeyboardDevice.getState())
            }
        } else {
            success = device.setColor(red: request.red, green: request.green, blue: request.blue)
        }

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

    func applyRazerMode(_ mode: RazerModeSelection) {
        guard let deviceName = selectedDevice, let device = devices[deviceName] else { return }

        queue.async { [weak self] in
            guard let self else { return }

            let color = [self.currentColor.red, self.currentColor.green, self.currentColor.blue]
            let success: Bool
            if let razerDevice = device as? RazerDevice {
                switch mode {
                case .static:
                    success = razerDevice.setModeStatic(color)
                case .spectrum:
                    success = razerDevice.setSpectrum()
                case .breathe:
                    success = razerDevice.setBreathe(color)
                case .waveLeft:
                    success = razerDevice.setWaveSimple(direction: .left)
                case .waveRight:
                    success = razerDevice.setWaveSimple(direction: .right)
                case .none:
                    success = razerDevice.setModeNone()
                }
            } else if let razerKeyboardDevice = device as? RazerKeyboardDevice {
                switch mode {
                case .none:
                    success = razerKeyboardDevice.setModeNone()
                default:
                    success = razerKeyboardDevice.setModeStatic(color)
                }
            } else {
                return
            }

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if success {
                    self.selectedRazerMode = mode
                    if let razerDevice = device as? RazerDevice {
                        self.saveRazerState(for: deviceName, state: razerDevice.getState())
                    } else if let razerKeyboardDevice = device as? RazerKeyboardDevice {
                        self.saveRazerState(for: deviceName, state: razerKeyboardDevice.getState())
                    }
                    self.statusMessage = "Ready"
                } else {
                    self.statusMessage = "Failed to set Razer mode on \(deviceName)"
                }
            }
        }
    }

    func syncSelectedDeviceState() {
        guard let deviceName = selectedDevice, let device = devices[deviceName] else { return }

        availableRazerModes = supportedRazerModes(for: device)

        if let razerDevice = device as? RazerDevice {
            if let savedState = savedRazerStates[deviceName] {
                queue.async { [weak self] in
                    let success = self?.applySavedState(savedState, to: razerDevice) ?? false
                    DispatchQueue.main.async {
                        if success {
                            self?.selectedRazerMode = self?.modeSelection(from: savedState.mode, args: savedState.args) ?? .static
                        } else {
                            self?.selectedRazerMode = .static
                        }
                    }
                }
            } else {
                selectedRazerMode = modeSelection(from: razerDevice.getState())
            }
            return
        }

        if let razerKeyboardDevice = device as? RazerKeyboardDevice {
            if let savedState = savedRazerStates[deviceName] {
                queue.async { [weak self] in
                    let success = self?.applySavedState(savedState, to: razerKeyboardDevice) ?? false
                    DispatchQueue.main.async {
                        if success {
                            self?.selectedRazerMode = self?.modeSelection(from: savedState.mode, args: savedState.args) ?? .static
                        } else {
                            self?.selectedRazerMode = .static
                        }
                    }
                }
            } else {
                selectedRazerMode = modeSelection(from: razerKeyboardDevice.getState())
            }
            return
        }

        availableRazerModes = RazerModeSelection.allCases
        selectedRazerMode = .static
    }

    private func modeSelection(from state: RazerDevice.LightingState) -> RazerModeSelection {
        switch state.mode {
        case .none:
            return .none
        case .static, .staticNoStore:
            return .static
        case .spectrum:
            return .spectrum
        case .breathe:
            return .breathe
        case .waveSimple:
            let raw = state.args?.first ?? RazerDevice.WaveDirection.left.rawValue
            return raw == RazerDevice.WaveDirection.right.rawValue ? .waveRight : .waveLeft
        }
    }

    private func modeSelection(from state: RazerKeyboardDevice.LightingState) -> RazerModeSelection {
        switch state.mode {
        case .none:
            return .none
        case .static, .staticNoStore:
            return .static
        }
    }

    private func saveRazerState(for deviceName: String, state: RazerDevice.LightingState) {
        savedRazerStates[deviceName] = SavedRazerState(mode: state.mode.rawValue, args: state.args)
        guard let encoded = try? JSONEncoder().encode(savedRazerStates) else { return }
        UserDefaults.standard.set(encoded, forKey: razerStateDefaultsKey)
    }

    private func saveRazerState(for deviceName: String, state: RazerKeyboardDevice.LightingState) {
        savedRazerStates[deviceName] = SavedRazerState(mode: state.mode.rawValue, args: state.args)
        guard let encoded = try? JSONEncoder().encode(savedRazerStates) else { return }
        UserDefaults.standard.set(encoded, forKey: razerStateDefaultsKey)
    }

    private func loadSavedRazerStates() {
        guard let data = UserDefaults.standard.data(forKey: razerStateDefaultsKey) else { return }
        if let states = try? JSONDecoder().decode([String: SavedRazerState].self, from: data) {
            savedRazerStates = states
            return
        }
        if let legacyStates = try? JSONDecoder().decode([String: RazerDevice.LightingState].self, from: data) {
            savedRazerStates = legacyStates.mapValues { SavedRazerState(mode: $0.mode.rawValue, args: $0.args) }
        }
    }

    private func modeSelection(from mode: String, args: [UInt8]?) -> RazerModeSelection {
        switch mode {
        case RazerDevice.LightingMode.none.rawValue, RazerKeyboardDevice.LightingMode.none.rawValue:
            return .none
        case RazerDevice.LightingMode.spectrum.rawValue:
            return .spectrum
        case RazerDevice.LightingMode.breathe.rawValue:
            return .breathe
        case RazerDevice.LightingMode.waveSimple.rawValue:
            let raw = args?.first ?? RazerDevice.WaveDirection.left.rawValue
            return raw == RazerDevice.WaveDirection.right.rawValue ? .waveRight : .waveLeft
        default:
            return .static
        }
    }

    private func applySavedState(_ state: SavedRazerState, to device: RazerDevice) -> Bool {
        guard let mode = RazerDevice.LightingMode(rawValue: state.mode) else {
            return device.setModeStatic([currentColor.red, currentColor.green, currentColor.blue])
        }

        let decodedState = RazerDevice.LightingState(mode: mode, args: state.args)
        if device.applyState(decodedState) {
            return true
        }

        return device.setModeStatic([currentColor.red, currentColor.green, currentColor.blue])
    }

    private func applySavedState(_ state: SavedRazerState, to device: RazerKeyboardDevice) -> Bool {
        guard let mode = RazerKeyboardDevice.LightingMode(rawValue: state.mode) else {
            return device.setModeStatic([currentColor.red, currentColor.green, currentColor.blue])
        }

        let decodedState = RazerKeyboardDevice.LightingState(mode: mode, args: state.args)
        if device.applyState(decodedState) {
            return true
        }

        return device.setModeStatic([currentColor.red, currentColor.green, currentColor.blue])
    }

    private func supportedRazerModes(for device: HIDDevice) -> [RazerModeSelection] {
        if device is RazerKeyboardDevice {
            return [.static, .none]
        }
        if device is RazerDevice {
            return RazerModeSelection.allCases
        }
        return RazerModeSelection.allCases
    }
}
