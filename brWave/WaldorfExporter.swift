//
//  WaldorfExporter.swift
//  brWave
//
//  Exports Behringer Wave patches as Waldorf PPG Wave 3.V .fxb bank files.
//
//  This is the exact inverse of WaldorfImporter. Each Behringer patch becomes
//  two consecutive FPCh float records (Group A + Group B), packed into an FBCh
//  outer container that the PPG Wave 3.V and 2.V plugins can load.
//
//  FXB structure (see docs/FXB_ANALYSIS.md for forensic detail):
//
//    FBCh outer header (160 bytes):
//      [0-3]   "CcnK"
//      [4-7]   byteSize = totalFileSize - 8 (UInt32 BE)
//      [8-11]  "FBCh"
//      [12-15] version = 1 (UInt32 BE)
//      [16-19] plugin ID "2901" (4 ASCII bytes)
//      [20-23] fxVersion = 1 (UInt32 BE)
//      [24-27] numPrograms = patch count (UInt32 BE)
//      [28-155] reserved (128 zero bytes)
//      [156-159] chunkSize = size of all FPCh records (UInt32 BE)
//
//    FPCh record per group (1417 bytes = 52 header + 1360 floats + 5 padding):
//      [0-3]   "FPCh"
//      [4-7]   version = 1 (UInt32 BE)
//      [8-11]  plugin ID "2901"
//      [12-15] fxVersion = 0 (UInt32 BE)
//      [16-19] 0x00000159 (UInt32 BE)
//      [20-47] patch name (28 bytes ASCII, null-padded)
//      [48-51] float array size = 1360 (UInt32 BE)
//      [52-1411] 340 × Float32 BE
//      [1412-1416] 5 zero padding bytes
//
//  Float index mapping is the inverse of WaldorfImporter.buildGroupBytes.
//  All unmapped float indices remain 0.0 (safe PPG plugin defaults).
//

import Foundation
import CoreData
import UniformTypeIdentifiers

// MARK: - Public entry point

enum WaldorfExporter {

    /// Export an array of Patch objects to .fxb bank data.
    /// Returns nil if patches is empty or all have empty payloads.
    static func exportFXB(patches: [Patch]) -> Data? {
        let valid = patches.filter { !$0.rawBytes.isEmpty }
        guard !valid.isEmpty else { return nil }

        // Build all FPCh records (2 per patch: Group A + Group B)
        var recordBytes: [UInt8] = []
        for patch in valid {
            let payload = patch.rawBytes
            guard payload.count >= 121 else { continue }
            let name = patchNameString(payload)
            recordBytes.append(contentsOf: makeFPChRecord(name: name, payload: payload, groupOffset: 19))  // Group A
            recordBytes.append(contentsOf: makeFPChRecord(name: name, payload: payload, groupOffset: 70))  // Group B
        }

        let patchCount = valid.count
        let chunkSize  = recordBytes.count

        // FBCh outer header (160 bytes)
        var header = [UInt8](repeating: 0, count: 160)

        // CcnK
        header[0] = 0x43; header[1] = 0x63; header[2] = 0x6E; header[3] = 0x4B
        // byteSize = total file size - 8
        let totalSize = 160 + chunkSize
        writeUInt32BE(&header, at: 4, value: UInt32(totalSize - 8))
        // FBCh
        header[8] = 0x46; header[9] = 0x42; header[10] = 0x43; header[11] = 0x68
        // version = 1
        writeUInt32BE(&header, at: 12, value: 1)
        // plugin ID "2901"
        header[16] = 0x32; header[17] = 0x39; header[18] = 0x30; header[19] = 0x31
        // fxVersion = 1
        writeUInt32BE(&header, at: 20, value: 1)
        // numPrograms = patch count (not record count — plugin pairs them internally)
        writeUInt32BE(&header, at: 24, value: UInt32(patchCount))
        // [28-155]: reserved zeros (already zero from repeating: 0)
        // chunkSize
        writeUInt32BE(&header, at: 156, value: UInt32(chunkSize))

        return Data(header + recordBytes)
    }
}

// MARK: - FPCh record builder

