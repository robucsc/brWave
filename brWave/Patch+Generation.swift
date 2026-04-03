//
//  Patch+Generation.swift
//  brWave
//
//  Generates random templates based on Category keywords.
//  Provides native Behringer Wave 121-byte patches to populate the app
//  while we work on importing retro formats.
//

import Foundation
import CoreData

struct PatchGenerator {
    
    /// Generates a new patch based on the seed category and applies it to the target patch.
    /// When real-patch centroid data is available (after the first galaxy layout), uses the
    /// category's centroid as the base — a Bayesian MAP estimate from the actual library.
    /// Falls back to the deterministic template when no centroid is available.
    static func generate(_ category: PatchCategory, for patch: Patch) {
        let (values, _) = generateValues(category)
        patch.patchValues = values
        patch.name = "\(category.rawValue) Template"
    }

    /// Generates a batch of random patches across different categories.
    /// Useful for populating the galaxy or testing.
    static func generateRandomBatch(count: Int) -> [(values: WavePatchValues, name: String, category: PatchCategory)] {
        var results: [(WavePatchValues, String, PatchCategory)] = []
        let categories = PatchCategory.allCases.filter { $0 != .uncategorized }
        
        for _ in 0..<count {
            let cat = categories.randomElement() ?? .bass
            let suffix = String(format: "%03d", Int.random(in: 1...999))
            let (values, baseName) = generateValues(cat)
            results.append((values, "\(baseName) \(suffix)", cat))
        }
        
        return results
    }

