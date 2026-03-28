import SwiftUI
import AppKit

struct ColorPickerMenu: View {
    @StateObject private var deviceManager = DeviceManager()
    @State private var showColorPicker = false
    @State private var selectedColor = Color.green
    @State private var suppressNextSelectedColorWrite = false
    @State private var selectedAllDevicesModeName: String?

    private let presets: [(name: String, color: Color)] = [
        ("Signal Red", Color(red: 0.98, green: 0.22, blue: 0.24)),
        ("Lime", Color(red: 0.38, green: 1.0, blue: 0.2)),
        ("Cyan", Color(red: 0.0, green: 0.9, blue: 1.0)),
        ("Royal", Color(red: 0.2, green: 0.35, blue: 1.0)),
        ("Amber", Color(red: 1.0, green: 0.67, blue: 0.14)),
        ("Rose", Color(red: 1.0, green: 0.2, blue: 0.6)),
        ("White", .white)
    ]

    private let grid = Array(repeating: GridItem(.flexible(minimum: 20, maximum: 60), spacing: 10), count: 4)

    private let quickModes: [QuickMode] = [
        QuickMode(name: "Warm", logitech: (245, 160, 59), razer: (147, 84, 11), fallback: (245, 160, 59)),
        QuickMode(name: "Forest", logitech: (6, 153, 59), razer: (18, 118, 18), fallback: (6, 153, 59)),
        QuickMode(name: "White", logitech: (255, 255, 255), razer: (255, 255, 255), fallback: (255, 255, 255))
    ]

    var body: some View {
        VStack(spacing: 10) {
            header
            content
            footer
        }
        .padding(12)
        .frame(width: 286)
        .background(
            LinearGradient(
                colors: [Color(NSColor.windowBackgroundColor), Color(NSColor.windowBackgroundColor).opacity(0.92)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .onChange(of: selectedColor) { _, newColor in
            guard deviceManager.isDevicesEnabled else { return }
            if suppressNextSelectedColorWrite {
                suppressNextSelectedColorWrite = false
                return
            }
            let (r, g, b) = rgbFromColor(newColor)
            deviceManager.setDeviceColor(red: r, green: g, blue: b)
        }
        .onReceive(deviceManager.$currentColor) { rgb in
            let next = Color(
                red: Double(rgb.red) / 255.0,
                green: Double(rgb.green) / 255.0,
                blue: Double(rgb.blue) / 255.0
            )

            if !colorsMatch(selectedColor, next) {
                suppressNextSelectedColorWrite = true
                selectedColor = next
            }
        }
        .onChange(of: deviceManager.selectedDevice) { _, _ in
            deviceManager.syncSelectedDeviceState()
        }
        .onChange(of: deviceManager.availableDevices) { _, devices in
            guard deviceManager.isDevicesEnabled else { return }
            guard !devices.isEmpty else { return }
            guard let selectedModeName = selectedAllDevicesModeName else { return }
            guard let mode = quickModes.first(where: { $0.name == selectedModeName }) else { return }
            applyQuickModeToAllDevices(mode)
        }
        .animation(.easeInOut(duration: 0.16), value: selectedColor)
        .animation(.easeInOut(duration: 0.16), value: deviceManager.needsElevation)
        .animation(.easeInOut(duration: 0.16), value: deviceManager.availableDevices)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(selectedColor)
                .frame(width: 18, height: 18)
                .overlay {
                    Circle().stroke(Color.primary.opacity(0.2), lineWidth: 1)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text("Orchestrator")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                Text(deviceManager.selectedDevice ?? "No active device")
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            statusChip
        }
        .padding(.horizontal, 2)
    }

    private var content: some View {
        Group {
            if deviceManager.needsElevation {
                elevationCard
            } else if deviceManager.availableDevices.isEmpty {
                emptyCard
            } else {
                controlsCard
            }
        }
    }

    private var elevationCard: some View {
        VStack(spacing: 10) {
            Text("Elevated access is required")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
            Text("Grant permissions to write HID reports.")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
            Button(action: { deviceManager.requestElevation() }) {
                Label("Request Access", systemImage: "lock.open.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryActionStyle(accent: selectedColor))
        }
        .panelStyle()
    }

    private var emptyCard: some View {
        VStack(spacing: 10) {
            Text("No compatible devices")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
            Text(deviceManager.statusMessage)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(action: { deviceManager.scanDevices() }) {
                Label("Scan Again", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryActionStyle(accent: selectedColor))
        }
        .panelStyle()
    }

    private var controlsCard: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Device")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("Device", selection: $deviceManager.selectedDevice) {
                    ForEach(deviceManager.availableDevices, id: \.self) { device in
                        Text(device).tag(Optional(device))
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 150)
            }

            LazyVGrid(columns: grid, spacing: 10) {
                ForEach(presets, id: \.name) { preset in
                    presetButton(preset)
                }
            }
            .disabled(!deviceManager.isDevicesEnabled)
            .opacity(deviceManager.isDevicesEnabled ? 1.0 : 0.45)

            VStack(alignment: .leading, spacing: 8) {
                Text("Modes")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    ForEach(quickModes, id: \.name) { mode in
                        Button(mode.name) {
                            applyQuickMode(mode)
                        }
                        .buttonStyle(PrimaryActionStyle(accent: modeColor(mode)))
                    }
                }
            }
            .disabled(!deviceManager.isDevicesEnabled)
            .opacity(deviceManager.isDevicesEnabled ? 1.0 : 0.45)

            VStack(alignment: .leading, spacing: 8) {
                Text("Custom Color")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    ColorPicker("Pick", selection: $selectedColor, supportsOpacity: false)
                        .font(.system(size: 11, weight: .medium, design: .rounded))

                    Button(action: { showColorPicker = true }) {
                        Label("Expanded", systemImage: "eyedropper.halffull")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryActionStyle(accent: selectedColor))
                }
            }
            .popover(isPresented: $showColorPicker) {
                ColorPickerView(
                    color: $selectedColor,
                    onColorSelected: { _ in
                        showColorPicker = false
                    }
                )
                .padding(12)
            }
            .disabled(!deviceManager.isDevicesEnabled)
            .opacity(deviceManager.isDevicesEnabled ? 1.0 : 0.45)

            VStack(alignment: .leading, spacing: 8) {
                Text("All Devices Modes")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    ForEach(quickModes, id: \.name) { mode in
                        Button(mode.name) {
                            applyQuickModeToAllDevices(mode)
                        }
                        .buttonStyle(PrimaryActionStyle(accent: modeColor(mode)))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.primary.opacity(selectedAllDevicesModeName == mode.name ? 0.6 : 0.0), lineWidth: 1.2)
                        }
                    }
                }
            }
            .disabled(!deviceManager.isDevicesEnabled)
            .opacity(deviceManager.isDevicesEnabled ? 1.0 : 0.45)

