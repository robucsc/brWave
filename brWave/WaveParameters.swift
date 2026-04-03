//
//  WaveParameters.swift
//  brWave
//
//  Behringer Wave / PPG Wave parameter definitions.
//  Single source of truth for NRPN numbers, SysEx byte offsets, ranges, and display names.
//
//  Key facts:
//  - NRPN format: Bn 63 00, Bn 62 ParNum (0–46), Bn 06 Value (0–127) — 3 messages
//  - SysEx preset: 121 bytes (D0–D120). Name 0–15, shared 16–18, Group A 19–69, Group B 70–120
//  - NRPN numbers do NOT match SysEx byte offsets
//  - Per-group params use the same NRPN regardless of which group is active
//

import Foundation

// MARK: - Parameter ID

enum WaveParamID: String, CaseIterable, Codable {

    // Shared per-patch (SysEx bytes 16–18)
    case wavetb = "WAVETB"          // Wavetable select
    case split  = "SPLIT"           // Split point
    case keyb   = "KEYB"            // Keyboard mode

    // Per-group: LFO (Analog section)
    case delay     = "DELAY"        // LFO Delay
    case waveshape = "WAVESHAPE"    // LFO Shape
    case rate      = "RATE"         // LFO Rate

    // Per-group: Envelope 1 (Waveshape)
    case a1 = "A1"
    case d1 = "D1"
    case s1 = "S1"
    case r1 = "R1"

    // Per-group: Filter
    case vcfCutoff   = "VCF_CUTOFF"
    case vcfEmphasis = "VCF_EMPHASIS"

    // Per-group: Wave tab positions
    case wavesOsc = "WAVES_OSC"     // Main Osc Wave Tab Position
    case wavesSub = "WAVES_SUB"     // Sub Osc Wave Tab Position

    // Per-group: Envelope 3 (Pitch)
    case attack3 = "ATTACK3"
    case decay3  = "DECAY3"
    case env3Att = "ENV3_ATT"       // Env 3 Amount

    // Per-group: Envelope 2 (Loudness)
    case a2 = "A2"
    case d2 = "D2"
    case s2 = "S2"
    case r2 = "R2"

    // Per-group: Analog modulation amounts
    case modWhl      = "MOD_WHL"        // Mod Wheel Position
    case env1VCF     = "ENV1_VCF"       // Env 1 -> VCF Frequency Mod
    case env2Loud    = "ENV2_LOUDNESS"  // Env 2 -> Loudness (Preset Volume)
    case env1Waves   = "ENV1_WAVES"     // Env 1 -> Wave Pos Mod

    // Per-group: Digital — oscillator config
    case uw = "UW"                  // Upper WT Select
    case sw = "SW"                  // Sub Osc Mode

    // Per-group: Digital — Key tracking
    case kw = "KW"                  // Key -> Wave Mod
    case kf = "KF"                  // Key -> Filter Mod
    case kl = "KL"                  // Key -> Loudness Mod

    // Per-group: Digital — Mod Wheel routing
    case mw = "MW"                  // Mod Wheel -> Wave Mod
    case mf = "MF"                  // Mod Wheel -> Filter Mod
    case ml = "ML"                  // Mod Wheel -> Loudness Mod

    // Per-group: Digital — Bender
    case bd = "BD"                  // Bender Destination
    case bi = "BI"                  // Bender Interval

    // Per-group: Digital — Touch (Aftertouch)
    case tw = "TW"                  // Touch -> Wave Mod
    case tf = "TF"                  // Touch -> Filter Mod
    case tl = "TL"                  // Touch -> Loudness Mode
    case tm = "TM"                  // Touch -> Mod Wheel

    // Per-group: Digital — Velocity
    case vf = "VF"                  // Velocity -> Filter Mod
    case vl = "VL"                  // Velocity -> Loudness Mod

