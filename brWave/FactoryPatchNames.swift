//
//  FactoryPatchNames.swift
//  brWave
//
//  Factory preset name resolution for the Behringer Wave.
//
//  Background:
//  The Wave hardware does not store or recall patch names — bytes 0–15 of every
//  SPKT 0x06 response are always returned as "1111111111111111" regardless of
//  what was written. (Confirmed: KnobKraft-ORM adaptation, firmware 1.0.11.)
//
//  Resolution strategy (three tiers):
//
//  1. Positional lookup — if bank/program is known and matches a factory slot,
//     return the official factory name from the manual's preset list.
//     Fast, accurate for unmodified factory patches fresh off the hardware.
//
//  2. Vector matching — once factory vectors are built (call buildVectorRegistry
//     after factory SYX is imported), nearest-neighbor Euclidean distance in
//     parameter space identifies factory patches even when moved to a new slot
//     or slightly modified. Threshold ~0.02 = exact match; increase for fuzzy.
//     Shares the same vector infrastructure as Galaxy and SimilarityEngine.
//
//  3. Generated name — fallback when no factory match is found.
//     Format: "{WT slot name} {mainPos}/{subPos}"  e.g. "HmcBliss 08/12"
//     mainPos / subPos are WAVES-OSC / WAVES-SUB divided by 2 (0–63 display range).
//
//  Source: Behringer Wave User Manual v1.0.11, factory preset list.
//  Cross-referenced with KnobKraft-ORM Behringer_Wave.py adaptation.
//

import CoreData

enum FactoryPatchNames {

    // MARK: - Public API

    /// Primary entry point. Returns the best available name for a patch
    /// whose SysEx name bytes are placeholders.
    ///
    /// - Parameters:
    ///   - bank:     hardware bank (0 or 1)
    ///   - program:  hardware program (0–99)
    ///   - vector:   normalised parameter vector from SimilarityEngine.patchToVector
    ///   - wavetb:   WAVETB parameter value (0–127)
    ///   - wavesOsc: WAVES-OSC Group A value (0–127 stored, divide by 2 for display)
    ///   - wavesSub: WAVES-SUB Group A value (0–127 stored, divide by 2 for display)
    static func resolve(bank: Int?, program: Int?,
                        vector: [Double]? = nil,
                        wavetb: Int = 0, wavesOsc: Int = 0, wavesSub: Int = 0) -> String {
        // 1. Positional lookup
        if let b = bank, let p = program, let name = factoryName(bank: b, program: p) {
            return name
        }
        // 2. Vector matching (requires registry to be populated)
        if let vec = vector, let name = factoryName(nearestTo: vec) {
            return name
        }
        // 3. Generated name from patch parameters
        return generated(wavetb: wavetb, wavesOsc: wavesOsc, wavesSub: wavesSub)
    }

    // MARK: - Positional Lookup

    static func factoryName(bank: Int, program: Int) -> String? {
        namesByPosition[bank * 100 + program]
    }

    // MARK: - Vector Matching

    /// Nearest-neighbour lookup in the vector registry.
    /// Returns nil if the registry is empty or the nearest match exceeds the threshold.
    static func factoryName(nearestTo vector: [Double],
                            threshold: Double = 0.02) -> String? {
        guard !vectorRegistry.isEmpty else { return nil }
        var bestDist = Double.infinity
        var bestName: String? = nil
        for (name, factoryVec) in vectorRegistry {
            let d = SimilarityEngine.euclideanDistance(v1: vector, v2: factoryVec)
            if d < bestDist { bestDist = d; bestName = name }
        }
        return bestDist <= threshold ? bestName : nil
    }

