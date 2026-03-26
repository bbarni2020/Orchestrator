import Foundation

final class RazerFireflyV2: HIDDevice, HIDWriteProbeCapable {
    let vendorID = 0x1532
    let productID = 0x0C04
    let name = "Razer Firefly V2"

    private enum PacketSpec {
        static let reportSize = 90
        static let reportID: UInt8 = 0x00
        static let transactionID: UInt8 = 0x3F
        static let commandClass: UInt8 = 0x0F
        static let commandID: UInt8 = 0x02
        static let ledIDs: [UInt8] = [0x05, 0x00]
        static let staticEffect: UInt8 = 0x01
        static let noneEffect: UInt8 = 0x00
    }

    private let connection: HIDDeviceConnection

    init() {
        connection = HIDDeviceConnection(vendorID: vendorID, productID: productID)
    }

    func setColor(red: UInt8, green: UInt8, blue: UInt8) -> Bool {
        let reports = PacketSpec.ledIDs.map { ledID in
            makeReport(ledID: ledID, effect: PacketSpec.staticEffect, red: red, green: green, blue: blue)
        }
        return sendWithRetries(reports)
    }

    func probeWriteAccess() -> Bool {
        let reports = PacketSpec.ledIDs.map { ledID in
            makeReport(ledID: ledID, effect: PacketSpec.noneEffect, red: 0, green: 0, blue: 0)
        }
        return sendWithRetries(reports)
    }

    private func sendWithRetries(_ reports: [[UInt8]]) -> Bool {
        var delay: TimeInterval = 0.01

        for _ in 0..<3 {
            guard connection.connect() else {
                Thread.sleep(forTimeInterval: delay)
                delay *= 2
                continue
            }

            var wroteAll = true
            for report in reports {
                if !connection.sendReport(data: report, reportID: PacketSpec.reportID) {
                    wroteAll = false
                    break
                }
            }
            connection.disconnect()

            if wroteAll {
                return true
            }

            Thread.sleep(forTimeInterval: delay)
            delay *= 2
        }

        return false
    }

    private func makeReport(ledID: UInt8, effect: UInt8, red: UInt8, green: UInt8, blue: UInt8) -> [UInt8] {
        var report = [UInt8](repeating: 0x00, count: PacketSpec.reportSize)
        let args: [UInt8]

        if effect == PacketSpec.staticEffect {
            args = [0x01, ledID, effect, 0x00, 0x00, 0x01, red, green, blue]
        } else {
            args = [0x01, ledID, effect, 0x00, 0x00, 0x00]
        }

        report[0] = 0x00
        report[1] = PacketSpec.transactionID
        report[2] = 0x00
        report[3] = 0x00
        report[4] = 0x00
        report[5] = UInt8(args.count)
        report[6] = PacketSpec.commandClass
        report[7] = PacketSpec.commandID

        for (index, value) in args.enumerated() {
            let target = 8 + index
            if target < 88 {
                report[target] = value
            }
        }

        report[88] = checksum(report)
        report[89] = 0x00

        return report
    }

    private func checksum(_ report: [UInt8]) -> UInt8 {
        var value: UInt8 = 0
        for index in 2..<88 {
            value ^= report[index]
        }
        return value
    }
}