/// Build one 1417-byte FPCh record from a group within a 121-byte Behringer payload.
/// groupOffset is 19 (Group A) or 70 (Group B).
private func makeFPChRecord(name: String, payload: [UInt8], groupOffset: Int) -> [UInt8] {
    var record = [UInt8](repeating: 0, count: 1417)

    // "FPCh"
    record[0] = 0x46; record[1] = 0x50; record[2] = 0x43; record[3] = 0x68
    // version = 1
    writeUInt32BE(&record, at: 4, value: 1)
    // plugin ID "2901"
    record[8] = 0x32; record[9] = 0x39; record[10] = 0x30; record[11] = 0x31
    // fxVersion = 0 at +12 (already zero)
    // unknown field = 0x159 at +16
    writeUInt32BE(&record, at: 16, value: 0x159)
    // patch name at +20, 28 bytes null-padded
    let nameBytes = Array(name.utf8.prefix(28))
    for (i, b) in nameBytes.enumerated() { record[20 + i] = (b >= 32 && b <= 126) ? b : 0x20 }
    // float array size at +48
    writeUInt32BE(&record, at: 48, value: 1360)

    // Build 340-float array (Group A or B)
    let group = Array(payload[groupOffset..<min(groupOffset + 51, payload.count)])
    let floats = buildFloatArray(behGroup: group, sharedPayload: payload, isGroupA: groupOffset == 19)

    // Write 340 floats as big-endian Float32 starting at +52
    for (i, f) in floats.enumerated() {
        let bits = f.bitPattern
        record[52 + i * 4 + 0] = UInt8((bits >> 24) & 0xFF)
        record[52 + i * 4 + 1] = UInt8((bits >> 16) & 0xFF)
        record[52 + i * 4 + 2] = UInt8((bits >>  8) & 0xFF)
        record[52 + i * 4 + 3] = UInt8( bits        & 0xFF)
    }
    // [1412-1416]: 5-byte padding already zero

    return record
}

// MARK: - Float array builder (inverse of WaldorfImporter.buildGroupBytes)