    // Per-group: Tuning
    case detu   = "DETU"            // Sub Osc Detuning
    case mo     = "MO"              // Mod -> Main Osc Pitch
    case ms     = "MS"              // Mod -> Sub Osc Pitch
    case eo     = "EO"              // Env3 -> Main Osc Pitch
    case es     = "ES"              // Env3 -> Main Sub Pitch
    case semitV1 = "SEMIT_V1"
    case semitV2 = "SEMIT_V2"
    case semitV3 = "SEMIT_V3"
    case semitV4 = "SEMIT_V4"
    case semitV5 = "SEMIT_V5"
    case semitV6 = "SEMIT_V6"
    case semitV7 = "SEMIT_V7"
    case semitV8 = "SEMIT_V8"

    // Arp/Seq (live NRPN — stored in sequencer data block, not preset bytes)
    case state = "STATE"            // Arp/Seq State (Stop/Play/Rec/Overdub)
    case mod   = "MOD"              // Arp/Seq Mode
    case clk   = "CLK"              // Clock Selection
    case gat   = "GAT"              // Gate Time
    case div   = "DIV"              // Clock Division
    case bpm   = "BPM"              // Tempo

    // Global (live NRPN only — not stored in preset SysEx)
    case dtf      = "DTF"           // Preset Data Recall Mode
    case tune     = "TUNE"          // Master Tuning (400–499 Hz)
    case expPedal = "EXP_PEDAL"     // Expression Pedal Function
    case touch    = "TOUCH"         // Channel Aftertouch Mode
    case brt      = "BRT"           // LCD Brightness
    case cnt      = "CNT"           // LCD Contrast
    case firm     = "FIRM"          // Firmware Enhancement Mode (0=original,1=linear,2=exp)
    case osc      = "OSC"           // Oscillator Mode
    case lfo      = "LFO"           // LFO Mode
}

// MARK: - Parameter Group (panel section)

enum WaveParamGroup: String {
    case waves       = "Waves"
    case lfo         = "LFO"
    case env1        = "Env 1"
    case filter      = "Filter"
    case env3        = "Env 3"
    case env2        = "Env 2"
    case modulation  = "Modulation"
    case digital     = "Digital"
    case tuning      = "Tuning"
    case arpSeq      = "Arp / Seq"
    case global      = "Global"
    case program     = "Program"
}

// MARK: - Storage location in SysEx preset

enum WaveParamStorage {
    /// Shared per-patch, bytes 16–18 in preset
    case shared(sysexByte: Int)
    /// Per-group: `sysexGroupOffset` is the byte offset within a group block (0–50).
    /// Group A byte = 19 + offset. Group B byte = 70 + offset.
    case perGroup(sysexGroupOffset: Int)
    /// In sequencer data block (577 bytes), not preset bytes
    case sequencer
    /// Global hardware setting, not stored in preset SysEx
    case globalOnly
}

// MARK: - Descriptor

struct WaveParamDescriptor: Identifiable {
    let id: WaveParamID
    let nrpn: Int?                  // nil = no dedicated NRPN (or future use)
    let range: ClosedRange<Int>
    let displayName: String
    let shortName: String           // for panel labels where space is tight
    let group: WaveParamGroup
    let storage: WaveParamStorage
}

// MARK: - Parameter Table

enum WaveParameters {

    static let groupABase = 19
    static let groupBBase = 70
    static let presetPayloadLength = 121   // bytes D0–D120
    static let sequencerPayloadLength = 577

