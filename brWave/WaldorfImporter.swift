//
//  WaldorfImporter.swift
//  brWave
//
//  Imports Waldorf PPG Wave 3.V / 2.V .fxb bank files into CoreData.
//
//  Format forensics documented in docs/FXB_ANALYSIS.md.
//
//  KEY FACTS:
//  - FXB outer container: FBCh block. Chunk payload starts after outer header.
//  - Each patch stored as FPCh record (float32 parameter array, big-endian).
//  - PPG Wave 3.V: 340 floats per record (1360 bytes). 2.V: 339 floats.
//  - DUAL PATCHES: each Behringer patch = TWO consecutive FPCh records.
//    record[N*2]   = Group A sound (floats 0–339)
//    record[N*2+1] = Group B sound — SAME float index map as Group A
//  - Shared params (WAVETB, KEYB): read from the Group A record.
//  - Effects section floats[230–337]: no Behringer SysEx equivalent, skipped.
//  - Sentinel value -134217728.0 = unset slot, treat as 0.
//
//  Float index → Behringer byte map:
//    Confirmed via mod-file diffs (see FXB_ANALYSIS.md Session 4).
//    Scale "÷63" → float encodes 0–63 in 0.0–1.0 → Beh = round(f×127) for 0-127 params.
//    Scale "÷63" → Beh = round(f×63) for 0-63 params (semitones).
//

import Foundation
import AppKit
import CoreData
import UniformTypeIdentifiers

// MARK: - Public entry point

enum WaldorfImporter {

    /// Import one or more .fxp single-preset files.
    /// Each FXP contains one group of floats. Group B is set equal to Group A on import
    /// (no dual-group in a standalone FXP — user can diverge Group B afterwards).
    @MainActor
    static func importFXP(urls: [URL], into context: NSManagedObjectContext) {
        var totalImported = 0

        for url in urls {
            guard let data = try? Data(contentsOf: url),
                  let record = parseFXPRecord(from: data) else { continue }

            // Single group — duplicate to A and B
            let patchName = importName(record.name, sourceMarker: "3")
            guard let payload = buildPayload(recordA: record, recordB: record, patchName: patchName) else { continue }

            let patch = Patch(context: context)
            patch.uuid            = UUID()
            patch.dateCreated     = Date()
            patch.dateModified    = Date()
            patch.name            = patchName
            patch.designer        = importDesigner(
                source: "Waldorf PPG Wave 3.V",
                fileName: url.lastPathComponent,
                extra: "FXP import"
            )
            patch.bank            = -1
            patch.program         = 0
            patch.rawSysexPayload = Data(payload)
            patch.patchValues     = valuesFromPayload(payload)
            patch.category        = PatchCategory.classify(patchName: patchName).rawValue

            // Each FXP imports as its own single-patch library
            let libName = url.deletingPathExtension().lastPathComponent
            let patchSet = PatchSet.findOrCreate(named: libName, in: context)
            patchSet.modifiedAt = Date()
            PatchSlot.make(position: 0, patch: patch, in: patchSet, ctx: context)
            totalImported += 1
        }

        if totalImported > 0 { try? context.save() }
    }

    /// Import .fxb files from the provided URLs.
    @MainActor
    static func importFXB(urls: [URL], into context: NSManagedObjectContext) {
        var totalImported = 0

        for url in urls {
            guard let data = try? Data(contentsOf: url) else { continue }

            let records = parseFPChRecords(from: data)
            guard records.count >= 2 else { continue }

            // Pair consecutive records: (A, B) per patch
            let patchCount = records.count / 2
            guard patchCount > 0 else { continue }

            let libraryName = url.deletingPathExtension().lastPathComponent
            let patchSet = PatchSet.findOrCreate(named: libraryName, in: context)
            patchSet.modifiedAt = Date()

            for n in 0..<patchCount {
                let recA = records[n * 2]
                let recB = records[n * 2 + 1]

                let patchName = importName(recA.name, sourceMarker: "3")
                guard let payload = buildPayload(recordA: recA, recordB: recB, patchName: patchName) else { continue }

                let patch = Patch(context: context)
                patch.uuid            = UUID()
                patch.dateCreated     = Date()
                patch.dateModified    = Date()
                patch.name            = patchName
                patch.designer        = importDesigner(
                    source: "Waldorf PPG Wave 3.V",
                    fileName: url.lastPathComponent,
                    extra: "FXB import"
                )
                patch.bank            = -1
                patch.program         = Int16(n)
                patch.rawSysexPayload = Data(payload)
                patch.patchValues     = valuesFromPayload(payload)
                patch.category        = PatchCategory.classify(patchName: patchName).rawValue

                // Assign sequential slot positions (0-based within the library)
                PatchSlot.make(position: n, patch: patch, in: patchSet, ctx: context)
                totalImported += 1
            }
        }

        if totalImported > 0 {
            try? context.save()
        }
    }
}