/// Builds a 340-element Float32 array from a 51-byte Behringer group block.
/// isGroupA = true when building Group A (needed for shared params like WAVETB / KEYB).
private func buildFloatArray(behGroup: [UInt8], sharedPayload: [UInt8], isGroupA: Bool) -> [Float32] {
    var f = [Float32](repeating: 0.0, count: 340)

    func b(_ offset: Int) -> UInt8 {
        offset < behGroup.count ? behGroup[offset] : 0
    }

    // Shared params — only write from Group A record so Group B doesn't clobber them.
    // The FXB float map stores WAVETB and KEYB in every record; both A and B records
    // in the original FXB have the same values for these (they're truly shared).
    if isGroupA {
        f[29] = Float32(sharedPayload[16]) / 127.0   // WAVETB
        f[32] = Float32(sharedPayload[18]) / 9.0     // KEYB MODE
    } else {
        // Group B records in real FXBs carry the same shared values — replicate them.
        f[29] = Float32(sharedPayload[16]) / 127.0
        f[32] = Float32(sharedPayload[18]) / 9.0
    }

    // +0: DETU (0–9) → float[36]
    f[36] = Float32(b(0)) / 9.0

    // +1: MO (0–1) → float[37], bipolar: OFF=0.5, ON=1.0
    f[37] = b(1) > 0 ? 1.0 : 0.5

    // +2: MS (0–1) → float[38], bipolar
    f[38] = b(2) > 0 ? 1.0 : 0.5

    // +3: EO (0–9) → float[39]
    f[39] = Float32(b(3)) / 9.0

    // +4: ES (0–1) → float[40], bipolar
    f[40] = b(4) > 0 ? 1.0 : 0.5

    // +5–+12: SEMIT V1–V8 (0–63) → floats[41–48]
    for v in 0..<8 { f[41 + v] = Float32(b(5 + v)) / 63.0 }

    // +13: LFO DELAY (0–127) → float[5]
    f[5] = Float32(b(13)) / 127.0

    // +14: LFO WAVESHAPE (0–127) → float[6]
    f[6] = Float32(b(14)) / 127.0

    // +15: LFO RATE (0–127) → float[7]
    f[7] = Float32(b(15)) / 127.0

    // +16: ENV1 ATK (0–127) → float[11]
    f[11] = Float32(b(16)) / 127.0

    // +17: ENV1 DEC (0–127) → float[12]
    f[12] = Float32(b(17)) / 127.0

    // +18: ENV1 SUS (0–127) → float[13]
    f[13] = Float32(b(18)) / 127.0

    // +19: ENV1 REL (0–127) → float[14]
    f[14] = Float32(b(19)) / 127.0

    // +20: VCF CUTOFF (0–63 in Beh, but imported at ×127 scale) → float[19]
    //   Import: b[20] = round(float[19] × 127). Export inverse: float[19] = b[20] / 127.
    f[19] = Float32(b(20)) / 127.0

    // +21: VCF EMPHASIS → float[20]
    f[20] = Float32(b(21)) / 127.0

    // +22: WAVES-OSC (0–63) → float[21]
    f[21] = Float32(b(22)) / 63.0

    // +23: WAVES-SUB (0–63) → float[22]
    f[22] = Float32(b(23)) / 63.0

    // +24: ENV3 ATK → float[8]
    f[8] = Float32(b(24)) / 127.0

    // +25: ENV3 DEC → float[9]
    f[9] = Float32(b(25)) / 127.0

    // +26: ENV3 ATT → float[10]
    f[10] = Float32(b(26)) / 127.0

    // +27: ENV2 ATK → float[15]
    f[15] = Float32(b(27)) / 127.0

    // +28: ENV2 DEC → float[16]
    f[16] = Float32(b(28)) / 127.0

    // +29: ENV2 SUS → float[17]
    f[17] = Float32(b(29)) / 127.0

    // +30: ENV2 REL → float[18]
    f[18] = Float32(b(30)) / 127.0

    // +31: MOD WHL — no confirmed FXB index; skip (leave 0)

    // +32: ENV1→VCF → float[23]
    f[23] = Float32(b(32)) / 127.0

    // +33: ENV2→VCA → float[24]
    f[24] = Float32(b(33)) / 127.0

    // +34: ENV1→WAVES → float[25]
    f[25] = Float32(b(34)) / 127.0

    // +35: UW (0–2) → float[30], 0.0=off, 1.0=on (>0 in Beh maps to "on")
    f[30] = b(35) > 0 ? 1.0 : 0.0

    // +36: SW (Sub Osc Mode, 0–6) → float[31]
    f[31] = Float32(b(36)) / 6.0

    // +37: KW (Key→Wave, 0–7) → float[49]
    f[49] = Float32(b(37)) / 7.0

    // +38: KF (Key→Filter, 0–7) → float[50]
    f[50] = Float32(b(38)) / 7.0

    // +39: KL (Key→Loud, 0–7) → float[51]
    f[51] = Float32(b(39)) / 7.0

    // +40: MW (Mod→Wave, 0–9) → float[54], bipolar: float = 0.5 + beh / (9 × 2)
    f[54] = 0.5 + Float32(b(40)) / 18.0

    // +41: MF (Mod→Filter, 0–9) → float[55]
    f[55] = 0.5 + Float32(b(41)) / 18.0

    // +42: ML (Mod→Loud, 0–1) → float[56], bipolar toggle
    f[56] = b(42) > 0 ? 1.0 : 0.5

    // +43: BD — no confirmed FXB index; skip

    // +44: BI (Bender Interval, 0–5) → float[73]
    f[73] = Float32(b(44)) / 5.0

    // +45: TW (Touch→Wave, 0–2) → float[57]
    f[57] = Float32(b(45)) / 2.0

    // +46: TF (Touch→Filter, 0–2) → float[58]
    f[58] = Float32(b(46)) / 2.0

    // +47: TL (Touch→Loud, 0–2) → float[59]
    f[59] = Float32(b(47)) / 2.0

    // +48: TM (Touch→Mod, 0–1) → float[60]
    f[60] = Float32(b(48))

    // +49: VF (Vel→Filter, 0–3) → float[52], bipolar: float = 0.5 + beh / (3 × 2)
    f[52] = 0.5 + Float32(b(49)) / 6.0

    // +50: VL (Vel→Loud, 0–3) → float[53]
    f[53] = 0.5 + Float32(b(50)) / 6.0

    return f
}

// MARK: - Helpers

private func patchNameString(_ payload: [UInt8]) -> String {
    let nameBytes = payload[0..<16].prefix(while: { $0 != 0 && $0 >= 32 })
    return String(bytes: nameBytes, encoding: .ascii)?.trimmingCharacters(in: .whitespaces) ?? "Untitled"
}

private func writeUInt32BE(_ buf: inout [UInt8], at offset: Int, value: UInt32) {
    buf[offset + 0] = UInt8((value >> 24) & 0xFF)
    buf[offset + 1] = UInt8((value >> 16) & 0xFF)
    buf[offset + 2] = UInt8((value >>  8) & 0xFF)
    buf[offset + 3] = UInt8( value        & 0xFF)
}
