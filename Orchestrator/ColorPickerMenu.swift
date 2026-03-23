import SwiftUI

struct ColorPickerMenu: View {
    @StateObject private var deviceManager = DeviceManager()
    @State private var showColorPicker = false
    @State private var selectedColor = Color.red
    
    private let presets: [(name: String, color: Color)] = [
        ("Red", .red),
        ("Green", .green),
        ("Blue", .blue),
        ("Purple", .purple),
        ("Cyan", .cyan),
        ("Yellow", .yellow),
        ("White", .white),
        ("Black", .black)
    ]
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Orchestrator")
                    .font(.headline)
                Spacer()
                Circle()
                    .fill(selectedColor)
                    .frame(width: 16, height: 16)
            }
            .padding(.bottom, 4)
            
            Divider()
            
            if deviceManager.needsElevation {
                VStack(spacing: 8) {
                    Text("Elevated Access Required")
                        .font(.caption)
                        .fontWeight(.semibold)
                    Text("HID devices need admin access to control")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Button(action: { deviceManager.requestElevation() }) {
                        HStack {
                            Image(systemName: "lock.open")
                            Text("Request Access")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            } else if deviceManager.availableDevices.isEmpty {
                VStack(spacing: 8) {
                    Text("No devices found")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(deviceManager.statusMessage)
                        .font(.caption2)
                        .foregroundColor(.gray)
                    Button("Scan Again") {
                        deviceManager.scanDevices()
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                Picker("Device", selection: $deviceManager.selectedDevice) {
                    ForEach(deviceManager.availableDevices, id: \.self) { device in
                        Text(device).tag(Optional(device))
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity)

                if deviceManager.isSelectedDeviceRazer {
                    Picker("Mode", selection: $deviceManager.selectedRazerMode) {
                        ForEach(deviceManager.availableRazerModes) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity)
                }
                
                Divider()
                
                VStack(spacing: 8) {
                    HStack(spacing: 4) {
                        ForEach(presets.prefix(4), id: \.name) { preset in
                            presetButton(preset)
                        }
                    }
                    HStack(spacing: 4) {
                        ForEach(presets.dropFirst(4), id: \.name) { preset in
                            presetButton(preset)
                        }
                    }
                }
                
                Divider()
                
                Button(action: { showColorPicker = true }) {
                    HStack {
                        Image(systemName: "eyedropper.halffull")
                        Text("Custom Color")
                    }
                    .frame(maxWidth: .infinity)
                }
                .popover(isPresented: $showColorPicker) {
                    ColorPickerView(
                        color: $selectedColor,
                        onColorSelected: { _ in
                            showColorPicker = false
                        }
                    )
                    .padding()
                }
            }
            
            Divider()
            
            Button(action: {
                NSApplication.shared.terminate(nil)
            }) {
                HStack {
                    Image(systemName: "power")
                    Text("Quit")
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(12)
        .frame(width: 220)
        .onChange(of: selectedColor) { _, newColor in
            let (r, g, b) = rgbFromColor(newColor)
            deviceManager.setDeviceColor(red: r, green: g, blue: b)
        }
        .onChange(of: deviceManager.selectedDevice) { _, _ in
            deviceManager.syncSelectedDeviceState()
        }
        .onChange(of: deviceManager.selectedRazerMode) { _, mode in
            guard deviceManager.isSelectedDeviceRazer else { return }
            deviceManager.applyRazerMode(mode)
        }
    }
    
    private func presetButton(_ preset: (name: String, color: Color)) -> some View {
        Button(action: {
            selectedColor = preset.color
        }) {
            Circle()
                .fill(preset.color)
        }
        .help(preset.name)
        .buttonStyle(.plain)
    }
    
    private func rgbFromColor(_ color: Color) -> (UInt8, UInt8, UInt8) {
        let components = NSColor(color).cgColor.components ?? [0, 0, 0, 1]
        let red = UInt8(components[0] * 255)
        let green = UInt8(components[1] * 255)
        let blue = UInt8(components[2] * 255)
        return (red, green, blue)
    }
}

struct ColorPickerView: View {
    @Binding var color: Color
    var onColorSelected: (Color) -> Void
    
    var body: some View {
        VStack {
            ColorPicker("", selection: $color)
            Button("Done") {
                onColorSelected(color)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(width: 200, height: 250)
    }
}

#Preview {
    ColorPickerMenu()
}