// MARK: - FPCh Record

private struct FPChRecord {
    let name:   String          // up to 16 chars for Beh name field
    let floats: [Float32]       // 339 (2.V) or 340 (3.V) big-endian floats
}

// MARK: - FXP single-preset parser

/// Parse a standalone .fxp file (CcnK outer wrapper + FPCh program chunk).
///
/// FXP layout (offsets from file start):
///   [0]  CcnK
///   [4]  byteSize
///   [8]  FPCh  ← fxMagic
///   [12] version
///   [16] fxID "2901"
///   [20] fxVersion
///   [24] pchName (28 bytes)
///   [52] chunkSize (UInt32 BE)
///   [56] float data (340 × Float32 BE for 3.V, 339 for 2.V)
///
/// This differs from FBCh-embedded FPCh records: in those, FPCh sits at offset 0
/// within the record (not 8), and has an extra 4-byte field between fxID and the name,
/// shifting name/floats 4 bytes later (+20/+52 vs +24/+56 within the FPCh block).
private func parseFXPRecord(from data: Data) -> FPChRecord? {
    let bytes = [UInt8](data)
    guard bytes.count >= 60 else { return nil }

    // Validate CcnK + FPCh magic
    let ccnk: [UInt8] = [0x43, 0x63, 0x6E, 0x4B]
    let fpch: [UInt8] = [0x46, 0x50, 0x43, 0x68]
    guard bytes[0...3].elementsEqual(ccnk) &&
          bytes[8...11].elementsEqual(fpch) else { return nil }

    // Name at offset 24, 28 bytes null-padded
    let nameBytes = bytes[24..<52].prefix(while: { $0 != 0 && $0 >= 32 })
    let name = (String(bytes: nameBytes, encoding: .ascii) ?? "Untitled")
                   .trimmingCharacters(in: .whitespaces)

    // Float array size at offset 52
    let floatByteCount = readUInt32BE(bytes, at: 52)
    let floatCount = Int(floatByteCount) / 4
    guard floatCount >= 100,
          56 + Int(floatByteCount) <= bytes.count else { return nil }

    // Float data at offset 56
    var floats = [Float32](repeating: 0, count: floatCount)
    for f in 0..<floatCount {
        let offset = 56 + f * 4
        let bits = readUInt32BE(bytes, at: offset)
        floats[f] = Float32(bitPattern: bits)
    }

    return FPChRecord(name: name.isEmpty ? "Untitled" : name, floats: floats)
}

// MARK: - FPCh Parsing