            Divider()
                .overlay(Color.primary.opacity(0.1))

            HStack {
                Text("All Devices Lighting")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
                Toggle(
                    "",
                    isOn: Binding(
                        get: { deviceManager.isDevicesEnabled },
                        set: { deviceManager.setDevicesEnabled($0) }
                    )
                )
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
            }
        }
        .panelStyle()
    }

    private var footer: some View {
        Button(action: {
            NSApplication.shared.terminate(nil)
        }) {
            Label("Quit", systemImage: "power")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var statusChip: some View {
        Text(statusLabel)
            .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(statusColor)
            )
    }

    private var statusLabel: String {
        if !deviceManager.isDevicesEnabled {
            return "Off"
        }
        return deviceManager.statusMessage == "Ready" ? "Live" : "Idle"
    }

    private var statusColor: Color {
        if !deviceManager.isDevicesEnabled {
            return Color.primary.opacity(0.12)
        }
        return deviceManager.statusMessage == "Ready" ? selectedColor.opacity(0.24) : Color.primary.opacity(0.08)
    }

    private func presetButton(_ preset: (name: String, color: Color)) -> some View {
        let isActive = colorsMatch(selectedColor, preset.color)
        return Button(action: {
            selectedColor = preset.color
        }) {
            Circle()
                .fill(preset.color)
                .frame(width: 28, height: 28)
                .overlay {
                    Circle()
                        .stroke(.primary.opacity(isActive ? 0.75 : 0.2), lineWidth: isActive ? 2.5 : 1)
                }
                    .scaleEffect(isActive ? 1.08 : 1.0)
        }
        .help(preset.name)
        .buttonStyle(.plain)
    }

    private func colorsMatch(_ lhs: Color, _ rhs: Color) -> Bool {
        let left = NSColor(lhs).usingColorSpace(.deviceRGB) ?? .black
        let right = NSColor(rhs).usingColorSpace(.deviceRGB) ?? .black
        return abs(left.redComponent - right.redComponent) < 0.01
            && abs(left.greenComponent - right.greenComponent) < 0.01
            && abs(left.blueComponent - right.blueComponent) < 0.01
    }

    private func rgbFromColor(_ color: Color) -> (UInt8, UInt8, UInt8) {
        let candidate = NSColor(color)
        if let nsColor = candidate.usingColorSpace(.sRGB)
            ?? candidate.usingColorSpace(.deviceRGB)
            ?? candidate.usingColorSpace(.genericRGB) {
            var r: CGFloat = 0
            var g: CGFloat = 0
            var b: CGFloat = 0
            var a: CGFloat = 0
            nsColor.getRed(&r, green: &g, blue: &b, alpha: &a)
            return (UInt8(r * 255), UInt8(g * 255), UInt8(b * 255))
        }

        if let cg = candidate.cgColor.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil), let components = cg.components {
            var r: CGFloat = 0
            var g: CGFloat = 0
            var b: CGFloat = 0
            if components.count >= 3 {
                r = components[0]
                g = components[1]
                b = components[2]
            } else if components.count == 2 {
                r = components[0]
                g = components[0]
                b = components[0]
            }
            return (UInt8(r * 255), UInt8(g * 255), UInt8(b * 255))
        }

        return (0, 0, 0)
    }

    private func modeColor(_ mode: QuickMode) -> Color {
        let rgb = mode.rgb(for: currentDeviceFamily())
        return Color(
            red: Double(rgb.r) / 255.0,
            green: Double(rgb.g) / 255.0,
            blue: Double(rgb.b) / 255.0
        )
    }

    private func applyQuickMode(_ mode: QuickMode) {
        selectedColor = modeColor(mode)
    }

    private func applyQuickModeToAllDevices(_ mode: QuickMode) {
        selectedAllDevicesModeName = mode.name
        suppressNextSelectedColorWrite = true
        selectedColor = modeColor(mode)
        deviceManager.setAllDevicesMode(
            logitech: (red: mode.logitech.r, green: mode.logitech.g, blue: mode.logitech.b),
            razer: (red: mode.razer.r, green: mode.razer.g, blue: mode.razer.b),
            fallback: (red: mode.fallback.r, green: mode.fallback.g, blue: mode.fallback.b)
        )
    }

    private func currentDeviceFamily() -> DeviceFamily {
        guard let selected = deviceManager.selectedDevice?.lowercased() else {
            return .other
        }
        if selected.contains("logitech") {
            return .logitech
        }
        if selected.contains("razer") {
            return .razer
        }
        return .other
    }
}

