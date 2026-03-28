import Foundation
import Combine
import AppKit
import CoreGraphics

class DeviceManager: ObservableObject {
    @Published var availableDevices: [String] = []
    @Published var currentColor: (red: UInt8, green: UInt8, blue: UInt8) = (255, 0, 0)
    @Published var selectedDevice: String?
    @Published var statusMessage: String = ""
    @Published var needsElevation: Bool = false
    @Published var isDevicesEnabled: Bool = true
    
    private var devices: [String: HIDDevice] = [:]
    private let queue = DispatchQueue(label: "com.orchestrator.device-manager", qos: .userInitiated)
    private var pendingColorRequest: (red: UInt8, green: UInt8, blue: UInt8)?
    private var colorFlushScheduled = false
    private var knownDeviceColors: [String: (red: UInt8, green: UInt8, blue: UInt8)] = [:]
    private var savedDeviceColorsBeforePowerOff: [String: (red: UInt8, green: UInt8, blue: UInt8)] = [:]
    private let defaults = UserDefaults.standard
    private var isScreenLocked = false
    private var isScreenSaverActive = false
    private var isLightingActive = true
    private var distributedNotificationObservers: [NSObjectProtocol] = []
    private var screenStateTimer: DispatchSourceTimer?
    private var lastScreenSaverBlackoutEnforcement = Date.distantPast
    private var lastScreenSaverStartDate: Date?
    private var isScreenSaverLockSession = false

    private enum TransitionSpec {
        static let logitechSteps = 20
        static let logitechFrameDelayMicroseconds: useconds_t = 100_000
        static let screenSaverBlackoutRefreshInterval: TimeInterval = 1.2
        static let lockSessionStartWindow: TimeInterval = 4.0
        static let screenSaverProcessGraceWindow: TimeInterval = 4.0
    }

    private enum DefaultsKey {
        static let devicesEnabled = "orchestrator.devicesEnabled"
        static let currentColor = "orchestrator.currentColor"
        static let knownDeviceColors = "orchestrator.knownDeviceColors"
    }

    private enum AccessState {
        case unavailable
        case readableOnly
        case writable
    }
    
    init() {
        loadPersistedState()
        checkElevation()
        setupScreenStateMonitoring()
        scanDevices()
        queue.async { [weak self] in
            self?.refreshDynamicScreenStateOnQueue()
        }
    }

