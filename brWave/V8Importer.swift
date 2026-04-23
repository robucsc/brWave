//
//  V8Importer.swift
//  brWave
//
//  Imports PPG Wave V8.x SysEx bank files (.syx) into CoreData.
//
//  V8 FORMAT (factory23.syx, factory22_vm.syx, etc.):
//    F0  29 01 0D  [100 patches × 102 nibble-bytes]  F7
//    Total: 1 + 3 + 10200 + 1 = 10205 bytes
//
//  NIBBLE DECODING:
//    Each patch = 102 raw bytes, all values 0–15 (nibbles).
//    Decode: decoded[j] = (raw[2j] << 4) | raw[2j+1]  →  51 decoded bytes per patch.
//
//  V8 → BEHRINGER MAPPING (see docs/FXB_ANALYSIS.md, Sessions 4+5):
//    The V8 hardware used a DIFFERENT byte order than the Behringer Group A layout.
//    Only a subset of positions are confirmed via Pearson correlation against
//    matched FXB ↔ Behringer factory patches. Unconfirmed positions default to 0.
//
//  GROUP A/B:
//    The original PPG Wave 2.3 had ONE sound per preset (no A/B dual-group).
//    Each V8 patch block encodes Group A only. Group B is set equal to Group A on import.
//    The user can override Group B parameters in the patch editor after import.
//
//  SCALE RULES (from Session 5 regression):
//    V8 params are stored at full 8-bit range (0–254 typical).
//    - Behringer 0–127 range params: Beh = clamp(V8 / 2, 0, 127)
//    - Behringer 0–63  range params: Beh = clamp(V8 / 4, 0, 63)
//    - Behringer 0–7   range params: Beh = clamp(V8 / 32, 0, 7)
//    - Behringer 0–9   range params: Beh = clamp(V8 * 9 / 254, 0, 9)
//    - Behringer discrete/toggle: map from nibble range as noted per position.
//

import Foundation
import CoreData

// MARK: - Public entry point

enum V8Importer {

    /// Import V8 .syx bank files.
    @MainActor
    static func importV8(urls: [URL], into context: NSManagedObjectContext) {
        var totalImported = 0

        for url in urls {
            guard let data = try? Data(contentsOf: url) else { continue }
            let bytes = [UInt8](data)

            guard let patches = parseV8Bank(bytes) else {
                print("[V8Importer] \(url.lastPathComponent): unrecognised format — skipped")
                continue
            }

            let libraryName = url.deletingPathExtension().lastPathComponent
            let sourceFileName = url.lastPathComponent
            let patchSet = PatchSet.findOrCreate(named: libraryName, in: context)
            patchSet.modifiedAt = Date()

            for (n, v8) in patches.enumerated() {
                let patchName = importName(v8BaseName(patchNumber: n), sourceMarker: "8")
                let payload = buildPayload(v8: v8, patchName: patchName)

                let patch = Patch(context: context)
                patch.uuid            = UUID()
                patch.dateCreated     = Date()
                patch.dateModified    = Date()
                patch.name            = patchName
                patch.designer        = importDesigner(
                    source: "PPG Wave V8x",
                    fileName: sourceFileName,
                    extra: "nibble SysEx import"
                )
                patch.bank            = -1
                patch.program         = Int16(n)
                patch.rawSysexPayload = Data(payload)
                patch.patchValues     = valuesFromPayload(payload)
                patch.category        = PatchCategory.classify(patchName: patchName).rawValue

                PatchSlot.make(position: n, patch: patch, in: patchSet, ctx: context)
                totalImported += 1
            }
        }

        if totalImported > 0 {
            try? context.save()
        }
    }

    @MainActor
    static func importMessages(_ messages: [[UInt8]],
                               libraryName: String,
                               sourceFileName: String,
                               into context: NSManagedObjectContext) {
        let patchSet = PatchSet.findOrCreate(named: libraryName, in: context)
        patchSet.modifiedAt = Date()

        var totalImported = 0

        for message in messages {
            guard let patches = parseV8Bank(message) else { continue }

            for (n, v8) in patches.enumerated() {
                let patchName = importName(v8BaseName(patchNumber: totalImported + n), sourceMarker: "8")
                let payload = buildPayload(v8: v8, patchName: patchName)

                let patch = Patch(context: context)
                patch.uuid            = UUID()
                patch.dateCreated     = Date()
                patch.dateModified    = Date()
                patch.name            = patchName
                patch.designer        = importDesigner(
                    source: "PPG Wave V8x",
                    fileName: sourceFileName,
                    extra: "MIDI SysEx import"
                )
                patch.bank            = -1
                patch.program         = Int16(totalImported + n)
                patch.rawSysexPayload = Data(payload)
                patch.patchValues     = valuesFromPayload(payload)
                patch.category        = PatchCategory.classify(patchName: patchName).rawValue

                PatchSlot.make(position: totalImported + n, patch: patch, in: patchSet, ctx: context)
            }

            totalImported += patches.count
        }

        if totalImported > 0 {
            try? context.save()
        }
    }
}