private func parseFPChRecords(from data: Data) -> [FPChRecord] {
    var records: [FPChRecord] = []
    let bytes = [UInt8](data)
    let magic: [UInt8] = [0x46, 0x50, 0x43, 0x68]   // "FPCh"

    var i = 0
    while i <= bytes.count - 4 {
        // Scan for FPCh magic
        if bytes[i] == magic[0] && bytes[i+1] == magic[1] &&
           bytes[i+2] == magic[2] && bytes[i+3] == magic[3] {

            let base = i

            // Name at +20, 28 bytes ASCII null-padded
            guard base + 52 <= bytes.count else { i += 1; continue }
            let nameBytes = bytes[(base + 20)..<(base + 48)]
            let name = String(bytes: nameBytes.prefix(while: { $0 != 0 && $0 >= 32 }),
                              encoding: .ascii) ?? "Untitled"
            let truncated = String(name.prefix(16)).trimmingCharacters(in: .whitespaces)

            // Float array size at +48 (UInt32 big-endian)
            let floatByteCount = readUInt32BE(bytes, at: base + 48)
            let floatCount = Int(floatByteCount) / 4
            guard floatCount >= 100 else { i += 1; continue }   // sanity check
            guard base + 52 + Int(floatByteCount) <= bytes.count else { i += 1; continue }

            // Read floats
            var floats = [Float32](repeating: 0, count: floatCount)
            for f in 0..<floatCount {
                let offset = base + 52 + f * 4
                let bits = readUInt32BE(bytes, at: offset)
                floats[f] = Float32(bitPattern: bits)
            }

            records.append(FPChRecord(name: truncated.isEmpty ? "Untitled" : truncated,
                                      floats: floats))

            // Advance past this record to avoid false-positive re-match inside floats
            i = base + 52 + Int(floatByteCount)
        } else {
            i += 1
        }
    }

    return records
}

// MARK: - Payload Builder

/// Builds a 121-byte Behringer Wave SysEx preset payload from an A+B FPCh pair.
private func buildPayload(recordA: FPChRecord, recordB: FPChRecord, patchName: String) -> [UInt8]? {
    var payload = [UInt8](repeating: 0, count: 121)

    // Bytes 0–15: Name (16 ASCII chars, space-padded)
    let nameBytes = Array(patchName.utf8.prefix(16))
    for i in 0..<min(nameBytes.count, 16) {
        let c = nameBytes[i]
        payload[i] = (c >= 32 && c <= 126) ? c : 0x20
    }
    for i in nameBytes.count..<16 { payload[i] = 0x20 }   // space pad

    // Byte 16: WAVETB (shared) — float[29] ÷127
    payload[16] = UInt8(clamping: scaleLinear(recordA.floats, index: 29, max: 127))

    // Byte 17: SPLIT (not in FXB — default 0)
    payload[17] = 0

    // Byte 18: KEYB (shared) — float[32], discrete 0-9
    payload[18] = UInt8(clamping: scaleLinear(recordA.floats, index: 32, max: 9))

    // Bytes 19–69: Group A (51 bytes)
    let groupA = buildGroupBytes(from: recordA.floats)
    for i in 0..<51 { payload[19 + i] = groupA[i] }

    // Bytes 70–120: Group B (same float map)
    let groupB = buildGroupBytes(from: recordB.floats)
    for i in 0..<51 { payload[70 + i] = groupB[i] }

    return payload
}

// MARK: - Group byte builder