private enum DeviceFamily {
    case logitech
    case razer
    case other
}

private struct QuickMode {
    let name: String
    let logitech: (r: UInt8, g: UInt8, b: UInt8)
    let razer: (r: UInt8, g: UInt8, b: UInt8)
    let fallback: (r: UInt8, g: UInt8, b: UInt8)

    init(name: String, logitech: (UInt8, UInt8, UInt8), razer: (UInt8, UInt8, UInt8), fallback: (UInt8, UInt8, UInt8)) {
        self.name = name
        self.logitech = (r: logitech.0, g: logitech.1, b: logitech.2)
        self.razer = (r: razer.0, g: razer.1, b: razer.2)
        self.fallback = (r: fallback.0, g: fallback.1, b: fallback.2)
    }

    func rgb(for family: DeviceFamily) -> (r: UInt8, g: UInt8, b: UInt8) {
        switch family {
        case .logitech:
            return logitech
        case .razer:
            return razer
        case .other:
            return fallback
        }
    }
}

private struct PrimaryActionStyle: ButtonStyle {
    let accent: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(.primary)
            .padding(.vertical, 7)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [accent.opacity(0.26), accent.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .opacity(configuration.isPressed ? 0.92 : 1.0)
    }
}

private extension View {
    func panelStyle() -> some View {
        self
            .padding(11)
            .frame(maxWidth: .infinity)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 0.8)
            }
    }
}