    /// Returns: (Values, Name) — fully deterministic, no random values.
    static func generateValues(_ category: PatchCategory) -> (WavePatchValues, String) {
        var v = WavePatchValues(params: [:])

        // Common Defaults — ensure a PLAYABLE, AUDIBLE patch reaches the hardware
        // Shared parameters
        v.setValue(0, for: .wavetb, group: .a) // Wavetable 0
        v.setValue(0, for: .keyb, group: .a)   // Poly mode
        
        // Set basic playable envelopes for both Groups A & B
        for g in [WaveGroup.a, WaveGroup.b] {
            // Loudness Envelope
            v.setValue(0,   for: .a2, group: g)
            v.setValue(64,  for: .d2, group: g)
            v.setValue(127, for: .s2, group: g)
            v.setValue(20,  for: .r2, group: g)
            
            // Filter Envelope
            v.setValue(0,   for: .a1, group: g)
            v.setValue(64,  for: .d1, group: g)
            v.setValue(0,   for: .s1, group: g)
            v.setValue(20,  for: .r1, group: g)
            
            // Filter fully open
            v.setValue(127, for: .vcfCutoff, group: g)
            v.setValue(0,   for: .vcfEmphasis, group: g)
            
            // Osc
            v.setValue(0,   for: .wavesOsc, group: g)
        }

        switch category {
        case .uncategorized:
            break
            
        case .bass:
            v.setValue(1, for: .keyb, group: .a)   // Mono mode
            for g in [WaveGroup.a, WaveGroup.b] {
                v.setValue(15, for: .wavetb, group: g) // Bass-heavy table
                v.setValue(30, for: .vcfCutoff, group: g)
                v.setValue(60, for: .vcfEmphasis, group: g)
                v.setValue(100, for: .env1VCF, group: g) // Pluck mod
                v.setValue(0,  for: .a2, group: g)
                v.setValue(40, for: .d2, group: g)
                v.setValue(0,  for: .s2, group: g)
                v.setValue(10, for: .r2, group: g)
            }

        case .lead:
            v.setValue(1, for: .keyb, group: .a)   // Mono mode
            for g in [WaveGroup.a, WaveGroup.b] {
                v.setValue(5,  for: .wavetb, group: g) // Bright table
                v.setValue(100, for: .vcfCutoff, group: g)
                v.setValue(30,  for: .vcfEmphasis, group: g)
                v.setValue(10,  for: .a2, group: g)
                v.setValue(64,  for: .d2, group: g)
                v.setValue(127, for: .s2, group: g)
                v.setValue(30,  for: .r2, group: g)
                v.setValue(10,  for: .delay, group: g) // LFO vibrato delay
                v.setValue(60,  for: .rate, group: g)
                v.setValue(20,  for: .modWhl, group: g)
            }

        case .pad:
            v.setValue(0, for: .keyb, group: .a)   // Poly mode
            for g in [WaveGroup.a, WaveGroup.b] {
                v.setValue(10, for: .wavetb, group: g) // Sweep table
                v.setValue(50, for: .vcfCutoff, group: g)
                v.setValue(60, for: .a2, group: g)
                v.setValue(64, for: .d2, group: g)
                v.setValue(127, for: .s2, group: g)
                v.setValue(70, for: .r2, group: g)
                v.setValue(100, for: .env1Waves, group: g) // Slow Wavetable sweep
                v.setValue(50, for: .a1, group: g)
            }

        case .poly:
            v.setValue(0, for: .keyb, group: .a)
            for g in [WaveGroup.a, WaveGroup.b] {
                v.setValue(20, for: .a2, group: g)
                v.setValue(64, for: .d2, group: g)
                v.setValue(127, for: .s2, group: g)
                v.setValue(40, for: .r2, group: g)
            }

        case .strings:
            for g in [WaveGroup.a, WaveGroup.b] {
                v.setValue(2,  for: .wavetb, group: g)
                v.setValue(40, for: .a2, group: g)
                v.setValue(127, for: .s2, group: g)
                v.setValue(50, for: .r2, group: g)
                v.setValue(80, for: .vcfCutoff, group: g)
            }

        case .brass:
            for g in [WaveGroup.a, WaveGroup.b] {
                v.setValue(12, for: .wavetb, group: g)
                v.setValue(40, for: .vcfCutoff, group: g)
                v.setValue(20, for: .a1, group: g)
                v.setValue(50, for: .d1, group: g)
                v.setValue(80, for: .env1VCF, group: g)
            }

        case .keys:
            for g in [WaveGroup.a, WaveGroup.b] {
                v.setValue(3,  for: .wavetb, group: g) 
                v.setValue(0,  for: .a2, group: g)
                v.setValue(50, for: .d2, group: g)
                v.setValue(0,  for: .s2, group: g)
                v.setValue(20, for: .r2, group: g)
            }

        case .organ:
            for g in [WaveGroup.a, WaveGroup.b] {
                v.setValue(4,  for: .wavetb, group: g)
                v.setValue(0,  for: .a2, group: g)
                v.setValue(127, for: .s2, group: g)
                v.setValue(0,  for: .r2, group: g)
                v.setValue(127, for: .vcfCutoff, group: g)
            }

        case .piano:
            for g in [WaveGroup.a, WaveGroup.b] {
                v.setValue(0,  for: .a2, group: g)
                v.setValue(70, for: .d2, group: g)
                v.setValue(0,  for: .s2, group: g)
                v.setValue(30, for: .r2, group: g)
            }

        case .percussion:
            for g in [WaveGroup.a, WaveGroup.b] {
                v.setValue(0,  for: .a2, group: g)
                v.setValue(20, for: .d2, group: g)
                v.setValue(0,  for: .s2, group: g)
                v.setValue(10, for: .r2, group: g)
            }

        case .fx:
            for g in [WaveGroup.a, WaveGroup.b] {
                v.setValue(10, for: .vcfCutoff, group: g)
                v.setValue(120, for: .vcfEmphasis, group: g)
                v.setValue(120, for: .env1VCF, group: g)
                v.setValue(127, for: .rate, group: g) // Fast LFO
            }

        case .sequence:
            break
        case .arp:
            break
        }

        return (v, "\(category.rawValue)")
    }
}