/// Maps one FPCh float array to 51 Group bytes (offsets 0–50 within a group block).
/// Float indices and scales from FXB_ANALYSIS.md Session 4 confirmed map.
private func buildGroupBytes(from f: [Float32]) -> [UInt8] {
    var b = [UInt8](repeating: 0, count: 51)

    // Convenience: scale f[index] × limit → UInt8, with sentinel handling and clamping.
    func lin(_ index: Int, _ limit: Int) -> UInt8 {
        guard index < f.count else { return 0 }
        return UInt8(clamping: scaleLinear(f, index: index, max: limit))
    }

    // Bipolar: 0.5 = center/OFF, 1.0 = full ON. Maps to Behringer 0/1 toggle.
    func bipolarToggle(_ index: Int) -> UInt8 {
        guard index < f.count else { return 0 }
        let v = cleanFloat(f[index])
        return v > 0.75 ? 1 : 0
    }

    // Bipolar → stepped value. 0.5 = 0, 1.0 = limit.
    func bipolarStepped(_ index: Int, _ limit: Int) -> UInt8 {
        guard index < f.count else { return 0 }
        let v = cleanFloat(f[index])
        let raw = Int(round((v - 0.5) * Double(limit) * 2))
        return UInt8(clamping: Swift.max(0, raw))
    }

    // +0: DETU (Sub Osc Detune, 0–9) — float[36], nonlinear in PPG but linear approx is fine
    b[0] = lin(36, 9)

    // +1: MO (Mod→Main Osc, 0–1) — float[37], bipolar 0.5=OFF
    b[1] = bipolarToggle(37)

    // +2: MS (Mod→Sub Osc, 0–1) — float[38], bipolar
    b[2] = bipolarToggle(38)

    // +3: EO (ENV3→Main Osc, 0–9) — float[39], deduced (adjacent to MO/MS in param order)
    b[3] = lin(39, 9)

    // +4: ES (ENV3→Sub Osc, 0–1) — float[40], deduced
    b[4] = bipolarToggle(40)

    // +5–+12: SEMIT V1–V8 (0–63) — floats[41–48], confirmed r=1.000
    for v in 0..<8 { b[5 + v] = lin(41 + v, 63) }

    // +13: LFO DELAY (0–127) — float[5], confirmed mod13
    b[13] = lin(5, 127)

    // +14: LFO WAVESHAPE (0–127) — float[6], confirmed mod13
    //       PPG LFO shapes are discrete (saw/tri/square/etc). Linear scale approximates.
    b[14] = lin(6, 127)

    // +15: LFO RATE (0–127) — float[7], confirmed mod13
    b[15] = lin(7, 127)

    // +16: ENV1 Attack (0–127) — float[11], confirmed mod16
    b[16] = lin(11, 127)

    // +17: ENV1 Decay (0–127) — float[12], confirmed mod16
    b[17] = lin(12, 127)

    // +18: ENV1 Sustain (0–127) — float[13], confirmed mod16
    b[18] = lin(13, 127)

    // +19: ENV1 Release (0–127) — float[14], confirmed mod16
    b[19] = lin(14, 127)

    // +20: VCF Cutoff (0–127) — float[19], confirmed mod14
    b[20] = lin(19, 127)

    // +21: VCF Emphasis (0–127) — float[20], confirmed mod14
    b[21] = lin(20, 127)

    // +22: WAVES-OSC (0–63) — 64 wavetable cycles
    b[22] = lin(21, 63)

    // +23: WAVES-SUB (0–63) — 64 wavetable cycles
    b[23] = lin(22, 63)

    // +24: ENV3 Attack (0–127) — float[8], confirmed mod15
    b[24] = lin(8, 127)

    // +25: ENV3 Decay (0–127) — float[9], confirmed mod15
    b[25] = lin(9, 127)

    // +26: ENV3 Amount (0–127) — float[10], confirmed mod15
    b[26] = lin(10, 127)

    // +27: ENV2 Attack (0–127) — float[15], confirmed mod17
    b[27] = lin(15, 127)

    // +28: ENV2 Decay (0–127) — float[16], confirmed mod17
    b[28] = lin(16, 127)

    // +29: ENV2 Sustain (0–127) — float[17], confirmed mod17
    b[29] = lin(17, 127)

    // +30: ENV2 Release (0–127) — float[18], confirmed mod17
    b[30] = lin(18, 127)

    // +31: MOD WHL position (0–127) — no confirmed FXB index; default 0
    b[31] = 0

    // +32: ENV1→VCF (0–127) — float[23], confirmed mod9/mod19
    b[32] = lin(23, 127)

    // +33: ENV2→LOUDNESS (0–127) — float[24], confirmed mod9/mod19
    b[33] = lin(24, 127)

    // +34: ENV1→WAVES (0–127) — float[25], confirmed mod9/mod19
    b[34] = lin(25, 127)

    // +35: UW (Upper WT, 0–2) — float[30], 0/1 toggle → map 0.0=0, 1.0=2
    //       PPG had two WT sizes. Behringer has three (128/2048/8192). Map: off=0, on=2.
    b[35] = (cleanFloat(f[30]) > 0.5 && 30 < f.count) ? 2 : 0

    // +36: SW (Sub Osc Mode, 0–6) — float[31], discrete confirmed mod10
    b[36] = lin(31, 6)

    // +37: KW (Key→Wave, 0–7) — float[49], 15-step PPG → 8-step Wave; confirmed mod31
    b[37] = lin(49, 7)

    // +38: KF (Key→Filter, 0–7) — float[50], confirmed mod32
    b[38] = lin(50, 7)

    // +39: KL (Key→Loud, 0–7) — float[51], 8-step; confirmed mod33
    //       PPG display was inverted (1:10 = max) but Behringer is 0=off,7=max.
    //       Linear scale gives reasonable results.
    b[39] = lin(51, 7)

    // +40: MW (Mod→Wave, 0–9) — float[54], bipolar 0.5=OFF; confirmed mod28
    b[40] = bipolarStepped(54, 9)

    // +41: MF (Mod→Filter, 0–9) — float[55], bipolar; confirmed mod29
    b[41] = bipolarStepped(55, 9)

    // +42: ML (Mod→Loud, 0–1) — float[56], bipolar toggle; confirmed mod30
    b[42] = bipolarToggle(56)

    // +43: BD (Bender Destination, 0–7)
    //       PPG Wave bender was pitch-only. No direct FXB index confirmed.
    //       Default 2 = Pitch (Behringer BD value for pitch bend).
    b[43] = 2

    // +44: BI (Bender Interval, 0–5) — float[73], 13-step (0–12); confirmed mod34
    b[44] = lin(73, 5)

    // +45: TW (Touch→Wave, 0–2) — float[57], deduced (precedes TM at float[60])
    b[45] = lin(57, 2)

    // +46: TF (Touch→Filter, 0–2) — float[58], deduced
    b[46] = lin(58, 2)

    // +47: TL (Touch→Loud, 0–2) — float[59], deduced
    b[47] = lin(59, 2)

    // +48: TM (Touch→Mod, 0–1) — float[60], confirmed mod39
    b[48] = lin(60, 1)

    // +49: VF (Vel→Filter, 0–3) — float[52], bipolar center; confirmed mod24
    b[49] = bipolarStepped(52, 3)

    // +50: VL (Vel→Loud, 0–3) — float[53], bipolar center; confirmed mod25
    b[50] = bipolarStepped(53, 3)

    return b
}