struct ColorPickerView: View {
    @Binding var color: Color
    var onColorSelected: (Color) -> Void

    @State private var hue: Double = 0
    @State private var saturation: Double = 1
    @State private var brightness: Double = 1

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(color)
                    .frame(width: 48, height: 48)
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.primary.opacity(0.18), lineWidth: 1)
                    }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Palette")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                    Text(hexString())
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            PaletteField(hue: hue, saturation: $saturation, brightness: $brightness) {
                applyHSVToBinding()
            }
            .frame(height: 170)

            VStack(spacing: 8) {
                HStack {
                    Text("Hue")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(hue * 360))°")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                HueRail(value: $hue) {
                    applyHSVToBinding()
                }
                .frame(height: 18)
            }

            HStack(spacing: 8) {
                channelChip(title: "R", value: rgbComponents().0)
                channelChip(title: "G", value: rgbComponents().1)
                channelChip(title: "B", value: rgbComponents().2)
            }

            HStack(spacing: 8) {
                Button("Reset") {
                    hue = 0.33
                    saturation = 1
                    brightness = 1
                    applyHSVToBinding()
                }
                .buttonStyle(.bordered)

                Button("Apply") {
                    onColorSelected(color)
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(width: 280)
        .padding(4)
        .onAppear {
            loadHSVFromCurrentColor()
        }
    }

    private func applyHSVToBinding() {
        color = Color(hue: hue, saturation: saturation, brightness: brightness)
    }

    private func rgbComponents() -> (Int, Int, Int) {
        let nsColor = NSColor(color).usingColorSpace(.sRGB) ?? .black
        return (
            Int(nsColor.redComponent * 255),
            Int(nsColor.greenComponent * 255),
            Int(nsColor.blueComponent * 255)
        )
    }

    private func hexString() -> String {
        let (r, g, b) = rgbComponents()
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    private func loadHSVFromCurrentColor() {
        let nsColor = NSColor(color).usingColorSpace(.sRGB) ?? .white
        var h: CGFloat = 0
        var s: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        nsColor.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        hue = Double(h)
        saturation = Double(s)
        brightness = Double(b)
    }

    private func channelChip(title: String, value: Int) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct PaletteField: View {
    let hue: Double
    @Binding var saturation: Double
    @Binding var brightness: Double
    var onChanged: () -> Void

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(hue: hue, saturation: 1, brightness: 1))

                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.white, .white.opacity(0)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )

                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.black.opacity(0), .black],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                Circle()
                    .stroke(Color.white, lineWidth: 2)
                    .frame(width: 14, height: 14)
                    .shadow(color: .black.opacity(0.25), radius: 2, x: 0, y: 1)
                    .position(
                        x: saturation * geometry.size.width,
                        y: (1 - brightness) * geometry.size.height
                    )
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let x = min(max(value.location.x, 0), geometry.size.width)
                        let y = min(max(value.location.y, 0), geometry.size.height)
                        saturation = x / geometry.size.width
                        brightness = 1 - (y / geometry.size.height)
                        onChanged()
                    }
            )
        }
    }
}

private struct HueRail: View {
    @Binding var value: Double
    var onChanged: () -> Void

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(hue: 0.0, saturation: 1, brightness: 1),
                                Color(hue: 0.17, saturation: 1, brightness: 1),
                                Color(hue: 0.33, saturation: 1, brightness: 1),
                                Color(hue: 0.5, saturation: 1, brightness: 1),
                                Color(hue: 0.67, saturation: 1, brightness: 1),
                                Color(hue: 0.83, saturation: 1, brightness: 1),
                                Color(hue: 1.0, saturation: 1, brightness: 1)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )

                Circle()
                    .fill(.white)
                    .frame(width: 14, height: 14)
                    .overlay {
                        Circle().stroke(Color.primary.opacity(0.22), lineWidth: 1)
                    }
                    .offset(x: (geometry.size.width - 14) * value)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let x = min(max(drag.location.x, 0), geometry.size.width)
                        value = x / geometry.size.width
                        onChanged()
                    }
            )
        }
    }
}

#Preview {
    ColorPickerMenu()
}
