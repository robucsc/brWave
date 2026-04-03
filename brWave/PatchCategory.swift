//
//  PatchCategory.swift
//  brWave
//
//  Patch categories — same set as Sledgitor/OBsixer for cross-app consistency.
//  Classification is keyword-based (patch name) since the Wave SysEx
//  carries no built-in category field.
//

import SwiftUI

enum PatchCategory: String, CaseIterable, Identifiable {
    case uncategorized = "Uncategorized"
    case bass          = "Bass"
    case lead          = "Lead"
    case pad           = "Pad"
    case poly          = "Poly"
    case strings       = "Strings"
    case brass         = "Brass"
    case keys          = "Keys"
    case organ         = "Organ"
    case piano         = "Piano"
    case percussion    = "Percussion"
    case fx            = "FX"
    case sequence      = "Sequence"
    case arp           = "Arp"

    var id: String { rawValue }

    // MARK: - Color (matches GalaxyHierarchy in Sledgitor/OBsixer)

    var color: Color {
        switch self {
        case .bass:          return .red
        case .lead:          return .orange
        case .pad:           return .blue
        case .strings:       return .purple
        case .brass:         return .yellow
        case .keys:          return .green
        case .fx:            return .pink
        case .percussion:    return .teal
        case .organ:         return .mint
        case .piano:         return .indigo
        case .sequence:      return .brown
        case .arp:           return .cyan
        case .poly:          return .teal
        case .uncategorized: return Color(red: 0.4, green: 0.35, blue: 0.6)
        }
    }

    // MARK: - Keyword classifier

    /// Infers a category from the patch name using keyword matching.
    /// Returns .uncategorized when no keywords match.
    static func classify(patchName: String) -> PatchCategory {
        let name = patchName.lowercased()

        // Order matters — more specific terms first
        let rules: [(keywords: [String], category: PatchCategory)] = [
            (["seq", "sequen", "step"],                      .sequence),
            (["arp", "arpegg"],                              .arp),
            (["perc", "drum", "kick", "snare", "hat", "clave", "rim", "clap"], .percussion),
            (["organ", "organ ", "orgue"],                   .organ),
            (["piano", "grand", "electric piano", "e.piano"], .piano),
            (["string", "violin", "cello", "viola", "orch"], .strings),
            (["brass", "horn", "trumpet", "trombone", "sax"], .brass),
            (["bass", "sub", "808"],                         .bass),
            (["lead", "solo", "mono lead"],                  .lead),
            (["pad", "ambient", "atmosphere", "atmo", "drone", "wash"], .pad),
            (["key", "clav", "rhodes", "wurli", "ep "],      .keys),
            (["poly", "chord", "ensemble"],                  .poly),
            (["fx", "effect", "noise", "sfx", "sweep", "riser", "zap"], .fx),
        ]

        for rule in rules {
            for keyword in rule.keywords where name.contains(keyword) {
                return rule.category
            }
        }
        return .uncategorized
    }
}

// MARK: - Patch extension

extension Patch {
    var patchCategory: PatchCategory {
        PatchCategory(rawValue: category ?? "") ?? .uncategorized
    }
}