    deinit {
        teardownScreenStateMonitoring()
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

                for name in detected.keys {
                    if self?.knownDeviceColors[name] == nil {
                        self?.knownDeviceColors[name] = self?.currentColor
                    }
                }
                
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

                self?.queue.async { [weak self] in
                    self?.applySavedStateToConnectedDevices()
                }
            }
        }
    }
    
    func setDeviceColor(red: UInt8, green: UInt8, blue: UInt8) {
        queue.async { [weak self] in
            guard let self else { return }
            guard self.isDevicesEnabled else { return }
            guard self.isLightingActive else { return }
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
            guard self.isDevicesEnabled else { return }
            guard self.isLightingActive else { return }

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

                if family.contains("logitech") {
                    rgb = logitech
                } else if family.contains("razer") {
                    rgb = razer
                } else {
                    rgb = fallback
                }

                if !self.sendColorWithRetries(device: device, red: rgb.red, green: rgb.green, blue: rgb.blue, attempts: 4) {
                    failures.append(name)
                } else {
                    self.knownDeviceColors[name] = rgb
                    self.persistKnownDeviceColors()
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

    private func flushPendingColorRequest() {
        colorFlushScheduled = false
        guard let request = pendingColorRequest else { return }
        pendingColorRequest = nil

        guard let deviceName = selectedDevice, let device = devices[deviceName] else { return }

        let success = device.setColor(red: request.red, green: request.green, blue: request.blue)

        if success {
            knownDeviceColors[deviceName] = request
            DispatchQueue.main.async { [weak self] in
                self?.currentColor = (request.red, request.green, request.blue)
                self?.persistCurrentColor()
            }
            persistKnownDeviceColors()
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

    func setDevicesEnabled(_ enabled: Bool) {
        let fallbackColor = currentColor
        queue.async { [weak self] in
            guard let self else { return }
            self.setDevicesEnabledOnQueue(enabled, fallbackColor: fallbackColor)
        }
    }

    private func setDevicesEnabledOnQueue(_ enabled: Bool, fallbackColor: (red: UInt8, green: UInt8, blue: UInt8)) {
        guard enabled != isDevicesEnabled else {
            return
        }

        DispatchQueue.main.async {
            self.isDevicesEnabled = enabled
            self.persistDevicesEnabled()
        }

        applyLightingPolicyOnQueue(fallbackColor: fallbackColor, manualEnabledOverride: enabled)
    }

    private func applyLightingPolicyOnQueue(
        fallbackColor: (red: UInt8, green: UInt8, blue: UInt8),
        manualEnabledOverride: Bool? = nil
    ) {
        let manualEnabled = manualEnabledOverride ?? isDevicesEnabled
        let isNormalDesktopEnvironment = !isScreenLocked && !isScreenSaverActive
        let shouldAllowLighting = !isScreenSaverActive && (isScreenLocked || isNormalDesktopEnvironment)
        let shouldEnableHardwareLighting = manualEnabled && shouldAllowLighting

        guard shouldEnableHardwareLighting != isLightingActive else {
            if devices.isEmpty {
                DispatchQueue.main.async {
                    self.statusMessage = "No devices found"
                }
            }
            return
        }

        guard !devices.isEmpty else {
            DispatchQueue.main.async {
                self.isLightingActive = shouldEnableHardwareLighting
                self.statusMessage = "No devices found"
            }
            return
        }

        if shouldEnableHardwareLighting {
            restoreAllDeviceColorsFromPowerOffState(fallbackColor: fallbackColor)
        } else {
            transitionAllDevicesToBlackAndSaveState(fallbackColor: fallbackColor)
        }
    }

    private func transitionAllDevicesToBlackAndSaveState(fallbackColor: (red: UInt8, green: UInt8, blue: UInt8)) {
        let black: (red: UInt8, green: UInt8, blue: UInt8) = (0, 0, 0)
        var hadFailure = false

        savedDeviceColorsBeforePowerOff.removeAll(keepingCapacity: true)

        for (name, device) in devices {
            let startColor = knownDeviceColors[name] ?? fallbackColor
            savedDeviceColorsBeforePowerOff[name] = startColor

            let success: Bool
            if isLogitechDevice(name: name) {
                success = animateColorTransition(
                    device: device,
                    from: startColor,
                    to: black,
                    steps: TransitionSpec.logitechSteps,
                    frameDelayMicroseconds: TransitionSpec.logitechFrameDelayMicroseconds
                )
            } else {
                success = sendColorWithRetries(device: device, red: 0, green: 0, blue: 0, attempts: 4)
            }

            if !success { hadFailure = true }
        }

        DispatchQueue.main.async {
            self.isLightingActive = false
            if let selected = self.selectedDevice, self.devices[selected] != nil {
                self.currentColor = black
            }
            self.persistCurrentColor()
            self.statusMessage = hadFailure ? "Power-off failed on some devices" : self.suspendedStatusMessage()
        }
    }

    private func restoreAllDeviceColorsFromPowerOffState(fallbackColor: (red: UInt8, green: UInt8, blue: UInt8)) {
        var hadFailure = false
        var failedDeviceNames: [String] = []

        for (name, device) in devices {
            let target = savedDeviceColorsBeforePowerOff[name] ?? knownDeviceColors[name] ?? fallbackColor

            let success: Bool
            if isLogitechDevice(name: name) {
                success = animateColorTransition(
                    device: device,
                    from: (0, 0, 0),
                    to: target,
                    steps: TransitionSpec.logitechSteps,
                    frameDelayMicroseconds: TransitionSpec.logitechFrameDelayMicroseconds
                )
            } else {
                success = sendColorWithRetries(device: device, red: target.red, green: target.green, blue: target.blue, attempts: 4)
            }

            if success {
                knownDeviceColors[name] = target
            } else {
                hadFailure = true
                failedDeviceNames.append(name)
            }
        }

        if !failedDeviceNames.isEmpty {
            usleep(180_000)
            var unresolvedFailures: [String] = []
            for name in failedDeviceNames {
                guard let device = devices[name] else { continue }
                let target = savedDeviceColorsBeforePowerOff[name] ?? knownDeviceColors[name] ?? fallbackColor
                let recovered = sendColorWithRetries(device: device, red: target.red, green: target.green, blue: target.blue, attempts: 8)
                if recovered {
                    knownDeviceColors[name] = target
                } else {
                    unresolvedFailures.append(name)
                }
            }

            hadFailure = !unresolvedFailures.isEmpty
        }

        savedDeviceColorsBeforePowerOff.removeAll(keepingCapacity: false)

        DispatchQueue.main.async {
            self.isLightingActive = true
            if let selected = self.selectedDevice, let selectedColor = self.knownDeviceColors[selected] {
                self.currentColor = selectedColor
            }
            self.persistCurrentColor()
            self.persistKnownDeviceColors()
            self.statusMessage = hadFailure ? "Restore failed on some devices" : "Lighting restored"
        }
    }

    private func animateColorTransition(
        device: HIDDevice,
        from: (red: UInt8, green: UInt8, blue: UInt8),
        to: (red: UInt8, green: UInt8, blue: UInt8),
        steps: Int,
        frameDelayMicroseconds: useconds_t
    ) -> Bool {
        guard steps > 0 else {
            return device.setColor(red: to.red, green: to.green, blue: to.blue)
        }

        for step in 1...steps {
            let progress = Double(step) / Double(steps)
            let red = interpolateChannel(from.red, to.red, progress: progress)
            let green = interpolateChannel(from.green, to.green, progress: progress)
            let blue = interpolateChannel(from.blue, to.blue, progress: progress)

            if !device.setColor(red: red, green: green, blue: blue) {
                return false
            }

            usleep(frameDelayMicroseconds)
        }

        return true
    }

    private func isLogitechDevice(name: String) -> Bool {
        name.lowercased().contains("logitech")
    }

    private func interpolateChannel(_ start: UInt8, _ end: UInt8, progress: Double) -> UInt8 {
        let startValue = Double(start)
        let endValue = Double(end)
        let value = startValue + (endValue - startValue) * progress
        return UInt8(clamping: Int(value.rounded()))
    }

    private func applySavedStateToConnectedDevices() {
        guard !devices.isEmpty else { return }

        if isLightingActive {
            for (name, device) in devices {
                let target = knownDeviceColors[name] ?? currentColor
                if sendColorWithRetries(device: device, red: target.red, green: target.green, blue: target.blue, attempts: 4) {
                    knownDeviceColors[name] = target
                }
            }
            persistKnownDeviceColors()
            DispatchQueue.main.async {
                if let selected = self.selectedDevice, let selectedColor = self.knownDeviceColors[selected] {
                    self.currentColor = selectedColor
                    self.persistCurrentColor()
                }
            }
            return
        }

        for (_, device) in devices {
            _ = sendColorWithRetries(device: device, red: 0, green: 0, blue: 0, attempts: 4)
        }
        DispatchQueue.main.async {
            self.currentColor = (0, 0, 0)
            self.persistCurrentColor()
            self.statusMessage = "Lighting off"
        }
    }

    private func setupScreenStateMonitoring() {
        let center = DistributedNotificationCenter.default()

        let lockObserver = center.addObserver(forName: NSNotification.Name("com.apple.screenIsLocked"), object: nil, queue: nil) { [weak self] _ in
            self?.queue.async {
                guard let self else { return }
                self.isScreenLocked = true
                if self.lastScreenSaverStartDate?.timeIntervalSinceNow ?? -.infinity > -TransitionSpec.lockSessionStartWindow {
                    self.isScreenSaverLockSession = true
                }
                self.refreshDynamicScreenStateOnQueue()
                self.applyLightingPolicyOnQueue(fallbackColor: self.currentColor)
            }
        }

        let unlockObserver = center.addObserver(forName: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil, queue: nil) { [weak self] _ in
            self?.queue.async {
                guard let self else { return }
                self.isScreenLocked = false
                self.isScreenSaverLockSession = false
                self.lastScreenSaverStartDate = nil
                self.refreshDynamicScreenStateOnQueue()
                self.applyLightingPolicyOnQueue(fallbackColor: self.currentColor)
            }
        }

        let saverStartObserver = center.addObserver(forName: NSNotification.Name("com.apple.screensaver.didstart"), object: nil, queue: nil) { [weak self] _ in
            self?.queue.async {
                guard let self else { return }
                self.lastScreenSaverStartDate = Date()
                self.isScreenSaverActive = true
                if self.isScreenLocked {
                    self.isScreenSaverLockSession = true
                }
                self.applyLightingPolicyOnQueue(fallbackColor: self.currentColor)
            }
        }

        let saverStopObserver = center.addObserver(forName: NSNotification.Name("com.apple.screensaver.didstop"), object: nil, queue: nil) { [weak self] _ in
            self?.queue.async {
                guard let self else { return }
                if self.isScreenLocked && self.isScreenSaverLockSession {
                    return
                }
                self.isScreenSaverActive = false
                self.lastScreenSaverStartDate = nil
                self.isScreenSaverLockSession = false
                self.applyLightingPolicyOnQueue(fallbackColor: self.currentColor)
            }
        }

        distributedNotificationObservers = [lockObserver, unlockObserver, saverStartObserver, saverStopObserver]

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 0.5, repeating: .milliseconds(500))
        timer.setEventHandler { [weak self] in
            self?.refreshDynamicScreenStateOnQueue()
        }
        screenStateTimer = timer
        timer.resume()
    }

    private func teardownScreenStateMonitoring() {
        let center = DistributedNotificationCenter.default()
        for observer in distributedNotificationObservers {
            center.removeObserver(observer)
        }
        distributedNotificationObservers.removeAll(keepingCapacity: false)
        screenStateTimer?.cancel()
        screenStateTimer = nil
    }

    private func refreshDynamicScreenStateOnQueue() {
        let state = queryScreenSaverState()

        if isScreenLocked && isScreenSaverLockSession {
            if !isScreenSaverActive {
                isScreenSaverActive = true
                applyLightingPolicyOnQueue(fallbackColor: currentColor)
            }
            enforceScreenSaverBlackoutIfNeededOnQueue()
            return
        }

        let saverNow = state.hasScreenSaverWindow || (state.hasScreenSaverProcess && isWithinScreenSaverProcessGraceWindow())
        if saverNow != isScreenSaverActive {
            isScreenSaverActive = saverNow
            if saverNow {
                if lastScreenSaverStartDate == nil {
                    lastScreenSaverStartDate = Date()
                }
            } else {
                lastScreenSaverStartDate = nil
            }
            applyLightingPolicyOnQueue(fallbackColor: currentColor)
        }

        if isScreenSaverActive {
            enforceScreenSaverBlackoutIfNeededOnQueue()
        }
    }

    private func enforceScreenSaverBlackoutIfNeededOnQueue() {
        guard !devices.isEmpty else { return }
        guard !isLightingActive else { return }

        let now = Date()
        guard now.timeIntervalSince(lastScreenSaverBlackoutEnforcement) >= TransitionSpec.screenSaverBlackoutRefreshInterval else {
            return
        }

        lastScreenSaverBlackoutEnforcement = now

        var hadFailure = false
        for (_, device) in devices {
            if !sendColorWithRetries(device: device, red: 0, green: 0, blue: 0, attempts: 2) {
                hadFailure = true
            }
        }

        DispatchQueue.main.async {
            self.currentColor = (0, 0, 0)
            self.persistCurrentColor()
            if hadFailure {
                self.statusMessage = "Power-off failed on some devices"
            } else if self.isScreenSaverActive {
                self.statusMessage = "Lighting off (screen saver)"
            }
        }
    }

    private func queryScreenSaverState() -> (hasScreenSaverWindow: Bool, hasScreenSaverProcess: Bool) {
        let hasScreenSaverProcess = NSWorkspace.shared.runningApplications.contains { app in
            let bundle = app.bundleIdentifier?.lowercased() ?? ""
            let name = app.localizedName?.lowercased() ?? ""
            let executable = app.executableURL?.lastPathComponent.lowercased() ?? ""
            return bundle.contains("screensaver") || name.contains("screensaver") || executable.contains("screensaver") || bundle.contains("legacyscreensaver") || name.contains("legacyscreensaver") || executable.contains("legacyscreensaver")
        }

        guard let windowInfo = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return (false, hasScreenSaverProcess)
        }

        let hasScreenSaverWindow = windowInfo.contains { window in
            let owner = (window[kCGWindowOwnerName as String] as? String)?.lowercased() ?? ""
            return owner.contains("screensaver") || owner.contains("legacyscreensaver")
        }

        return (hasScreenSaverWindow, hasScreenSaverProcess)
    }

    private func isWithinScreenSaverProcessGraceWindow() -> Bool {
        guard let lastStart = lastScreenSaverStartDate else {
            return false
        }
        return Date().timeIntervalSince(lastStart) <= TransitionSpec.screenSaverProcessGraceWindow
    }

    private func suspendedStatusMessage() -> String {
        if isScreenSaverActive {
            return "Lighting off (screen saver)"
        }
        return "Lighting off"
    }

    private func loadPersistedState() {
        if defaults.object(forKey: DefaultsKey.devicesEnabled) != nil {
            isDevicesEnabled = defaults.bool(forKey: DefaultsKey.devicesEnabled)
        }

        if let colorString = defaults.string(forKey: DefaultsKey.currentColor), let color = decodeColor(colorString) {
            currentColor = color
        }

        if let storedMap = defaults.dictionary(forKey: DefaultsKey.knownDeviceColors) as? [String: String] {
            var decoded: [String: (red: UInt8, green: UInt8, blue: UInt8)] = [:]
            for (name, encodedColor) in storedMap {
                if let color = decodeColor(encodedColor) {
                    decoded[name] = color
                }
            }
            knownDeviceColors = decoded
        }
    }

    private func persistDevicesEnabled() {
        defaults.set(isDevicesEnabled, forKey: DefaultsKey.devicesEnabled)
    }

    private func persistCurrentColor() {
        defaults.set(encodeColor(currentColor), forKey: DefaultsKey.currentColor)
    }

    private func persistKnownDeviceColors() {
        var encoded: [String: String] = [:]
        for (name, rgb) in knownDeviceColors {
            encoded[name] = encodeColor(rgb)
        }
        defaults.set(encoded, forKey: DefaultsKey.knownDeviceColors)
    }

    private func encodeColor(_ color: (red: UInt8, green: UInt8, blue: UInt8)) -> String {
        "\(color.red),\(color.green),\(color.blue)"
    }

    private func decodeColor(_ raw: String) -> (red: UInt8, green: UInt8, blue: UInt8)? {
        let components = raw.split(separator: ",")
        guard components.count == 3 else { return nil }

        guard
            let red = UInt8(components[0]),
            let green = UInt8(components[1]),
            let blue = UInt8(components[2])
        else {
            return nil
        }

        return (red, green, blue)
    }

    private func sendColorWithRetries(
        device: HIDDevice,
        red: UInt8,
        green: UInt8,
        blue: UInt8,
        attempts: Int
    ) -> Bool {
        let totalAttempts = max(1, attempts)
        for attempt in 1...totalAttempts {
            if device.setColor(red: red, green: green, blue: blue) {
                return true
            }
            if attempt < totalAttempts {
                usleep(12_000)
            }
        }
        return false
    }

    func syncSelectedDeviceState() {
        queue.async { [weak self] in
            guard let self else { return }
            guard let selectedName = self.selectedDevice else { return }

            let selectedColor = self.knownDeviceColors[selectedName] ?? self.currentColor
            DispatchQueue.main.async {
                self.currentColor = selectedColor
                self.persistCurrentColor()
            }
        }
    }
}
