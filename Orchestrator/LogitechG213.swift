import Foundation

class LogitechG213: HIDDevice, HIDWriteProbeCapable {
    let vendorID = 0x046D
    let productID = 0xC336
    let name = "Logitech G213"
    
    private enum PacketSpec {
        static let frameSize = 20
        static let reportID: UInt8 = 0x11
        static let header: [UInt8] = [0x11, 0xFF, 0x0C, 0x3A]
        static let regionSelector: UInt8 = 0x01
        static let allRegions: ClosedRange<UInt8> = 0x01...0x05
    }

    private let connection: HIDDeviceConnection
    
    init() {
        self.connection = HIDDeviceConnection(vendorID: vendorID, productID: productID)
    }
    
    func setColor(red: UInt8, green: UInt8, blue: UInt8) -> Bool {
        guard connection.connect() else { return false }
        defer { connection.disconnect() }

        for region in PacketSpec.allRegions {
            let report = makeRegionReport(region: region, red: red, green: green, blue: blue)
            if !connection.sendReport(data: report, reportID: PacketSpec.reportID) {
                return false
            }
        }

        return true
    }

    func probeWriteAccess() -> Bool {
        guard connection.connect() else { return false }
        defer { connection.disconnect() }

        var report = PacketSpec.header
        report.append(0x00)
        report.append(PacketSpec.regionSelector)
        report.append(0x00)
        report.append(0x00)
        report.append(0x00)
        if report.count < PacketSpec.frameSize {
            report.append(contentsOf: repeatElement(0x00, count: PacketSpec.frameSize - report.count))
        }

        return connection.sendReport(data: report, reportID: PacketSpec.reportID)
    }

    private func makeRegionReport(region: UInt8, red: UInt8, green: UInt8, blue: UInt8) -> [UInt8] {
        var report = PacketSpec.header
        report.append(region)
        report.append(PacketSpec.regionSelector)
        report.append(red)
        report.append(green)
        report.append(blue)
        if report.count < PacketSpec.frameSize {
            report.append(contentsOf: repeatElement(0x00, count: PacketSpec.frameSize - report.count))
        }
        return report
    }
}
