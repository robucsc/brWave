//
//  Theme.swift
//  brWave
//
//  PPG Wave aesthetic: deep blue panel, light knobs, minimal chrome.
//

import SwiftUI

struct Theme {

    // MARK: - Backgrounds

    /// Deep dark panel background (XR profile)
    static let panelBackground   = Color(red: 0.05, green: 0.05, blue: 0.06)
    /// App chrome background
    static let surfaceBackground = Color(red: 0.11, green: 0.11, blue: 0.14)
    /// Section/header blue matched to the requested hardware-style title strip.
    static let xrHeaderBackground = Color(red: 56.0 / 255.0, green: 114.0 / 255.0, blue: 214.0 / 255.0)
    /// XR section content background (Near Black)
    static let xrSectionBackground = Color(red: 0.07, green: 0.07, blue: 0.07)
    /// Banks/librarian grid background
    static let gridBackground    = Color(red: 0.04, green: 0.04, blue: 0.06)

    // MARK: - Labels

    static let labelPrimary   = Color(white: 0.95)

    // MARK: - Foreground & Accents

    /// Group A arc colour — clearer electric blue, less teal so A/B differences stay readable.
    static let waveHighlight     = Color(red: 0.16, green: 0.80, blue: 1.0)
    /// Group B arc colour — cool white with a touch of blue so it stays visible against the dark panel.
    static let waveGroupBHighlight = Color(red: 0.90, green: 0.95, blue: 1.0)
    /// Phosphor green for active readouts/values
    static let waveValueText     = Color(red: 0.10, green: 0.95, blue: 0.30)
    /// Accent blue kept in the same family as the requested title-strip blue.
    static let xrAccentBlue      = Color(red: 56.0 / 255.0, green: 114.0 / 255.0, blue: 214.0 / 255.0)
    
    /// Hardware red for LEDs
    static let waveLED           = Color(red: 0.90, green: 0.18, blue: 0.12)
    /// Dimmed grey for inactive labels
    static let labelSecondary    = Color(white: 0.40)

    // MARK: - Knob Sizes

    static let knobSizeLarge:  CGFloat = 80
    static let knobSizeMedium: CGFloat = 70
    static let knobSizeSmall:  CGFloat = 60
    static let knobSizeMini:   CGFloat = 40
}

// MARK: - Conditional modifier helper

extension View {
    @ViewBuilder
    func `if`<Transform: View>(_ condition: Bool, transform: (Self) -> Transform) -> some View {
        if condition { transform(self) } else { self }
    }
}
