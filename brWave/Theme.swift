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
    /// XR section header background (Dark Slate/Teal)
    static let xrHeaderBackground = Color(red: 0.12, green: 0.20, blue: 0.24)
    /// XR section content background (Near Black)
    static let xrSectionBackground = Color(red: 0.07, green: 0.07, blue: 0.07)
    /// Banks/librarian grid background
    static let gridBackground    = Color(red: 0.04, green: 0.04, blue: 0.06)

    // MARK: - Labels

    static let labelPrimary   = Color(white: 0.95)

    // MARK: - Foreground & Accents

    /// Group A arc colour — high-contrast cyan
    static let waveHighlight     = Color(red: 0.0, green: 0.85, blue: 1.0)
    /// Group B arc colour — warm amber (complementary to cyan)
    static let waveGroupBHighlight = Color(red: 1.0, green: 0.58, blue: 0.08)
    /// Phosphor green for active readouts/values
    static let waveValueText     = Color(red: 0.10, green: 0.95, blue: 0.30)
    /// Sequential Blue for section accents and borders (XR style)
    static let xrAccentBlue      = Color(red: 0.18, green: 0.28, blue: 0.65)
    
    /// Hardware red for LEDs
    static let waveLED           = Color(red: 0.90, green: 0.18, blue: 0.12)
    /// Dimmed grey for inactive labels
    static let labelSecondary    = Color(white: 0.40)

    // MARK: - Knob Sizes

    static let knobSizeLarge:  CGFloat = 80
    static let knobSizeMedium: CGFloat = 68
    static let knobSizeSmall:  CGFloat = 58
    static let knobSizeMini:   CGFloat = 42
}

// MARK: - Conditional modifier helper

extension View {
    @ViewBuilder
    func `if`<Transform: View>(_ condition: Bool, transform: (Self) -> Transform) -> some View {
        if condition { transform(self) } else { self }
    }
}
