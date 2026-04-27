//
//  PatchInspectorView.swift
//  brWave
//
//  Right-column inspector for a selected patch.
//  Shows patch metadata, hardware send controls, category, and edit.
//

import SwiftUI
import CoreData

struct PatchInspectorView: View {
    @ObservedObject var patch: Patch
    @EnvironmentObject var patchSelection: PatchSelection
    @Environment(\.managedObjectContext) var context

    @ObservedObject private var midi = MIDIController.shared
    @State private var editingName = false
    @State private var nameText = ""
    @State private var sendFeedback: String? = nil
    @State private var similarExpanded = false
    @State private var similarMatches: [SimilarityEngine.Match] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                headerSection
                Divider().padding(.vertical, 8)
                hardwareSection
                Divider().padding(.vertical, 8)
                metadataSection
                Divider().padding(.vertical, 8)
                categorySection
                Divider().padding(.vertical, 8)
                similarSection
            }
            .padding(16)
        }
        .frame(minWidth: 220)
        .onAppear { nameText = patch.name ?? "" }
        .onChange(of: patch.objectID) { _, _ in nameText = patch.name ?? "" }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Inspector")
                .font(.headline)
                .foregroundStyle(Theme.waveHighlight)

            if editingName {
                HStack {
                    TextField("Name", text: $nameText, onCommit: commitName)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13))
                    Button("Done") { commitName() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
            } else {
                HStack(alignment: .firstTextBaseline) {
                    Text(patch.name ?? "Untitled")
                        .font(.title3.bold())
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Spacer()
                    Button {
                        nameText = patch.name ?? ""
                        editingName = true
                    } label: {
                        Image(systemName: "pencil")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            if let designer = patch.designer, !designer.isEmpty {
                Text(designer)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Hardware

    private var hardwareSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Hardware", systemImage: "cable.connector.horizontal")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            let connected = midi.selectedDestinationUID != nil

            Button {
                sendToEditBuffer()
            } label: {
                Label("Send to Edit Buffer", systemImage: "arrow.right.circle.fill")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.waveHighlight)
            .controlSize(.regular)
            .disabled(!connected || patch.rawBytes.isEmpty)

            if let bank = bankIndex, let prog = programIndex, bank >= 0, prog >= 0 {
                Button {
                    sendToSlot(bank: bank, program: prog)
                } label: {
                    Label("Write to B\(bank) P\(String(format: "%02d", prog))",
                          systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .disabled(!connected || patch.rawBytes.isEmpty)
            }

            if let fb = sendFeedback {
                Text(fb)
                    .font(.caption2)
                    .foregroundStyle(Theme.waveHighlight)
                    .transition(.opacity)
            }

            if !connected {
                Label("No MIDI device connected", systemImage: "exclamationmark.triangle")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Metadata

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Patch Data", systemImage: "info.circle")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .padding(.bottom, 2)

            if let bank = bankIndex, let prog = programIndex, bank >= 0 && prog >= 0 {
                metaRow("Slot", "Bank \(bank) · Prog \(String(format: "%02d", prog))")
            }

            let wavetb = patch.value(for: .wavetb, group: .a)
            metaRow("Wavetable", "\(wavetb) \(wavetableLabel(wavetb))")

            let keyb = patch.value(for: .keyb, group: .a)
            if let modeName = WaveParamID.keybModeNames[keyb] {
                metaRow("Mode", modeName)
            }

            metaRow("Payload", "\(patch.rawBytes.count) bytes")

            if let date = patch.dateModified {
                metaRow("Modified", RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date()))
            }
        }
    }

    // MARK: - Category

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Category", systemImage: "tag")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            let cat = patch.patchCategory
            HStack(spacing: 6) {
                Circle()
                    .fill(cat.color)
                    .frame(width: 8, height: 8)
                Text(cat.rawValue)
                    .font(.callout)
                Spacer()
                Button("Re-classify") {
                    let name = patch.name ?? ""
                    patch.category = PatchCategory.classify(patchName: name).rawValue
                    try? context.save()
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            // Override picker
            Picker("", selection: Binding(
                get: { patch.patchCategory },
                set: { newCat in
                    patch.category = newCat.rawValue
                    try? context.save()
                }
            )) {
                ForEach(PatchCategory.allCases) { cat in
                    Label(cat.rawValue, systemImage: "circle.fill")
                        .tag(cat)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.small)

            // Favorite toggle
            Button {
                patch.isFavorite.toggle()
                try? context.save()
            } label: {
                Label(patch.isFavorite ? "Remove from Favorites" : "Add to Favorites",
                      systemImage: patch.isFavorite ? "star.fill" : "star")
                    .font(.callout)
                    .foregroundStyle(patch.isFavorite ? Theme.waveHighlight : .secondary)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
    }

    // MARK: - Similar Patches
    //
    // Searches from the Bayesian prior (patchSelection.priorPatch), not the
    // selected patch. The prior only moves when you jump far enough in vector
    // space, so browsing nearby patches keeps recommendations stable.
    // A small indicator shows when the prior differs from the current selection.

    private var priorIsDifferent: Bool {
        guard let prior = patchSelection.priorPatch else { return false }
        return prior.objectID != patch.objectID
    }

    private var similarSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    similarExpanded.toggle()
                }
                if similarExpanded && similarMatches.isEmpty {
                    loadSimilarMatches()
                }
            } label: {
                HStack {
                    Label("Similar Patches", systemImage: "sparkles")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Spacer()
                    if priorIsDifferent {
                        // Prior is anchored elsewhere — show which patch it's from
                        Text("anchored: \(patchSelection.priorPatch?.name ?? "?")")
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.waveHighlight.opacity(0.8))
                            .lineLimit(1)
                    }
                    Image(systemName: similarExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            if similarExpanded {
                if priorIsDifferent {
                    Button {
                        patchSelection.resetPrior()
                        loadSimilarMatches()
                    } label: {
                        Text("Reset anchor to this patch")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.waveHighlight)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 4)
                }

                if similarMatches.isEmpty {
                    Text("No similar patches found")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 4)
                } else {
                    VStack(spacing: 0) {
                        ForEach(similarMatches) { match in
                            Button {
                                patchSelection.selectedPatch = match.patch
                            } label: {
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(match.patch.patchCategory.color)
                                        .frame(width: 6, height: 6)
                                    Text(match.patch.name ?? "Untitled")
                                        .font(.caption)
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Spacer()
                                    Text(String(format: "%.2f", match.score))
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.vertical, 4)
                                .padding(.horizontal, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(patchSelection.selectedPatch?.objectID == match.patch.objectID
                                              ? Theme.waveHighlight.opacity(0.15) : Color.clear)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .onChange(of: patch.objectID) { _, _ in
            similarMatches = []
            if similarExpanded { loadSimilarMatches() }
        }
        .onChange(of: patchSelection.priorPatch?.objectID) { _, _ in
            similarMatches = []
            if similarExpanded { loadSimilarMatches() }
        }
    }

    private func loadSimilarMatches() {
        let anchor = patchSelection.priorPatch ?? patch
        similarMatches = SimilarityEngine.findSimilar(to: anchor, in: context, limit: 8)
    }

    // MARK: - Helpers

    private func metaRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
            Text(value)
                .font(.caption)
                .foregroundStyle(.primary)
            Spacer()
        }
    }

    private var bankIndex: Int? {
        let b = Int(patch.bank)
        return b >= 0 ? b : nil
    }
    private var programIndex: Int? {
        let p = Int(patch.program)
        return p >= 0 ? p : nil
    }

    private func wavetableLabel(_ n: Int) -> String {
        WaveTables.slotDisplayName(for: n)
    }

    private func commitName() {
        let trimmed = nameText.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            patch.name = String(trimmed.prefix(16))
            try? context.save()
        }
        editingName = false
    }

    private func sendToEditBuffer() {
        guard !patch.rawBytes.isEmpty else { return }
        MIDIController.shared.sendToEditBuffer(payload: patch.rawBytes)
        showFeedback("Sent to edit buffer")
    }

    private func sendToSlot(bank: Int, program: Int) {
        guard !patch.rawBytes.isEmpty else { return }
        MIDIController.shared.sendPreset(bank: bank, program: program, payload: patch.rawBytes)
        showFeedback("Written to B\(bank) P\(String(format: "%02d", program))")
    }

    private func showFeedback(_ msg: String) {
        withAnimation { sendFeedback = msg }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation { sendFeedback = nil }
        }
    }
}
