//
//  MicrowaveImporter.swift
//  brWave
//
//  Imports Waldorf MicroWave SysEx sounds into CoreData.
//
//  Supported in v1:
//  - BPRD single sound dump  (IDM 0x42)
//  - BPBD sound bank dump    (IDM 0x50)
//
//  Partially supported in v1:
//  - CRTD cartridge dump     (IDM 0x54)
//    Imports the leading contiguous sound records and ignores non-sound cartridge data.
//

import Foundation
import CoreData

enum MicrowaveImporter {

    @MainActor
    static func importSyx(urls: [URL], into context: NSManagedObjectContext) {
        var totalImported = 0

        for url in urls {
            guard let data = try? Data(contentsOf: url) else { continue }
            let bytes = [UInt8](data)

            guard let payloads = parseMicrowaveSYX(bytes) else {
                print("[MicrowaveImporter] \(url.lastPathComponent): unsupported or invalid MicroWave SysEx")
                continue
            }

            let libraryName = url.deletingPathExtension().lastPathComponent
            let patchSet = PatchSet.findOrCreate(named: libraryName, in: context)
            patchSet.modifiedAt = Date()

            for (index, mw) in payloads.enumerated() {
                let conversion = buildPayload(from: mw, patchNumber: index)

                let patch = Patch(context: context)
                patch.uuid            = UUID()
                patch.dateCreated     = Date()
                patch.dateModified    = Date()
                patch.name            = conversion.name
                patch.designer        = importDesigner(
                    source: "µWave",
                    fileName: url.lastPathComponent,
                    extra: microwaveImportExtra(for: bytes, patchCount: payloads.count)
                )
                patch.bank            = -1
                patch.program         = Int16(index)
                patch.rawSysexPayload = Data(conversion.payload)
                patch.patchValues     = microwaveValuesFromPayload(conversion.payload)
                patch.category        = PatchCategory.classify(patchName: conversion.name).rawValue

                PatchSlot.make(position: index, patch: patch, in: patchSet, ctx: context)
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
        var sounds: [MicrowaveSound] = []

        for message in messages {
            guard let payloads = parseMicrowaveSYX(message) else { continue }
            sounds.append(contentsOf: payloads)
        }

        guard !sounds.isEmpty else {
            print("[MicrowaveImporter] \(sourceFileName): unsupported or invalid MicroWave MIDI SysEx")
            return
        }

        let patchSet = PatchSet.findOrCreate(named: libraryName, in: context)
        patchSet.modifiedAt = Date()

        for (index, mw) in sounds.enumerated() {
            let conversion = buildPayload(from: mw, patchNumber: index)

            let patch = Patch(context: context)
            patch.uuid            = UUID()
            patch.dateCreated     = Date()
            patch.dateModified    = Date()
            patch.name            = conversion.name
            patch.designer        = importDesigner(
                source: "µWave",
                fileName: sourceFileName,
                extra: "MIDI SysEx import"
            )
            patch.bank            = -1
            patch.program         = Int16(index)
            patch.rawSysexPayload = Data(conversion.payload)
            patch.patchValues     = microwaveValuesFromPayload(conversion.payload)
            patch.category        = PatchCategory.classify(patchName: conversion.name).rawValue

            PatchSlot.make(position: index, patch: patch, in: patchSet, ctx: context)
        }

        try? context.save()
    }
}

private struct MicrowaveSound {
    let data: [UInt8]    // 180 bytes, bytes 5...184 from BPRD spec
}

private struct MicrowaveConversion {
    let name: String
    let payload: [UInt8]
}

private enum MW {
    static let manufacturer: UInt8 = 0x3E
    static let equipment: UInt8 = 0x00

    static let idmBPRD: UInt8 = 0x42
    static let idmBPBD: UInt8 = 0x50
    static let idmCRTD: UInt8 = 0x54
    static let cartridgeSoundCount = 64

    static let soundDataLength = 180
    static let validFlagIndex = 179

    static let osc1Octave = 0
    static let osc1Semitone = 1
    static let osc1Detune = 2
    static let osc1BendRange = 3

    static let osc2Octave = 11
    static let osc2Semitone = 12
    static let osc2Detune = 13
    static let osc2BendRange = 14

    static let wavetable = 23
    static let wave1Position = 24
    static let wave1EnvelopeAmount = 26
    static let wave1Keytrack = 28

    static let wave2Position = 36
    static let wave2EnvelopeAmount = 38
    static let wave2Keytrack = 40

    static let volumeEnvelopeAmount = 52
    static let volumeKeytrack = 54
    static let cutoff = 60
    static let resonance = 61
    static let cutoffEnvelopeAmount = 62
    static let cutoffKeytrack = 64

    static let volEnvAttack = 72
    static let volEnvDecay = 73
    static let volEnvSustain = 74
    static let volEnvRelease = 75

    static let filterEnvDelay = 85
    static let filterEnvAttack = 86
    static let filterEnvDecay = 87
    static let filterEnvSustain = 88
    static let filterEnvRelease = 89

    static let waveEnvTime1 = 101
    static let waveEnvLevel1 = 102
    static let waveEnvTime2 = 103
    static let waveEnvLevel2 = 104

    static let lfo1Rate = 124
    static let lfo1Shape = 125
    static let lfo1Delay = 132

    static let lfo2Rate = 135
    static let lfo2Shape = 136

    static let soundNameStart = 148
    static let soundNameLength = 16
}

private func parseMicrowaveSYX(_ bytes: [UInt8]) -> [MicrowaveSound]? {
    guard bytes.count >= 8,
          bytes.first == 0xF0,
          bytes.last == 0xF7,
          bytes[1] == MW.manufacturer,
          bytes[2] == MW.equipment else {
        return nil
    }

    let idm = bytes[4]

    switch idm {
    case MW.idmBPRD:
        guard bytes.count >= 187 else { return nil }
        let sound = Array(bytes[5..<185])
        guard sound.count == MW.soundDataLength else { return nil }
        guard sound[MW.validFlagIndex] == 0x55 else { return nil }
        let checksum = UInt8(sound.reduce(0, { ($0 + Int($1)) & 0xFF }) & 0x7F)
        guard checksum == bytes[185] else { return nil }
        return [MicrowaveSound(data: sound)]

    case MW.idmBPBD:
        let body = Array(bytes[5..<(bytes.count - 2)])
        guard !body.isEmpty, body.count % MW.soundDataLength == 0 else { return nil }

        var sounds: [MicrowaveSound] = []
        let count = body.count / MW.soundDataLength
        for i in 0..<count {
            let start = i * MW.soundDataLength
            let chunk = Array(body[start..<(start + MW.soundDataLength)])
            guard chunk[MW.validFlagIndex] == 0x55 else { continue }
            sounds.append(MicrowaveSound(data: chunk))
        }
        return sounds.isEmpty ? nil : sounds

    case MW.idmCRTD:
        let body = Array(bytes[5..<(bytes.count - 2)])
        guard body.count >= MW.soundDataLength else { return nil }

        var sounds: [MicrowaveSound] = []
        let chunkCount = body.count / MW.soundDataLength
        for i in 0..<chunkCount {
            let start = i * MW.soundDataLength
            let chunk = Array(body[start..<(start + MW.soundDataLength)])

            if chunk[MW.validFlagIndex] == 0x55 {
                sounds.append(MicrowaveSound(data: chunk))
                if sounds.count == MW.cartridgeSoundCount { break }
            } else if !sounds.isEmpty {
                break
            }
        }
        return sounds.isEmpty ? nil : sounds

    default:
        return nil
    }
}

private func microwaveImportExtra(for bytes: [UInt8], patchCount: Int) -> String {
    guard bytes.count >= 5 else { return patchCount == 1 ? "BPRD import" : "MicroWave import" }

    switch bytes[4] {
    case MW.idmBPRD:
        return "BPRD import"
    case MW.idmBPBD:
        return "BPBD import"
    case MW.idmCRTD:
        return patchCount == MW.cartridgeSoundCount ? "CRTD sound import" : "CRTD partial import"
    default:
        return "MicroWave import"
    }
}

private func buildPayload(from sound: MicrowaveSound, patchNumber: Int) -> MicrowaveConversion {
    var payload = [UInt8](repeating: 0, count: WaveParameters.presetPayloadLength)

    let sourceName = microwaveSourceName(sound.data)
    let lfoSelection = chooseLFO(sound.data)
    let delayFolded = sound.data[MW.filterEnvDelay] > 8
    let hasActiveMatrix = microwaveHasDroppedModulation(sound.data)
    let degraded = delayFolded || lfoSelection.promotedLFO2 || hasActiveMatrix

    let fallbackName = "MW \(String(format: "%03d", patchNumber + 1))"
    let patchName = importName(sourceName, sourceMarker: "u", degraded: degraded, fallback: fallbackName)
    let nameBytes = Array(patchName.utf8.prefix(16))
    for i in 0..<16 {
        payload[i] = i < nameBytes.count ? nameBytes[i] : 0x20
    }

    payload[16] = UInt8(clamping: Int(sound.data[MW.wavetable]))
    payload[17] = 0
    payload[18] = 0

    var group = [UInt8](repeating: 0, count: 51)

    let osc1Semis = microwaveSemitone(octave: sound.data[MW.osc1Octave], semi: sound.data[MW.osc1Semitone])
    let osc2Semis = microwaveSemitone(octave: sound.data[MW.osc2Octave], semi: sound.data[MW.osc2Semitone])
    let relSemis = max(-24, min(24, osc2Semis - osc1Semis))

    group[0] = microwaveDetune(sound.data[MW.osc2Detune], relativeSemis: relSemis)
    for offset in 5...12 { group[offset] = UInt8(clamping: max(0, min(63, osc1Semis + 24))) }

    group[13] = scale63(sound.data[lfoSelection.delayIndex])
    group[14] = microwaveLFOShape(sound.data[lfoSelection.shapeIndex])
    group[15] = scale63(sound.data[lfoSelection.rateIndex])

    group[16] = scale63(attackWithDelay(baseAttack: sound.data[MW.filterEnvAttack],
                                        delay: sound.data[MW.filterEnvDelay]))
    group[17] = scale63(sound.data[MW.filterEnvDecay])
    group[18] = scale63(sound.data[MW.filterEnvSustain])
    group[19] = scale63(sound.data[MW.filterEnvRelease])

    group[20] = scale63(sound.data[MW.cutoff])
    group[21] = scale63(sound.data[MW.resonance])
    group[22] = UInt8(clamping: min(Int(sound.data[MW.wave1Position]), 63))
    group[23] = UInt8(clamping: min(Int(sound.data[MW.wave2Position]), 63))

    group[24] = scale63(sound.data[MW.waveEnvTime1])
    group[25] = scale63(sound.data[MW.waveEnvTime2])
    group[26] = bipolarToPositive(sound.data[MW.waveEnvLevel1], max: 63)

    group[27] = scale63(sound.data[MW.volEnvAttack])
    group[28] = scale63(sound.data[MW.volEnvDecay])
    group[29] = scale63(sound.data[MW.volEnvSustain])
    group[30] = scale63(sound.data[MW.volEnvRelease])

    group[32] = bipolarToPositive(sound.data[MW.cutoffEnvelopeAmount], max: 63)
    group[33] = max(32, bipolarToPositive(sound.data[MW.volumeEnvelopeAmount], max: 63))
    group[34] = bipolarToPositive(max(sound.data[MW.wave1EnvelopeAmount], sound.data[MW.wave2EnvelopeAmount]), max: 63)

    group[37] = bipolarToPositive(max(sound.data[MW.wave1Keytrack], sound.data[MW.wave2Keytrack]), max: 7)
    group[38] = bipolarToPositive(sound.data[MW.cutoffKeytrack], max: 7)
    group[39] = bipolarToPositive(sound.data[MW.volumeKeytrack], max: 7)

    group[43] = 2
    group[44] = UInt8(clamping: min(Int(sound.data[MW.osc1BendRange]), 5))

    let velocityActivity = max(
        abs(Int(sound.data[27]) - 64),
        abs(Int(sound.data[39]) - 64),
        abs(Int(sound.data[53]) - 64),
        abs(Int(sound.data[63]) - 64)
    )
    if velocityActivity > 12 {
        group[49] = 1
        group[50] = 1
    }

    for i in 0..<51 {
        payload[WaveParameters.groupABase + i] = group[i]
        payload[WaveParameters.groupBBase + i] = group[i]
    }

    return MicrowaveConversion(name: patchName, payload: payload)
}

private func microwaveSourceName(_ data: [UInt8]) -> String {
    let raw = Array(data[MW.soundNameStart..<(MW.soundNameStart + MW.soundNameLength)])
    let ascii = String(bytes: raw.prefix(while: { $0 != 0 && $0 >= 32 && $0 <= 126 }), encoding: .ascii) ?? ""
    let trimmed = ascii.trimmingCharacters(in: .whitespaces)
    let placeholders = ["PG wave 2.3", "PPG wave 2.3", "wave 2.3"]
    if trimmed.isEmpty || placeholders.contains(where: { trimmed.caseInsensitiveCompare($0) == .orderedSame }) {
        return ""
    }
    return trimmed
}

private struct MWLFOSelection {
    let rateIndex: Int
    let shapeIndex: Int
    let delayIndex: Int
    let promotedLFO2: Bool
}

private func chooseLFO(_ data: [UInt8]) -> MWLFOSelection {
    let lfo1Rate = Int(data[MW.lfo1Rate])
    let lfo1Delay = Int(data[MW.lfo1Delay])
    let lfo2Rate = Int(data[MW.lfo2Rate])

    let promoteLFO2 = lfo1Rate < 8 && lfo1Delay > 96 && lfo2Rate > 12
    if promoteLFO2 {
        return MWLFOSelection(
            rateIndex: MW.lfo2Rate,
            shapeIndex: MW.lfo2Shape,
            delayIndex: MW.lfo1Delay,
            promotedLFO2: true
        )
    }

    return MWLFOSelection(
        rateIndex: MW.lfo1Rate,
        shapeIndex: MW.lfo1Shape,
        delayIndex: MW.lfo1Delay,
        promotedLFO2: false
    )
}

private func microwaveHasDroppedModulation(_ data: [UInt8]) -> Bool {
    let modifierSourceIndexes = [
        5, 6, 8, 16, 17, 19, 29, 30, 32, 41, 42, 44, 55, 56, 58, 65, 66, 68, 70,
        76, 78, 80, 82, 84, 86, 90, 92, 94, 96, 98, 119, 121, 130, 132, 134, 142
    ]
    return modifierSourceIndexes.contains { $0 < data.count && data[$0] != 0 }
}

private func microwaveSemitone(octave: UInt8, semi: UInt8) -> Int {
    let octaveMap: [Int: Int] = [0x00: -24, 0x10: -12, 0x20: 0, 0x30: 12, 0x40: 24]
    let oct = octaveMap[Int(octave)] ?? 0
    let semis = Int(semi) / 8
    return oct + semis
}

private func microwaveDetune(_ detune: UInt8, relativeSemis: Int) -> UInt8 {
    let fine = abs(Int(detune) - 64)
    let coarseWeight = min(abs(relativeSemis), 12) * 3
    return UInt8(clamping: min(9, (fine / 8 + coarseWeight / 8)))
}

private func attackWithDelay(baseAttack: UInt8, delay: UInt8) -> UInt8 {
    let folded = Int(baseAttack) + Int(delay) / 3
    return UInt8(clamping: min(127, folded))
}

private func scale63(_ value: UInt8) -> UInt8 {
    UInt8(clamping: min(Int(value) / 2, 63))
}

private func bipolarToPositive(_ value: UInt8, max: Int) -> UInt8 {
    let signed = Int(value) - 64
    if signed <= 0 { return 0 }
    return UInt8(clamping: min(max, Int(Double(signed) / 63.0 * Double(max) + 0.5)))
}

private func microwaveLFOShape(_ shape: UInt8) -> UInt8 {
    switch shape {
    case 0: return 0
    case 1: return 32
    case 2: return 64
    case 3, 4: return 96
    default: return 0
    }
}

private func microwaveValuesFromPayload(_ payload: [UInt8]) -> WavePatchValues {
    var pv = WavePatchValues()
    let aBase = WaveParameters.groupABase
    let bBase = WaveParameters.groupBBase

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