    static let all: [WaveParamDescriptor] = [

        // MARK: Shared / Program
        .init(id: .wavetb,   nrpn: 0,  range: 0...127, displayName: "Wavetable",      shortName: "WT",     group: .program,  storage: .shared(sysexByte: 16)),
        .init(id: .split,    nrpn: 1,  range: 0...99,  displayName: "Split Point",     shortName: "Split",  group: .program,  storage: .shared(sysexByte: 17)),
        .init(id: .keyb,     nrpn: 2,  range: 0...9,   displayName: "Keyboard Mode",   shortName: "Keyb",   group: .program,  storage: .shared(sysexByte: 18)),

        // MARK: Tuning (per-group offsets 0–12)
        .init(id: .detu,     nrpn: 28, range: 0...9,   displayName: "Sub Osc Detune",  shortName: "Detu",   group: .tuning,   storage: .perGroup(sysexGroupOffset: 0)),
        .init(id: .mo,       nrpn: 29, range: 0...1,   displayName: "Mod→Main Osc",    shortName: "MO",     group: .tuning,   storage: .perGroup(sysexGroupOffset: 1)),
        .init(id: .ms,       nrpn: 30, range: 0...1,   displayName: "Mod→Sub Osc",     shortName: "MS",     group: .tuning,   storage: .perGroup(sysexGroupOffset: 2)),
        .init(id: .eo,       nrpn: 31, range: 0...9,   displayName: "Env3→Main Osc",   shortName: "EO",     group: .tuning,   storage: .perGroup(sysexGroupOffset: 3)),
        .init(id: .es,       nrpn: 32, range: 0...1,   displayName: "Env3→Sub Osc",    shortName: "ES",     group: .tuning,   storage: .perGroup(sysexGroupOffset: 4)),
        .init(id: .semitV1,  nrpn: 33, range: 0...63,  displayName: "Voice 1 Semi",    shortName: "V1",     group: .tuning,   storage: .perGroup(sysexGroupOffset: 5)),
        .init(id: .semitV2,  nrpn: 34, range: 0...63,  displayName: "Voice 2 Semi",    shortName: "V2",     group: .tuning,   storage: .perGroup(sysexGroupOffset: 6)),
        .init(id: .semitV3,  nrpn: 35, range: 0...63,  displayName: "Voice 3 Semi",    shortName: "V3",     group: .tuning,   storage: .perGroup(sysexGroupOffset: 7)),
        .init(id: .semitV4,  nrpn: 36, range: 0...63,  displayName: "Voice 4 Semi",    shortName: "V4",     group: .tuning,   storage: .perGroup(sysexGroupOffset: 8)),
        .init(id: .semitV5,  nrpn: 37, range: 0...63,  displayName: "Voice 5 Semi",    shortName: "V5",     group: .tuning,   storage: .perGroup(sysexGroupOffset: 9)),
        .init(id: .semitV6,  nrpn: 38, range: 0...63,  displayName: "Voice 6 Semi",    shortName: "V6",     group: .tuning,   storage: .perGroup(sysexGroupOffset: 10)),
        .init(id: .semitV7,  nrpn: 39, range: 0...63,  displayName: "Voice 7 Semi",    shortName: "V7",     group: .tuning,   storage: .perGroup(sysexGroupOffset: 11)),
        .init(id: .semitV8,  nrpn: 40, range: 0...63,  displayName: "Voice 8 Semi",    shortName: "V8",     group: .tuning,   storage: .perGroup(sysexGroupOffset: 12)),

        // MARK: LFO / Analog (per-group offsets 13–15)
        .init(id: .delay,     nrpn: nil, range: 0...127, displayName: "LFO Delay",      shortName: "Delay",  group: .lfo,      storage: .perGroup(sysexGroupOffset: 13)),
        .init(id: .waveshape, nrpn: nil, range: 0...127, displayName: "LFO Shape",      shortName: "Shape",  group: .lfo,      storage: .perGroup(sysexGroupOffset: 14)),
        .init(id: .rate,      nrpn: nil, range: 0...127, displayName: "LFO Rate",       shortName: "Rate",   group: .lfo,      storage: .perGroup(sysexGroupOffset: 15)),

        // MARK: Envelope 1 — Waveshape (per-group offsets 16–19)
        .init(id: .a1, nrpn: nil, range: 0...127, displayName: "Env 1 Attack",  shortName: "Att", group: .env1, storage: .perGroup(sysexGroupOffset: 16)),
        .init(id: .d1, nrpn: nil, range: 0...127, displayName: "Env 1 Decay",   shortName: "Dec", group: .env1, storage: .perGroup(sysexGroupOffset: 17)),
        .init(id: .s1, nrpn: nil, range: 0...127, displayName: "Env 1 Sustain", shortName: "Sus", group: .env1, storage: .perGroup(sysexGroupOffset: 18)),
        .init(id: .r1, nrpn: nil, range: 0...127, displayName: "Env 1 Release", shortName: "Rel", group: .env1, storage: .perGroup(sysexGroupOffset: 19)),

        // MARK: Filter (per-group offsets 20–21)
        .init(id: .vcfCutoff,   nrpn: nil, range: 0...127, displayName: "Filter Freq",  shortName: "Freq",  group: .filter, storage: .perGroup(sysexGroupOffset: 20)),
        .init(id: .vcfEmphasis, nrpn: nil, range: 0...127, displayName: "Resonance",    shortName: "Res",   group: .filter, storage: .perGroup(sysexGroupOffset: 21)),

        // MARK: Wave Tab Positions (per-group offsets 22–23)
        .init(id: .wavesOsc, nrpn: nil, range: 0...127, displayName: "Main Osc Wave", shortName: "Osc W", group: .waves, storage: .perGroup(sysexGroupOffset: 22)),
        .init(id: .wavesSub, nrpn: nil, range: 0...127, displayName: "Sub Osc Wave",  shortName: "Sub W", group: .waves, storage: .perGroup(sysexGroupOffset: 23)),

        // MARK: Envelope 3 — Pitch (per-group offsets 24–26)
        .init(id: .attack3, nrpn: nil, range: 0...127, displayName: "Env 3 Attack", shortName: "Att",  group: .env3, storage: .perGroup(sysexGroupOffset: 24)),
        .init(id: .decay3,  nrpn: nil, range: 0...127, displayName: "Env 3 Decay",  shortName: "Dec",  group: .env3, storage: .perGroup(sysexGroupOffset: 25)),
        .init(id: .env3Att, nrpn: nil, range: 0...127, displayName: "Env 3 Amount", shortName: "Amt",  group: .env3, storage: .perGroup(sysexGroupOffset: 26)),

        // MARK: Envelope 2 — Loudness (per-group offsets 27–30)
        .init(id: .a2, nrpn: nil, range: 0...127, displayName: "Env 2 Attack",  shortName: "Att", group: .env2, storage: .perGroup(sysexGroupOffset: 27)),
        .init(id: .d2, nrpn: nil, range: 0...127, displayName: "Env 2 Decay",   shortName: "Dec", group: .env2, storage: .perGroup(sysexGroupOffset: 28)),
        .init(id: .s2, nrpn: nil, range: 0...127, displayName: "Env 2 Sustain", shortName: "Sus", group: .env2, storage: .perGroup(sysexGroupOffset: 29)),
        .init(id: .r2, nrpn: nil, range: 0...127, displayName: "Env 2 Release", shortName: "Rel", group: .env2, storage: .perGroup(sysexGroupOffset: 30)),

        // MARK: Analog Modulation Amounts (per-group offsets 31–34)
        .init(id: .modWhl,    nrpn: nil, range: 0...127, displayName: "Mod Wheel",     shortName: "Mod W",  group: .modulation, storage: .perGroup(sysexGroupOffset: 31)),
        .init(id: .env1VCF,   nrpn: nil, range: 0...127, displayName: "Env 1→Filter",  shortName: "E1→VCF", group: .modulation, storage: .perGroup(sysexGroupOffset: 32)),
        .init(id: .env2Loud,  nrpn: nil, range: 0...127, displayName: "Env 2→Loud",    shortName: "Vol",    group: .modulation, storage: .perGroup(sysexGroupOffset: 33)),
        .init(id: .env1Waves, nrpn: nil, range: 0...127, displayName: "Env 1→Waves",   shortName: "E1→WT",  group: .modulation, storage: .perGroup(sysexGroupOffset: 34)),

        // MARK: Digital — Oscillator Config (per-group offsets 35–36)
        .init(id: .uw, nrpn: 12, range: 0...2, displayName: "Upper WT",    shortName: "UW", group: .digital, storage: .perGroup(sysexGroupOffset: 35)),
        .init(id: .sw, nrpn: 13, range: 0...6, displayName: "Sub Osc Mode",shortName: "SW", group: .digital, storage: .perGroup(sysexGroupOffset: 36)),

        // MARK: Digital — Key Tracking (per-group offsets 37–39)
        .init(id: .kw, nrpn: 14, range: 0...7, displayName: "Key→Wave",    shortName: "KW", group: .digital, storage: .perGroup(sysexGroupOffset: 37)),
        .init(id: .kf, nrpn: 15, range: 0...7, displayName: "Key→Filter",  shortName: "KF", group: .digital, storage: .perGroup(sysexGroupOffset: 38)),
        .init(id: .kl, nrpn: 16, range: 0...7, displayName: "Key→Loud",    shortName: "KL", group: .digital, storage: .perGroup(sysexGroupOffset: 39)),

        // MARK: Digital — Mod Wheel Routing (per-group offsets 40–42)
        .init(id: .mw, nrpn: 17, range: 0...9, displayName: "Mod→Wave",    shortName: "MW", group: .digital, storage: .perGroup(sysexGroupOffset: 40)),
        .init(id: .mf, nrpn: 18, range: 0...9, displayName: "Mod→Filter",  shortName: "MF", group: .digital, storage: .perGroup(sysexGroupOffset: 41)),
        .init(id: .ml, nrpn: 19, range: 0...1, displayName: "Mod→Loud",    shortName: "ML", group: .digital, storage: .perGroup(sysexGroupOffset: 42)),

        // MARK: Digital — Bender (per-group offsets 43–44)
        .init(id: .bd, nrpn: 20, range: 0...7, displayName: "Bender Dest",    shortName: "BD", group: .digital, storage: .perGroup(sysexGroupOffset: 43)),
        .init(id: .bi, nrpn: 21, range: 0...5, displayName: "Bender Interval",shortName: "BI", group: .digital, storage: .perGroup(sysexGroupOffset: 44)),

        // MARK: Digital — Touch / Aftertouch (per-group offsets 45–48)
        .init(id: .tw, nrpn: 22, range: 0...2, displayName: "Touch→Wave",   shortName: "TW", group: .digital, storage: .perGroup(sysexGroupOffset: 45)),
        .init(id: .tf, nrpn: 23, range: 0...2, displayName: "Touch→Filter", shortName: "TF", group: .digital, storage: .perGroup(sysexGroupOffset: 46)),
        .init(id: .tl, nrpn: 24, range: 0...2, displayName: "Touch→Loud",   shortName: "TL", group: .digital, storage: .perGroup(sysexGroupOffset: 47)),
        .init(id: .tm, nrpn: 25, range: 0...1, displayName: "Touch→Mod",    shortName: "TM", group: .digital, storage: .perGroup(sysexGroupOffset: 48)),

        // MARK: Digital — Velocity (per-group offsets 49–50)
        .init(id: .vf, nrpn: 26, range: 0...3, displayName: "Vel→Filter",   shortName: "VF", group: .digital, storage: .perGroup(sysexGroupOffset: 49)),
        .init(id: .vl, nrpn: 27, range: 0...3, displayName: "Vel→Loud",     shortName: "VL", group: .digital, storage: .perGroup(sysexGroupOffset: 50)),

        // MARK: Arp / Seq
        .init(id: .state, nrpn: 41, range: 0...3,   displayName: "State",         shortName: "State", group: .arpSeq, storage: .sequencer),
        .init(id: .mod,   nrpn: 42, range: 0...25,  displayName: "Mode",          shortName: "Mode",  group: .arpSeq, storage: .sequencer),
        .init(id: .clk,   nrpn: 43, range: 0...34,  displayName: "Clock",         shortName: "Clock", group: .arpSeq, storage: .sequencer),
        .init(id: .gat,   nrpn: 44, range: 1...99,  displayName: "Gate Time",     shortName: "Gate",  group: .arpSeq, storage: .sequencer),
        .init(id: .div,   nrpn: 45, range: 0...6,   displayName: "Clock Div",     shortName: "Div",   group: .arpSeq, storage: .sequencer),
        .init(id: .bpm,   nrpn: 46, range: 40...240,displayName: "BPM",           shortName: "BPM",   group: .arpSeq, storage: .sequencer),

        // MARK: Global (live NRPN only)
        .init(id: .dtf,      nrpn: 3,  range: 0...7, displayName: "Recall Mode",    shortName: "DTF",   group: .global, storage: .globalOnly),
        .init(id: .tune,     nrpn: 4,  range: 0...99,displayName: "Master Tune",    shortName: "Tune",  group: .global, storage: .globalOnly),
        .init(id: .expPedal, nrpn: 5,  range: 0...5, displayName: "Exp Pedal",      shortName: "Pedal", group: .global, storage: .globalOnly),
        .init(id: .touch,    nrpn: 6,  range: 0...3, displayName: "Aftertouch",     shortName: "AT",    group: .global, storage: .globalOnly),
        .init(id: .brt,      nrpn: 7,  range: 0...99,displayName: "LCD Brightness", shortName: "Brt",   group: .global, storage: .globalOnly),
        .init(id: .cnt,      nrpn: 8,  range: 0...99,displayName: "LCD Contrast",   shortName: "Cnt",   group: .global, storage: .globalOnly),
        .init(id: .firm,     nrpn: 9,  range: 0...2, displayName: "Env Mode",       shortName: "Env",   group: .global, storage: .globalOnly),
        .init(id: .osc,      nrpn: 10, range: 0...1, displayName: "Osc Mode",       shortName: "Osc",   group: .global, storage: .globalOnly),
        .init(id: .lfo,      nrpn: 11, range: 0...1, displayName: "LFO Mode",       shortName: "LFO",   group: .global, storage: .globalOnly),
    ]

