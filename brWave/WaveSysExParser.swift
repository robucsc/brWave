//
//  WaveSysExParser.swift
//  brWave
//
//  Behringer Wave SysEx pack / unpack.
//
//  SysEx structure:
//    F0  00 20 32  00 01 39  00  PKT  [SPKT]  [Data]  [Checksum]  F7
//         ^MfrID    ^ModelID  ^DevID
//
//  No MS-bit packing (unlike Sequential). Raw bytes + checksum.
//  Checksum = (u8)(D0 + D1 + ... + Dn) & 0x7F, appended after data.
//
//  Preset payload: 121 bytes (D0–D120).
//  Sequencer payload: 577 bytes.
//  Global payload: 19 bytes.
//

import Foundation

// MARK: - Parsed patch

struct WaveParsedPatch {
    var name: String                          // 16 chars, ASCII 32–126
    var wavetb: Int                           // byte 16
    var split: Int                            // byte 17
    var keyb: Int                             // byte 18
    var groupA: [WaveParamID: Int]            // per-group params, Group A
    var groupB: [WaveParamID: Int]            // per-group params, Group B
    var rawBytes: [UInt8]                     // full 121-byte preset payload
    var bank: Int?
    var program: Int?

    func value(for id: WaveParamID, group: WaveGroup) -> Int {
        switch group {
        case .a: return groupA[id] ?? 0
        case .b: return groupB[id] ?? 0
        }
    }
}

// MARK: - Header constants

enum WaveSysEx {
    static let sysexStart: UInt8  = 0xF0
    static let sysexEnd: UInt8    = 0xF7
    static let mfrID: [UInt8]     = [0x00, 0x20, 0x32]   // Behringer GmbH
    static let modelID: [UInt8]   = [0x00, 0x01, 0x39]   // WAVE
    static let deviceID: UInt8    = 0x00
    static let pktWave: UInt8     = 0x74                  // Wave-specific packet type

    // Sub-packet types (SPKT)
    static let spktRequestPreset: UInt8   = 0x05
    static let spktPresetData: UInt8      = 0x06          // Wave→host OR host→Wave
    static let spktRequestEditBuf: UInt8  = 0x07
    static let spktEditBufData: UInt8     = 0x08          // Wave→host OR host→Wave
    static let spktPresetAck: UInt8       = 0x0A          // Wave ACK after receiving preset
    static let spktEditBufAck: UInt8      = 0x0C          // Wave ACK after receiving edit buf
    static let spktRequestSeq: UInt8      = 0x0D
    static let spktSeqData: UInt8         = 0x0E
    static let spktRequestEditSeq: UInt8  = 0x0F
    static let spktEditSeqData: UInt8     = 0x10
    static let spktWTReceive: UInt8       = 0x5D          // Send wavetable to Wave
    static let spktWTAck: UInt8           = 0x5E          // Wave ACK for WT receive
    static let spktRequestWTNames: UInt8  = 0x5F
    static let spktWTNames: UInt8         = 0x60
    static let pktRequestGlobal: UInt8    = 0x75
    static let pktGlobalData: UInt8       = 0x76

    static let version: UInt8 = 0x00
}

// MARK: - Parser

enum WaveSysExParser {

    // MARK: Parse incoming SysEx

    /// Parse a complete SysEx byte array from the Wave.
    /// Returns a WaveParsedPatch if it is a valid preset or edit-buffer response.
    static func parse(_ bytes: [UInt8]) -> WaveParsedPatch? {
        guard isWaveMessage(bytes) else { return nil }

        let pkt = bytes[8]
        guard pkt == WaveSysEx.pktWave else { return nil }

        let spkt = bytes[9]

        switch spkt {
        case WaveSysEx.spktPresetData:
            // F0 MfrID ModelID DevID 0x74 0x06 Bank Preset Version D0...D120 Checksum F7
            // indices:  0  1-3   4-6   7   8    9   10   11      12  13...133  134     135
            guard bytes.count >= 136 else { return nil }
            let bank    = Int(bytes[10])
            let preset  = Int(bytes[11])
            let payload = Array(bytes[13..<134])    // 121 bytes D0–D120
            return parsePresetPayload(payload, bank: bank, program: preset)

        case WaveSysEx.spktEditBufData:
            // F0 MfrID ModelID DevID 0x74 0x08 Version D0...D120 Checksum F7
            // indices:  0  1-3   4-6   7   8    9     10  11...131  132     133
            guard bytes.count >= 134 else { return nil }
            let payload = Array(bytes[11..<132])    // 121 bytes
            return parsePresetPayload(payload, bank: nil, program: nil)

        default:
            return nil
        }
    }