// MARK: - Value store builder

/// Rebuilds WavePatchValues from the 121-byte payload so the panel can read params.
private func valuesFromPayload(_ payload: [UInt8]) -> WavePatchValues {
    var pv = WavePatchValues()
    let aBase = WaveParameters.groupABase   // 19
    let bBase = WaveParameters.groupBBase   // 70

    // Shared
    pv.setValue(Int(payload[16]), for: .wavetb, group: .a)
    pv.setValue(Int(payload[17]), for: .split,  group: .a)
    pv.setValue(Int(payload[18]), for: .keyb,   group: .a)

    // Per-group — iterate all perGroup params and read from payload
    for desc in WaveParameters.all {
        guard case .perGroup(let offset) = desc.storage else { continue }
        pv.setValue(Int(payload[aBase + offset]), for: desc.id, group: .a)
        pv.setValue(Int(payload[bBase + offset]), for: desc.id, group: .b)
    }

    return pv
}

// MARK: - Scaling helpers

/// Clamps known sentinels, NaN/infinity, and absurd magnitudes to 0.0.
private func cleanFloat(_ v: Float32) -> Double {
    guard v.isFinite else { return 0.0 }
    let dv = Double(v)
    guard dv > -1e6, dv < 1e6 else { return 0.0 }
    return dv
}

/// Linear scale: round(cleanFloat(f[index]) × max), clamped to 0…max.
private func scaleLinear(_ f: [Float32], index: Int, max: Int) -> Int {
    guard index < f.count else { return 0 }
    let v = cleanFloat(f[index])
    let scaled = v * Double(max)
    guard scaled.isFinite else { return 0 }
    let rounded = scaled.rounded()
    if rounded <= 0 { return 0 }
    if rounded >= Double(max) { return max }
    return Int(rounded)
}

// MARK: - Binary helpers

private func readUInt32BE(_ bytes: [UInt8], at offset: Int) -> UInt32 {
    guard offset + 3 < bytes.count else { return 0 }
    return (UInt32(bytes[offset]) << 24) |
           (UInt32(bytes[offset+1]) << 16) |
           (UInt32(bytes[offset+2]) << 8)  |
            UInt32(bytes[offset+3])
}
