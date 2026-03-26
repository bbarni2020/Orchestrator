import Foundation

class RazerDevice: HIDDevice, HIDWriteProbeCapable {
    enum WaveDirection: UInt8, Codable {
        case left = 1
        case right = 2
    }

    enum LightingMode: String, Codable {
        case none
        case `static`
        case staticNoStore
        case spectrum
        case breathe
        case waveSimple
    }

    struct LightingState: Codable {
        let mode: LightingMode
        let args: [UInt8]?
    }

    enum RazerModel: CaseIterable {
        case firefly
        case firefly_v2
        case firefly_v2_pro
        case goliathus
        case goliathus_chroma
        case goliathus_extended_chroma

        enum ProtocolProfile {
            case standard
            case extended
        }
        
        var vendorID: Int { 0x1532 }
        var productID: Int {
            switch self {
            case .firefly: return 0x0C00
            case .firefly_v2: return 0x0C04
            case .firefly_v2_pro: return 0x0C08
            case .goliathus: return 0x0C01
            case .goliathus_chroma: return 0x0C02
            case .goliathus_extended_chroma: return 0x0C06
            }
        }
        
        var name: String {
            switch self {
            case .firefly: return "Razer Firefly"
            case .firefly_v2: return "Razer Firefly V2"
            case .firefly_v2_pro: return "Razer Firefly V2 Pro"
            case .goliathus: return "Razer Goliathus"
            case .goliathus_chroma: return "Razer Goliathus Chroma"
            case .goliathus_extended_chroma: return "Razer Goliathus Extended Chroma"
            }
        }

        var profile: ProtocolProfile {
            switch self {
            case .firefly:
                return .standard
            case .firefly_v2, .firefly_v2_pro, .goliathus, .goliathus_chroma, .goliathus_extended_chroma:
                return .extended
            }
        }

        var transactionByte: UInt8 {
            return 0x3F
        }
    }

    private enum PacketSpec {
        static let reportID: UInt8 = 0x00
        static let packetSize = 90
        static let statusIndex = 0
        static let transactionIndex = 1
        static let remainingIndexA = 2
        static let remainingIndexB = 3
        static let protocolIndex = 4
        static let dataSizeIndex = 5
        static let commandClassIndex = 6
        static let commandIDIndex = 7
        static let argsStartIndex = 8
        static let checksumIndex = 88
        static let reservedIndex = 89

        static let commandClassStandard: UInt8 = 0x03
        static let commandIDStandard: UInt8 = 0x0A
        static let commandClassExtended: UInt8 = 0x0F
        static let commandIDExtended: UInt8 = 0x02

        static let standardEffectNone: UInt8 = 0x00
        static let standardEffectStatic: UInt8 = 0x06

        static let extendedVariable: UInt8 = 0x01
        static let extendedLedID: UInt8 = 0x00
        static let extendedEffectNone: UInt8 = 0x00
        static let extendedEffectStatic: UInt8 = 0x01
    }
    
    let vendorID = 0x1532
    let productID: Int
    let name: String
    
    private let connection: HIDDeviceConnection
    private let model: RazerModel
    private var activeMode: LightingMode = .none
    private var activeModeArguments: [UInt8]?
    
    init(model: RazerModel) {
        self.model = model
        self.productID = model.productID
        self.name = model.name
        self.connection = HIDDeviceConnection(vendorID: vendorID, productID: productID)
    }
    
    func setColor(red: UInt8, green: UInt8, blue: UInt8) -> Bool {
        return setModeStatic([red, green, blue])
    }

    func setModeNone() -> Bool {
        let success = sendLightingCommand(command: noneCommand())
        if success {
            setModeState(mode: .none, args: nil)
        }
        return success
    }

    func setModeStatic(_ color: [UInt8]) -> Bool {
        guard color.count == 3 else { return false }
        let success = sendLightingCommand(command: staticCommand(color: color))

        if success {
            setModeState(mode: .static, args: color)
        }
        return success
    }

    func setModeStaticNoStore(_ color: [UInt8]) -> Bool {
        let success = setModeStatic(color)
        if success {
            setModeState(mode: .staticNoStore, args: color)
        }
        return success
    }

    func setSpectrum() -> Bool {
        let success: Bool
        switch model.profile {
        case .standard:
            success = sendLightingCommand(command: (commandClass: PacketSpec.commandClassStandard, commandID: PacketSpec.commandIDStandard, args: [0x04]))
        case .extended:
            success = sendLightingCommand(command: (commandClass: PacketSpec.commandClassExtended, commandID: PacketSpec.commandIDExtended, args: [
                PacketSpec.extendedVariable,
                PacketSpec.extendedLedID,
                0x03,
                0x00,
                0x00,
                0x00
            ]))
        }
        if success {
            setModeState(mode: .spectrum, args: nil)
        }
        return success
    }