    /// Extract and validate preset payload (121 bytes) into WaveParsedPatch.
    static func parsePresetPayload(_ payload: [UInt8], bank: Int?, program: Int?) -> WaveParsedPatch? {
        guard payload.count == WaveParameters.presetPayloadLength else { return nil }

        // Name: bytes 0–15, ASCII 32–126
        let nameBytes = Array(payload[0..<16])
        let name = String(bytes: nameBytes, encoding: .ascii)?
            .trimmingCharacters(in: .init(charactersIn: " ")) ?? "Untitled"

        let wavetb = Int(payload[16])
        let split  = Int(payload[17])
        let keyb   = Int(payload[18])

        let groupA = extractGroup(from: payload, base: WaveParameters.groupABase)
        let groupB = extractGroup(from: payload, base: WaveParameters.groupBBase)

        return WaveParsedPatch(
            name: name,
            wavetb: wavetb,
            split: split,
            keyb: keyb,
            groupA: groupA,
            groupB: groupB,
            rawBytes: payload,
            bank: bank,
            program: program
        )
    }

    // MARK: - Generate outgoing SysEx

    /// Build a "Request Program Preset" message.
    static func requestPreset(bank: Int, program: Int) -> [UInt8] {
        var msg = header()
        msg.append(WaveSysEx.pktWave)
        msg.append(WaveSysEx.spktRequestPreset)
        msg.append(UInt8(bank & 0x7F))
        msg.append(UInt8(program & 0x7F))
        msg.append(WaveSysEx.sysexEnd)
        return msg
    }

    /// Build a "Request Edit Buffer" message.
    static func requestEditBuffer() -> [UInt8] {
        var msg = header()
        msg.append(WaveSysEx.pktWave)
        msg.append(WaveSysEx.spktRequestEditBuf)
        msg.append(WaveSysEx.sysexEnd)
        return msg
    }

    /// Build a "Dump preset data to Wave" message (SPKT 0x06).
    /// Send to store into a specific bank/program slot.
    static func dumpToPreset(bank: Int, program: Int, payload: [UInt8]) -> [UInt8] {
        var msg = header()
        msg.append(WaveSysEx.pktWave)
        msg.append(WaveSysEx.spktPresetData)
        msg.append(UInt8(bank & 0x7F))
        msg.append(UInt8(program & 0x7F))
        msg.append(WaveSysEx.version)
        msg.append(contentsOf: payload)
        msg.append(checksum(for: payload))
        msg.append(WaveSysEx.sysexEnd)
        return msg
    }

    /// Build a "Dump preset data to edit buffer" message (SPKT 0x08).
    static func dumpToEditBuffer(payload: [UInt8]) -> [UInt8] {
        var msg = header()
        msg.append(WaveSysEx.pktWave)
        msg.append(WaveSysEx.spktEditBufData)
        msg.append(WaveSysEx.version)
        msg.append(contentsOf: payload)
        msg.append(checksum(for: payload))
        msg.append(WaveSysEx.sysexEnd)
        return msg
    }