// MARK: - V8 Parser

/// Returns array of 51-byte decoded patches from a V8 SysEx bank, or nil if format wrong.
private func parseV8Bank(_ bytes: [UInt8]) -> [[UInt8]]? {
    // Minimum size: F0 + 3-byte header + 1 patch (102 bytes) + F7 = 107
    guard bytes.count >= 107 else { return nil }
    guard bytes[0] == 0xF0 && bytes.last == 0xF7 else { return nil }

    // Header bytes 1–3: manufacturer 29 01 0D
    guard bytes[1] == 0x29 && bytes[2] == 0x01 && bytes[3] == 0x0D else { return nil }

    let body = bytes.dropFirst(4).dropLast(1)   // strip F0+header and F7
    let patchCount = body.count / 102
    guard patchCount >= 1 else { return nil }

    var patches = [[UInt8]]()
    for i in 0..<patchCount {
        let raw = Array(body[(i * 102)..<(i * 102 + 102)])
        let decoded = decodeNibblePatch(raw)
        patches.append(decoded)
    }
    return patches
}

/// High-nibble-first decode: 102 nibble bytes → 51 decoded bytes.
private func decodeNibblePatch(_ raw: [UInt8]) -> [UInt8] {
    precondition(raw.count == 102)
    return (0..<51).map { j in (raw[2 * j] << 4) | raw[2 * j + 1] }
}

// MARK: - Payload Builder

/// Build a 121-byte Behringer Wave SysEx preset payload from 51 decoded V8 bytes.
private func buildPayload(v8: [UInt8], patchName: String) -> [UInt8] {
    var payload = [UInt8](repeating: 0, count: 121)

    // Bytes 0–15: Name — V8 factory patches have no stored names; generate one.
    let nameBytes = Array(patchName.utf8.prefix(16))
    for i in 0..<min(nameBytes.count, 16) {
        let c = nameBytes[i]
        payload[i] = (c >= 32 && c <= 126) ? c : 0x20
    }
    for i in nameBytes.count..<16 { payload[i] = 0x20 }

    // Byte 16: WAVETB (shared) — V8[0], confirmed (value range 0–109 in factory)
    //   V8 factory wavetables 0–31 map directly to Behringer 0–31.
    //   Values above 31 (up to 109) map to user WT range — scale ×1 up to 127.
    payload[16] = UInt8(clamping: Int(v8[0]))

    // Byte 17: SPLIT — not stored in V8 hardware format; default 0.
    payload[17] = 0

    // Byte 18: KEYB MODE — V8[1] encoding unclear; default Poly (0).
    //   V8[1] values: mostly 0 or 128 in factory set. 128 may map to Dual mode (2).
    payload[18] = v8[1] >= 128 ? 2 : 0

    // Bytes 19–69: Group A
    let groupA = buildGroupBytes(v8: v8)
    for i in 0..<51 { payload[19 + i] = groupA[i] }

    // Bytes 70–120: Group B = copy of Group A (no dual-group in V8)
    for i in 0..<51 { payload[70 + i] = groupA[i] }

    return payload
}

// MARK: - Group Builder

