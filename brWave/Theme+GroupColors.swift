//
//  Theme+GroupColors.swift
//  brWave
//
//  Group color system for the Wave panel sections.
//  Protocol is synth-agnostic — port verbatim to other editors,
//  then supply a synth-specific GroupColorProviding implementation.
//

import SwiftUI

// MARK: - Protocol

public protocol GroupColorProviding {
    func color(for groupName: String?) -> Color
}

// MARK: - Wave default provider

public struct WaveGroupColorProvider: GroupColorProviding {
    public init() {}
    public func color(for groupName: String?) -> Color {
        let name = (groupName ?? "").lowercased()
        switch name {
        case "oscillators", "osc", "oscillator", "waves", "digital":
            return Color(red: 0.16, green: 0.80, blue: 1.0)   // Wave electric blue
        case "filter":
            return Color(red: 1.00, green: 0.60, blue: 0.25)  // warm orange
        case "filter env", "filter envelope", "envf":
            return Color(red: 1.00, green: 0.72, blue: 0.35)
        case "lfo", "analog":
            return Color(red: 0.35, green: 0.90, blue: 0.95)  // teal
        case "envelopes", "envelope", "env", "amp env", "loudness env", "pitch env":
            return Color(red: 0.95, green: 0.38, blue: 0.38)  // red/coral
        case "modulation", "mod", "routing":
            return Color(red: 0.75, green: 0.55, blue: 0.95)  // purple
        case "performance":
            return Color(red: 0.60, green: 0.75, blue: 1.00)  // light blue
        case "tuning", "voice tuning":
            return Color(red: 0.55, green: 0.85, blue: 0.75)  // seafoam
        case "arpeggiator", "arp", "sequencer", "seq":
            return Color(red: 0.60, green: 0.95, blue: 0.45)  // green
        case "global":
            return Color(white: 0.70)
        default:
            return Color(white: 0.50)
        }
    }
}

// MARK: - Theme extension

extension Theme {
    private static var _groupColorProvider: GroupColorProviding = WaveGroupColorProvider()

    public static func setGroupColorProvider(_ provider: GroupColorProviding) {
        _groupColorProvider = provider
    }

    public static func groupColor(for groupName: String?) -> Color {
        _groupColorProvider.color(for: groupName)
    }
}