    /// Build a preset payload (121 bytes) from a WaveParsedPatch.
    static func buildPayload(from patch: WaveParsedPatch) -> [UInt8] {
        var payload = [UInt8](repeating: 0, count: WaveParameters.presetPayloadLength)

        // Name: bytes 0–15
        let nameBytes = Array(patch.name.utf8.prefix(16))
        for i in 0..<16 {
            payload[i] = i < nameBytes.count ? (nameBytes[i] & 0x7F) : 0x20  // pad with space
        }

        // Shared
        payload[16] = UInt8(clamping: patch.wavetb)
        payload[17] = UInt8(clamping: patch.split)
        payload[18] = UInt8(clamping: patch.keyb)

        // Group A & B
        writeGroup(patch.groupA, into: &payload, base: WaveParameters.groupABase)
        writeGroup(patch.groupB, into: &payload, base: WaveParameters.groupBBase)

        return payload
    }

    // MARK: - ACK check

    static func isPresetAck(_ bytes: [UInt8]) -> Bool {
        guard isWaveMessage(bytes), bytes.count >= 12 else { return false }
        return bytes[8] == WaveSysEx.pktWave && bytes[9] == WaveSysEx.spktPresetAck && bytes[11] == 1
    }

    static func isEditBufAck(_ bytes: [UInt8]) -> Bool {
        guard isWaveMessage(bytes), bytes.count >= 11 else { return false }
        return bytes[8] == WaveSysEx.pktWave && bytes[9] == WaveSysEx.spktEditBufAck && bytes[10] == 1
    }

    // MARK: - File I/O

    /// Load .syx file, return all parsed patches found within it.
    static func parseSYXFile(at url: URL) -> [WaveParsedPatch] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return parseSYXData(Array(data))
    }

    /// Parse a raw byte array that may contain multiple concatenated SysEx messages.
    static func parseSYXData(_ bytes: [UInt8]) -> [WaveParsedPatch] {
        var patches: [WaveParsedPatch] = []
        var i = 0
        while i < bytes.count {
            guard bytes[i] == 0xF0 else { i += 1; continue }
            if let end = bytes[i...].firstIndex(of: 0xF7) {
                let msg = Array(bytes[i...end])
                if let patch = parse(msg) {
                    patches.append(patch)
                }
                i = end + 1
            } else {
                break
            }
        }
        return patches
    }

    // MARK: - Private helpers

    private static func header() -> [UInt8] {
        var h: [UInt8] = [WaveSysEx.sysexStart]
        h.append(contentsOf: WaveSysEx.mfrID)
        h.append(contentsOf: WaveSysEx.modelID)
        h.append(WaveSysEx.deviceID)
        return h
    }

    private static func checksum(for payload: [UInt8]) -> UInt8 {
        let sum = payload.reduce(0) { Int($0) + Int($1) }
        return UInt8(sum & 0x7F)
    }

    private static func isWaveMessage(_ bytes: [UInt8]) -> Bool {
        guard bytes.count >= 10 else { return false }
        guard bytes.first == WaveSysEx.sysexStart else { return false }
        guard bytes.last  == WaveSysEx.sysexEnd   else { return false }
        guard Array(bytes[1..<4]) == WaveSysEx.mfrID   else { return false }
        guard Array(bytes[4..<7]) == WaveSysEx.modelID else { return false }
        return true
    }

    private static func extractGroup(from payload: [UInt8], base: Int) -> [WaveParamID: Int] {
        var result: [WaveParamID: Int] = [:]
        for desc in WaveParameters.all {
            if case .perGroup(let offset) = desc.storage {
                let idx = base + offset
                guard idx < payload.count else { continue }
                result[desc.id] = Int(payload[idx])
            }
        }
        return result
    }

    private static func writeGroup(_ group: [WaveParamID: Int], into payload: inout [UInt8], base: Int) {
        for desc in WaveParameters.all {
            if case .perGroup(let offset) = desc.storage {
                let idx = base + offset
                guard idx < payload.count else { continue }
                payload[idx] = UInt8(clamping: group[desc.id] ?? 0)
            }
        }
    }
}

// MARK: - Checksum validation

extension WaveSysExParser {

    /// Verify the checksum of an incoming preset payload.
    static func validateChecksum(payload: [UInt8], received: UInt8) -> Bool {
        checksum(for: payload) == received
    }
}