    // MARK: - Lookups

    static let byID: [WaveParamID: WaveParamDescriptor] = {
        Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
    }()

    static let byNRPN: [Int: WaveParamDescriptor] = {
        Dictionary(
            all.compactMap { d -> (Int, WaveParamDescriptor)? in
                guard let n = d.nrpn else { return nil }
                return (n, d)
            },
            uniquingKeysWith: { first, _ in first }
        )
    }()

    static func descriptor(for id: WaveParamID) -> WaveParamDescriptor? { byID[id] }
    static func descriptor(forNRPN nrpn: Int) -> WaveParamDescriptor? { byNRPN[nrpn] }

    // MARK: - SysEx byte address helpers

    /// Byte index in the 121-byte preset payload for Group A.
    static func sysexByteA(for id: WaveParamID) -> Int? {
        guard let d = byID[id] else { return nil }
        switch d.storage {
        case .shared(let b):              return b
        case .perGroup(let offset):       return groupABase + offset
        case .sequencer, .globalOnly:     return nil
        }
    }

    /// Byte index in the 121-byte preset payload for Group B.
    static func sysexByteB(for id: WaveParamID) -> Int? {
        guard let d = byID[id] else { return nil }
        switch d.storage {
        case .shared(let b):              return b         // same byte for both groups
        case .perGroup(let offset):       return groupBBase + offset
        case .sequencer, .globalOnly:     return nil
        }
    }
}

