//
//  OrchestratorTests.swift
//  OrchestratorTests
//
//  Created by Balogh Barnabás on 2026. 03. 21..
//

import Testing
@testable import Orchestrator

struct OrchestratorTests {

    @MainActor
    @Test func razerKeyboardStaticPacketHasExpectedLayout() async throws {
        let keyboard = RazerKeyboardDevice(model: .blackWidowV4)
        let packet = keyboard.packetForStatic(red: 0x12, green: 0x34, blue: 0x56)

        #expect(packet.count == 90)
        #expect(packet[0] == 0x00)
        #expect(packet[1] == 0x3F)
        #expect(packet[5] == 0x09)
        #expect(packet[6] == 0x0F)
        #expect(packet[7] == 0x02)
        #expect(packet[8] == 0x01)
        #expect(packet[9] == 0x05)
        #expect(packet[10] == 0x01)
        #expect(packet[11] == 0x00)
        #expect(packet[12] == 0x00)
        #expect(packet[13] == 0x01)
        #expect(packet[14] == 0x12)
        #expect(packet[15] == 0x34)
        #expect(packet[16] == 0x56)
        #expect(packet[89] == 0x00)
    }

    @MainActor
    @Test func razerKeyboardPacketChecksumMatchesXor() async throws {
        let keyboard = RazerKeyboardDevice(model: .huntsmanV2)
        let packet = keyboard.packetForStatic(red: 0xFF, green: 0x00, blue: 0xA5)

        var checksum: UInt8 = 0
        for i in 2..<88 {
            checksum ^= packet[i]
        }

        #expect(packet[88] == checksum)
    }

}
