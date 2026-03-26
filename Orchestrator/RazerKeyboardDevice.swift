import Foundation

class RazerKeyboardDevice: HIDDevice, HIDWriteProbeCapable {
    enum LightingMode: String, Codable {
        case none
        case `static`
        case staticNoStore
    }

    struct LightingState: Codable {
        let mode: LightingMode
        let args: [UInt8]?
    }

    enum Model: CaseIterable {
        case blackWidowChroma
        case ornataChroma
        case blackWidowChromaV2
        case huntsmanElite
        case cynosaChroma
        case blackWidowV3
        case ornataV2
        case cynosaV2
        case huntsmanV2
        case blackWidowV4
        case huntsmanV3Pro

        var vendorID: Int { 0x1532 }

        var productID: Int {
            switch self {
            case .blackWidowChroma: return 0x0203
            case .ornataChroma: return 0x021E
            case .blackWidowChromaV2: return 0x0221
            case .huntsmanElite: return 0x0226
            case .cynosaChroma: return 0x022A
            case .blackWidowV3: return 0x024E
            case .ornataV2: return 0x025D
            case .cynosaV2: return 0x025E
            case .huntsmanV2: return 0x026C
            case .blackWidowV4: return 0x0287
            case .huntsmanV3Pro: return 0x0283
            }
        }

        var name: String {
            switch self {
            case .blackWidowChroma: return "Razer BlackWidow Chroma"
            case .ornataChroma: return "Razer Ornata Chroma"
            case .blackWidowChromaV2: return "Razer BlackWidow Chroma V2"
            case .huntsmanElite: return "Razer Huntsman Elite"
            case .cynosaChroma: return "Razer Cynosa Chroma"
            case .blackWidowV3: return "Razer BlackWidow V3"
            case .ornataV2: return "Razer Ornata V2"
            case .cynosaV2: return "Razer Cynosa V2"
            case .huntsmanV2: return "Razer Huntsman V2"
            case .blackWidowV4: return "Razer BlackWidow V4"
            case .huntsmanV3Pro: return "Razer Huntsman V3 Pro"
            }
        }
    }

    private enum PacketSpec {
        static let reportID: UInt8 = 0x00
        static let packetSize = 90
        static let dataSizeIndex = 5
        static let commandClassIndex = 6
        static let commandIDIndex = 7
        static let argsStartIndex = 8
        static let checksumIndex = 88
        static let commandClassLighting: UInt8 = 0x0F
        static let commandIDSetMatrixEffect: UInt8 = 0x02
        static let transactionByte: UInt8 = 0x3F
        static let variableStorage: UInt8 = 0x01
        static let ledBacklight: UInt8 = 0x05
        static let effectNone: UInt8 = 0x00
        static let effectStatic: UInt8 = 0x01
        static let reservedA: UInt8 = 0x00
        static let reservedB: UInt8 = 0x00
        static let reservedC: UInt8 = 0x01
    }

    let vendorID = 0x1532
    let productID: Int
    let name: String

    private let connection: HIDDeviceConnection
    private var activeMode: LightingMode = .none
    private var activeModeArguments: [UInt8]?

    init(model: Model) {
        self.productID = model.productID
        self.name = model.name
        self.connection = HIDDeviceConnection(vendorID: model.vendorID, productID: model.productID)
    }

    func setColor(red: UInt8, green: UInt8, blue: UInt8) -> Bool {
        return setModeStatic([red, green, blue])
    }

    func setModeNone() -> Bool {
        let success = sendLightingCommand(args: [
            PacketSpec.variableStorage,
            PacketSpec.ledBacklight,
            PacketSpec.effectNone,
            PacketSpec.reservedA,
            PacketSpec.reservedB,
            PacketSpec.reservedC,
            0x00,
            0x00,
            0x00
        ])
        if success {
            setModeState(mode: .none, args: nil)
        }
        return success
    }

    func setModeStatic(_ color: [UInt8]) -> Bool {
        guard color.count == 3 else { return false }
        let success = sendLightingCommand(args: [
            PacketSpec.variableStorage,
            PacketSpec.ledBacklight,
            PacketSpec.effectStatic,
            PacketSpec.reservedA,
            PacketSpec.reservedB,
            PacketSpec.reservedC,
            color[0],
            color[1],
            color[2]
        ])

        if success {
            setModeState(mode: .static, args: color)
        }
        return success
    }

    func setModeStaticNoStore(_ color: [UInt8]) -> Bool {
        guard color.count == 3 else { return false }
        let success = sendLightingCommand(args: [
            0x00,
            PacketSpec.ledBacklight,
            PacketSpec.effectStatic,
            PacketSpec.reservedA,
            PacketSpec.reservedB,
            PacketSpec.reservedC,
            color[0],
            color[1],
            color[2]
        ])
        if success {
            setModeState(mode: .staticNoStore, args: color)
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
        }
    }

    func probeWriteAccess() -> Bool {
        return connection.connectAndDisconnectProbe()
    }

    func packetForStatic(red: UInt8, green: UInt8, blue: UInt8) -> [UInt8] {
        return buildPacket(args: [
            PacketSpec.variableStorage,
            PacketSpec.ledBacklight,
            PacketSpec.effectStatic,
            PacketSpec.reservedA,
            PacketSpec.reservedB,
            PacketSpec.reservedC,
            red,
            green,
            blue
        ])
    }

    private func sendLightingCommand(args: [UInt8]) -> Bool {
        guard args.count <= (PacketSpec.checksumIndex - PacketSpec.argsStartIndex) else { return false }
        let packet = buildPacket(args: args)
        return connection.sendReportToMatchingDevices(data: packet, reportID: PacketSpec.reportID)
    }

    private func buildPacket(args: [UInt8]) -> [UInt8] {
        var packet = [UInt8](repeating: 0x00, count: PacketSpec.packetSize)
        packet[0] = 0x00
        packet[1] = PacketSpec.transactionByte
        packet[2] = 0x00
        packet[3] = 0x00
        packet[4] = 0x00
        packet[PacketSpec.dataSizeIndex] = UInt8(args.count)
        packet[PacketSpec.commandClassIndex] = PacketSpec.commandClassLighting
        packet[PacketSpec.commandIDIndex] = PacketSpec.commandIDSetMatrixEffect

        for (index, value) in args.enumerated() {
            packet[PacketSpec.argsStartIndex + index] = value
        }

        packet[PacketSpec.checksumIndex] = calculateChecksum(packet)
        packet[89] = 0x00
        return packet
    }

    private func calculateChecksum(_ packet: [UInt8]) -> UInt8 {
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
}