    func setBreathe(_ color: [UInt8]?) -> Bool {
        let hasColor = color?.count == 3
        let success: Bool
        switch model.profile {
        case .standard:
            if hasColor, let color {
                success = sendLightingCommand(command: (commandClass: PacketSpec.commandClassStandard, commandID: PacketSpec.commandIDStandard, args: [0x01, color[0], color[1], color[2]]))
            } else {
                success = sendLightingCommand(command: (commandClass: PacketSpec.commandClassStandard, commandID: PacketSpec.commandIDStandard, args: [0x02]))
            }
        case .extended:
            if hasColor, let color {
                success = sendLightingCommand(command: (commandClass: PacketSpec.commandClassExtended, commandID: PacketSpec.commandIDExtended, args: [
                    PacketSpec.extendedVariable,
                    PacketSpec.extendedLedID,
                    0x02,
                    0x00,
                    0x00,
                    0x01,
                    color[0],
                    color[1],
                    color[2]
                ]))
            } else {
                success = sendLightingCommand(command: (commandClass: PacketSpec.commandClassExtended, commandID: PacketSpec.commandIDExtended, args: [
                    PacketSpec.extendedVariable,
                    PacketSpec.extendedLedID,
                    0x02,
                    0x00,
                    0x00,
                    0x00
                ]))
            }
        }
        if success {
            setModeState(mode: .breathe, args: hasColor ? color : nil)
        }
        return success
    }

    func setWaveSimple(direction: WaveDirection) -> Bool {
        let success: Bool
        switch model.profile {
        case .standard:
            success = sendLightingCommand(command: (commandClass: PacketSpec.commandClassStandard, commandID: PacketSpec.commandIDStandard, args: [0x03, direction.rawValue]))
        case .extended:
            success = sendLightingCommand(command: (commandClass: PacketSpec.commandClassExtended, commandID: PacketSpec.commandIDExtended, args: [
                PacketSpec.extendedVariable,
                PacketSpec.extendedLedID,
                0x04,
                direction.rawValue,
                0x28
            ]))
        }
        if success {
            setModeState(mode: .waveSimple, args: [direction.rawValue])
        }
        return success
    }

    func getState() -> LightingState {
        return LightingState(mode: activeMode, args: activeModeArguments)
    }

    func applyState(_ state: LightingState) -> Bool {
        switch state.mode {
        case .none:
            return setModeNone()
        case .static, .staticNoStore:
            guard let args = state.args, args.count == 3 else { return false }
            return state.mode == .static ? setModeStatic(args) : setModeStaticNoStore(args)
        case .spectrum:
            return setSpectrum()
        case .breathe:
            if let args = state.args {
                return setBreathe(args)
            }
            return setBreathe(nil)
        case .waveSimple:
            let arg = state.args?.first ?? WaveDirection.left.rawValue
            let direction: WaveDirection = arg == WaveDirection.right.rawValue ? .right : .left
            return setWaveSimple(direction: direction)
        }
    }

    func probeWriteAccess() -> Bool {
        return connection.connectAndDisconnectProbe()
    }

    private func sendLightingCommand(command: (commandClass: UInt8, commandID: UInt8, args: [UInt8])) -> Bool {
        guard command.args.count <= (PacketSpec.checksumIndex - PacketSpec.argsStartIndex) else { return false }
        let packet = buildPacket(commandClass: command.commandClass, commandID: command.commandID, args: command.args)
        return connection.sendReportToMatchingDevices(data: packet, reportID: PacketSpec.reportID)
    }

    private func buildPacket(commandClass: UInt8, commandID: UInt8, args: [UInt8]) -> [UInt8] {
        var packet = [UInt8](repeating: 0x00, count: PacketSpec.packetSize)
        packet[PacketSpec.statusIndex] = 0x00
        packet[PacketSpec.transactionIndex] = model.transactionByte
        packet[PacketSpec.remainingIndexA] = 0x00
        packet[PacketSpec.remainingIndexB] = 0x00
        packet[PacketSpec.protocolIndex] = 0x00
        packet[PacketSpec.dataSizeIndex] = UInt8(args.count)
        packet[PacketSpec.commandClassIndex] = commandClass
        packet[PacketSpec.commandIDIndex] = commandID

        for (index, value) in args.enumerated() {
            packet[PacketSpec.argsStartIndex + index] = value
        }

        packet[PacketSpec.checksumIndex] = calculateRazerChecksum(packet)
        packet[PacketSpec.reservedIndex] = 0x00
        return packet
    }

    private func calculateRazerChecksum(_ packet: [UInt8]) -> UInt8 {
        var checksum: UInt8 = 0

        for i in 2..<88 {
            checksum ^= packet[i]
        }

        return checksum
    }

    private func setModeState(mode: LightingMode, args: [UInt8]?) {
        activeMode = mode
        activeModeArguments = args
    }

    private func noneCommand() -> (commandClass: UInt8, commandID: UInt8, args: [UInt8]) {
        switch model.profile {
        case .standard:
            return (PacketSpec.commandClassStandard, PacketSpec.commandIDStandard, [PacketSpec.standardEffectNone])
        case .extended:
            return (
                PacketSpec.commandClassExtended,
                PacketSpec.commandIDExtended,
                [
                    PacketSpec.extendedVariable,
                    PacketSpec.extendedLedID,
                    PacketSpec.extendedEffectNone,
                    0x00,
                    0x00,
                    0x00
                ]
            )
        }
    }

    private func staticCommand(color: [UInt8]) -> (commandClass: UInt8, commandID: UInt8, args: [UInt8]) {
        switch model.profile {
        case .standard:
            return (
                PacketSpec.commandClassStandard,
                PacketSpec.commandIDStandard,
                [PacketSpec.standardEffectStatic, color[0], color[1], color[2]]
            )
        case .extended:
            return (
                PacketSpec.commandClassExtended,
                PacketSpec.commandIDExtended,
                [
                    PacketSpec.extendedVariable,
                    PacketSpec.extendedLedID,
                    PacketSpec.extendedEffectStatic,
                    0x00,
                    0x00,
                    0x01,
                    color[0],
                    color[1],
                    color[2]
                ]
            )
        }
    }
}