// MARK: - WavePatchValues

/// Flat value store for one parsed patch. Keyed by WaveParamID.
/// Group A and B are stored with separate suffixed keys (e.g. "DELAY_A", "DELAY_B").
/// Shared params use the plain key.
struct WavePatchValues: Codable {
    var params: [String: Int] = [:]

    func value(for id: WaveParamID, group: WaveGroup) -> Int {
        let key = storageKey(id: id, group: group)
        return params[key] ?? 0
    }

    mutating func setValue(_ value: Int, for id: WaveParamID, group: WaveGroup) {
        params[storageKey(id: id, group: group)] = value
    }

    private func storageKey(id: WaveParamID, group: WaveGroup) -> String {
        guard let d = WaveParameters.byID[id] else { return id.rawValue }
        switch d.storage {
        case .shared:  return id.rawValue
        default:       return "\(id.rawValue)_\(group.rawValue)"
        }
    }
}

// MARK: - Group

enum WaveGroup: String, CaseIterable, Codable {
    case a = "A"
    case b = "B"
}

// MARK: - Keyboard Mode names

extension WaveParamID {
    static let keybModeNames: [Int: String] = [
        0: "Poly",
        1: "Mono",
        2: "Mono Low",
        3: "Mono High",
        4: "Mono Last",
        5: "Quad",
        6: "A Poly B Mono",
        7: "Quad A/B",
        8: "Quad A Low",
        9: "CV In"
    ]
}

// MARK: - Notification names

extension Notification.Name {
    static let waveParameterChanged = Notification.Name("waveParameterChanged")
}
