//
//  FloatingToolbar.swift
//  brWave
//
//  Floating pill toolbar above the patch editor area.
//  Ported from OBsixer — adapted for Wave 3-message NRPN and Group A/B.
//

import SwiftUI

enum PatchDisplayMode: String, CaseIterable {
    case panel = "Panel"
    case table = "Table"
}

struct FloatingToolbar: View {
    @ObservedObject var patch: Patch
    @Binding var layoutMode: PatchDisplayMode
    var onInit: () -> Void

    var body: some View {
        HStack(spacing: 12) {

            // Init
            Button(action: onInit) {
                Label("Init", systemImage: "doc.badge.plus")
            }
            .buttonStyle(.plain)
            .help("Initialize patch to default values")

            // Pattern generator menu
            Menu {
                ForEach(PatchCategory.allCases.filter { $0 != .uncategorized }) { cat in
                    Button {
                        PatchGenerator.generate(cat, for: patch)
                        try? patch.managedObjectContext?.save()
                    } label: {
                        Label(cat.rawValue, systemImage: "circle.fill")
                    }
                }
            } label: {
                Label("Pattern", systemImage: "wand.and.stars")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Generate patch from category template")

            Divider().frame(height: 16)

            // Panel / Table picker
            Picker("", selection: $layoutMode) {
                Text("Panel").tag(PatchDisplayMode.panel)
                Text("Table").tag(PatchDisplayMode.table)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 120)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1))
        .shadow(color: .black.opacity(0.4), radius: 10, y: 5)
    }
}
