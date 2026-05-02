# Orchestrator

Menu bar application for controlling RGB lighting on Logitech G213 and Razer peripheral devices via USB/HID on macOS.

## Demo video

<video width="100%" controls>
  <source src="https://cdn.hackclub.com/019dea21-7135-7939-b2a2-dca36f323275/Video%20Compress%20IMG%200056%20from%20Orchestrator.mp4" type="video/mp4">
  Your browser does not support the video tag.
</video>

[Link](https://cdn.hackclub.com/019dea21-7135-7939-b2a2-dca36f323275/Video%20Compress%20IMG%200056%20from%20Orchestrator.mp4)

## Features

- 8-color presets and custom color picker
- Support for Logitech G213 Prodigy and Razer Firefly/Goliathus devices
- Real-time device detection and connection monitoring
- Menu bar interface for quick access

## Supported Devices

| Device | Vendor ID | Product ID |
|--------|-----------|------------|
| Logitech G213 | 0x046D | 0xC336 |
| Razer Firefly | 0x1532 | 0x0C00 |
| Razer Goliathus | 0x1532 | 0x0C01 |

## Building and Setup

1. Open `Orchestrator.xcodeproj` in Xcode
2. Configure the target build settings with `Orchestrator.entitlements` in **Build Settings** → **Code Signing Entitlements**
3. Build and run the application

The application automatically detects connected devices and displays in the system menu bar.

## Technical Implementation

- **HID Communication**: IOKit low-level HID APIs for device communication
- **Logitech G213**: 20-byte feature reports with zone-based color commands
- **Razer Devices**: 90-byte command envelopes with XOR checksum validation
- **Device Manager**: Asynchronous device scanning and command queueing

## Architecture

```
AppDelegate           Menu bar setup and popover management
├── ColorPickerMenu   Color preset UI and device selection
├── DeviceManager     Device detection and command orchestration
├── HIDDevice         Device abstraction protocol
├── LogitechG213      Logitech device implementation
└── RazerFireflyV2    Razer device implementation
```

## License

MIT