    /// Build the vector registry from patches already in the CoreData store.
    /// Call once after importing a factory SYX bank — the 200 named patches
    /// provide the anchors for fuzzy matching going forward.
    ///
    /// Thread: must be called on the context's queue (main thread is fine).
    @discardableResult
    static func buildVectorRegistry(from context: NSManagedObjectContext) -> Int {
        let req: NSFetchRequest<Patch> = Patch.fetchRequest()
        guard let patches = try? context.fetch(req) else { return 0 }
        let knownNames = Set(namesByPosition.values)
        var registry: [String: [Double]] = [:]
        for patch in patches {
            if let name = patch.name, knownNames.contains(name) {
                let vec = SimilarityEngine.patchToVector(patch.values)
                if !vec.isEmpty { registry[name] = vec }
            }
        }
        vectorRegistry = registry
        return registry.count
    }

    /// Pre-computed factory patch vectors keyed by patch name.
    /// Populated by buildVectorRegistry(from:).
    private(set) static var vectorRegistry: [String: [Double]] = [:]

    // MARK: - Generated Name Fallback

    /// Constructs a descriptive name from WT slot and oscillator positions.
    static func generated(wavetb: Int, wavesOsc: Int, wavesSub: Int) -> String {
        let wtName = wtSlotName(wavetb)
        let main   = wavesOsc / 2   // stored 0–127, displayed 0–63
        let sub    = wavesSub / 2
        return "\(wtName) \(String(format: "%02d", main))/\(String(format: "%02d", sub))"
    }

    private static func wtSlotName(_ slot: Int) -> String {
        if let name = WaveTables.slotNames[slot] { return name }
        switch slot {
        case 49...63:  return "UserWT\(slot)"
        case 87...127: return "UserTR\(slot)"
        default:       return "WT\(slot)"
        }
    }

    // MARK: - Factory Preset Name Table
    //
    // Source: Behringer Wave User Manual v1.0.11, pp. 30–32
    // Indexed by bank * 100 + program (0–199).