/// Map 51 decoded V8 bytes to the 51-byte Behringer Group A layout.
/// Confirmed positions from Pearson correlation (factory23.syx ↔ Hardware Unit FXB, N=64).
/// All unconfirmed positions default to 0 (the Behringer hardware default).
private func buildGroupBytes(v8: [UInt8]) -> [UInt8] {
    var b = [UInt8](repeating: 0, count: 51)

    // --- CONFIRMED positions (r ≥ 0.9) ---

    // A+20  VCF_CUT   (0–63): V8[3] — r=1.000 ✓  scale: ÷4
    b[20] = scaleDiv4(v8[3], max: 63)

    // A+17  ENV1_DEC  (0–63): V8[7] — r=1.000 ✓  scale: ÷4
    b[17] = scaleDiv4(v8[7], max: 63)

    // A+29  ENV2_SUS  (0–63): V8[9] — r=0.936 ✓  scale: ÷4
    b[29] = scaleDiv4(v8[9], max: 63)

    // A+13  LFO_DELAY (0–63): V8[11] — r=0.917 ✓  scale: ÷4
    b[13] = scaleDiv4(v8[11], max: 63)

    // A+22  WAVES_OSC (0–63): V8[2] — r=0.902 ✓  scale: ÷4
    b[22] = scaleDiv4(v8[2], max: 63)

    // A+39  KL        (0–7):  V8[17] — r=0.991 ✓  scale: ÷32
    b[39] = UInt8(clamping: Int(v8[17]) / 32)

    // A+5–12 SEMIT V1–V8 (0–63): V8[21] — r=1.000 ✓
    //   V8 factory stores a single semitone offset applied uniformly to all voices.
    //   scale: ÷2
    let semit = UInt8(clamping: Int(v8[21]) / 2)
    for v in 0..<8 { b[5 + v] = semit }

    // --- MODERATE CONFIDENCE positions (0.65 ≤ r < 0.9) ---

    // A+23  WAVES_SUB (0–63): V8[14] — r=0.796
    b[23] = scaleDiv4(v8[14], max: 63)

    // A+35  UW        (0–2):  V8[15] — r=0.786
    //   V8[15] values: 0 or small ints in factory. Map top bit to UW on/off.
    b[35] = (Int(v8[15]) > 63) ? 2 : 0

    // A+48  TM        (0–1):  V8[16] — r=0.885 (discrete toggle)
    b[48] = (Int(v8[16]) > 7) ? 1 : 0

    // --- DEFAULTS for all other Behringer Group A offsets ---
    // A+0   DETU (0–9): 0
    // A+1   MO (0–1): 0
    // A+2   MS (0–1): 0
    // A+3   EO (0–9): 0
    // A+4   ES (0–1): 0
    // A+14  WAVESHAPE (0–127): 0 = Tri (default PPG LFO shape)
    // A+15  LFO_RATE (0–63): 0
    // A+16  ENV1_ATK (0–63): 0
    // A+18  ENV1_SUS (0–63): 63 (default sustain = max)
    b[18] = 63
    // A+19  ENV1_REL (0–63): 0
    // A+21  VCF_EMP (0–63): 0
    // A+24  ENV3_ATK (0–63): 0
    // A+25  ENV3_DEC (0–63): 0
    // A+26  ENV3_ATT (0–63): 0
    // A+27  ENV2_ATK (0–63): 0
    // A+28  ENV2_DEC (0–63): 0
    // A+30  ENV2_REL (0–63): 0
    // A+31  MOD_WHL (0–127): 0
    // A+32  ENV1_VCF (0–63): 0
    // A+33  ENV2_VCA (0–63): 63 (default full loudness env)
    b[33] = 63
    // A+34  ENV1_WAVES (0–63): 0
    // A+36  SW (0–6): 0
    // A+37  KW (0–7): 0
    // A+38  KF (0–7): 0
    // A+40  MW (0–9): 0
    // A+41  MF (0–9): 0
    // A+42  ML (0–1): 0
    // A+43  BD (0–7): 2 = Pitch (standard pitch-bend destination)
    b[43] = 2
    // A+44  BI (0–5): 2 = ±2 semitones (common default)
    b[44] = 2
    // A+45  TW (0–2): 0
    // A+46  TF (0–2): 0
    // A+47  TL (0–2): 0
    // A+49  VF (0–3): 0
    // A+50  VL (0–3): 0

    return b
}

// MARK: - Scale helpers

/// Scale a V8 nibble-decoded byte (0–255) to 0…max range by dividing by 4.
private func scaleDiv4(_ v8: UInt8, max: Int) -> UInt8 {
    UInt8(clamping: min(Int(v8) / 4, max))
}

/// Scale a V8 byte to 0…max range by dividing by 2.
private func scaleDiv2(_ v8: UInt8, max: Int) -> UInt8 {
    UInt8(clamping: min(Int(v8) / 2, max))
}

// MARK: - Naming

private func v8BaseName(patchNumber: Int) -> String {
    "PPG \(String(format: "%03d", patchNumber + 1))"
}

// MARK: - Value store builder

private func valuesFromPayload(_ payload: [UInt8]) -> WavePatchValues {
    var pv = WavePatchValues()
    let aBase = WaveParameters.groupABase   // 19
    let bBase = WaveParameters.groupBBase   // 70

    pv.setValue(Int(payload[16]), for: .wavetb, group: .a)
    pv.setValue(Int(payload[17]), for: .split,  group: .a)
    pv.setValue(Int(payload[18]), for: .keyb,   group: .a)

    for desc in WaveParameters.all {
        guard case .perGroup(let offset) = desc.storage else { continue }
        pv.setValue(Int(payload[aBase + offset]), for: desc.id, group: .a)
        pv.setValue(Int(payload[bBase + offset]), for: desc.id, group: .b)
    }

    return pv
}