    static let namesByPosition: [Int: String] = [

        // BANK 0 — Behringer Factory (A00–A99)
          0: "Thingie",
          1: "Space Sweep",
          2: "Dynamic Tines",
          3: "Bass & Juno Sweep",
          4: "Dynamic Prophet Brass",
          5: "Stratos",
          6: "Bass & Voco Trem",
          7: "Wurli One",
          8: "Jazz Guitar",
          9: "Rotary B3",
         10: "Bass & PWM Strings",
         11: "Tomita's Bass",
         12: "Church Pipes",
         13: "Dream Vibes",
         14: "Fretless & Tines",
         15: "BellTasia",
         16: "Tubular",
         17: "CZ Sawer",
         18: "FM Brass",
         19: "WAVE Waves",
         20: "FairVox",
         21: "PanFlute",
         22: "Pizzicato",
         23: "Steel Guitar",
         24: "Xylophone",
         25: "Sail Away",
         26: "PWMstringer",
         27: "Soft Bell EP",
         28: "Dusty Rhodos",
         29: "Solo Trumpet",
         30: "Mute Trumpet",
         31: "Duuuh",
         32: "Bass & Wurli",
         33: "Sync Solo",
         34: "Synth Flute",
         35: "Alto Sax",
         36: "Retro Split",
         37: "Strings'n Solo",
         38: "Matrix Strings",
         39: "Alpha Pad",
         40: "Cosmic Soup",
         41: "Harpoon",
         42: "Square Solo",
         43: "Fantasia",
         44: "Synth Pizzi",
         45: "Super Saw",
         46: "Organ Chariot",
         47: "Noise Siren",
         48: "Piano X",
         49: "Percussion",
         50: "Drone Harmonica",
         51: "FanWAVEia",
         52: "Lyle's Solo",
         53: "FM Bass1",
         54: "PWM Pad",
         55: "Solina 1",
         56: "808 Bass",
         57: "SYNC",
         58: "WAVE SeqSplit",
         59: "Synth Cello",
         60: "SoundTrack",
         61: "Solead",
         62: "LA Strings",
         63: "Crystal Waves",
         64: "80s Rig",
         65: "JunPad & CV-Bass",
         66: "Fendi Rhodos",
         67: "Funky Wurli",
         68: "Arpeggio PAD",
         69: "Ding Ding",
         70: "Universal",
         71: "Pipe Brass",
         72: "Big Score",
         73: "Breathy Vox",
         74: "Hammer Harp",
         75: "Spring Pad",
         76: "Octave Bell",
         77: "Yoga Temple",
         78: "Steel Drum",
         79: "Short Bell",
         80: "Square Arp",
         81: "Reso Harp",
         82: "Organic Synth",
         83: "Steel Organ",
         84: "Robotic",
         85: "Reso Phase",
         86: "Arcade Pad",
         87: "PWM Solo",
         88: "VCF SSM2044",
         89: "ARP Lead",
         90: "Spring Pad",
         91: "Reso Dive Organ",
         92: "ArpEratus",
         93: "EquiSAW",
         94: "Woody SQU",
         95: "Wave Chase",
         96: "Poly Bass",
         97: "Wave Slide",
         98: "Landscape",
         99: "Formant Drop",

        // BANK 1 — Classic Wave (B00–B99)
        100: "WAVE Swirl",
        101: "Modulated Vibraphone",
        102: "Harmonic Glide",
        103: "WAVE Tone 16",
        104: "Resonant Extended Synth",
        105: "Belli Pad",
        106: "KW Organ",
        107: "Waow!",
        108: "Organ 1",
        109: "Organ 2",
        110: "Bellgan",
        111: "Wave Organ",
        112: "Filter Mod",
        113: "WAVE Sitar",
        114: "Sawyer",
        115: "StringPan",
        116: "Inspired by Fender Keys",
        117: "Inspired by Electric Keys",
        118: "Env Sync",
        119: "Punchy with Quinte",
        120: "Wave Shaping",
        121: "Concert Piano",
        122: "Brass Bel",
        123: "Punchy",
        124: "Dynamic Spinet",
        125: "Bubble Square",
        126: "Cosmic Spinet",
        127: "Upright Piano",
        128: "Citrus",
        129: "Wave Bypass",
        130: "Synth",
        131: "Pulse Width Synth",
        132: "Resonant Synth Attack",
        133: "Tinkle",
        134: "Sawtooth Extended Synth",
        135: "Punchy with Resonance",
        136: "Punchy Metal",
        137: "Punchy Chime",
        138: "Electric 12-String",
        139: "Chime",
        140: "Long Space Chime",
        141: "Chime-like",
        142: "Delicate Punch",
        143: "Mallet Keys",
        144: "Vibrating Keys",
        145: "Punchy 3",
        146: "Saxophone",
        147: "Brass Section 1",
        148: "Trumpet Section",
        149: "Perc./Extended",
        150: "Deep Brass",
        151: "Trombone Section",
        152: "Brass Ensemble",
        153: "Blended Brass",
        154: "High Register Flute",
        155: "Woodwind Flute",
        156: "String Ensemble 1",
        157: "String Ensemble 2",
        158: "Vox Ocean",
        159: "ChoirTasia",
        160: "Ethereal Strings",
        161: "Ethereal Strings",
        162: "Poly with Sync FX",
        163: "Echo Bell Pad",
        164: "Reed Instrument",
        165: "Concert Piano + Saxophone",
        166: "Studio Organ",
        167: "Cathedral Organ",
        168: "Orgish Bell",
        169: "High Perc",
        170: "Perc",
        171: "Organ 3",
        172: "Organ 1 Redux",
        173: "Raw Choir",
        174: "Blended Choir",
        175: "Ethereal Choir",
        176: "Ethereal Choir 2",
        177: "FX",
        178: "Space Poly",
        179: "FX Poly",
        180: "Sync-stortion",
        181: "Elec Piano",
        182: "Poly Pad",
        183: "Funk Saw",
        184: "Simple Organ",
        185: "Glockenspiel",
        186: "Harp-une",
        187: "Chain Saw Bass",
        188: "Soundcard FM",
        189: "Full Keys",
        190: "Concert Piano Strings",
        191: "Concert Piano with Wave Tone",
        192: "Concert Piano with Sax",
        193: "Perc for Sequencer",
        194: "Delay",
        195: "Pitch Shift",
        196: "FX",
        197: "Quirky",
        198: "Delay Effect",
        199: "Sample & Hold",
    ]
}
