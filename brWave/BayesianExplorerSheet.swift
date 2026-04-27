//
//  BayesianExplorerSheet.swift
//  brWave
//
//  Sheet-based patch explorer backed by BayesianWavePatchSampler.
//  Opens from Patch menu → "Explore from Here…" with the selected patch as seed.
//
//  Session flow:
//    1. Sheet opens → saves original state → seeds sampler from selected patch → generates first
//    2. User navigates ← → through generated history; → incorporates current as evidence
//    3. "Use This" → applies chosen state back to the patch → dismiss
//    4. "New Set from All" → creates PatchSet containing all session patches
//    5. Cancel → restores original state → dismiss

import SwiftUI
import CoreData

// MARK: - Session entry

private struct GeneratedEntry: Identifiable {
    let id          = UUID()
    var patchData:  Data       // JSON dict (patch.values format)
    var name:       String
    var regime:     VectorRegime?
}

// MARK: - Sheet

struct BayesianExplorerSheet: View {

    let patch:   Patch
    let context: NSManagedObjectContext

    @Environment(\.dismiss) private var dismiss

    @StateObject private var sampler = BayesianWavePatchSampler()

    @State private var session:          [GeneratedEntry] = []
    @State private var currentIndex:     Int              = 0
    @State private var originalValues:   Data?
    @State private var originalRawSysex: Data?
    @State private var isGenerating:     Bool             = false
    @State private var showCommitAlert:  Bool             = false
    @State private var commitSetName:    String           = ""
    @State private var animatedAccumulator: Double        = 0

    private let highlight = Theme.waveHighlight

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider().opacity(0.3)
            mainContent
            Divider().opacity(0.3)
            actionBar
        }
        .frame(minWidth: 520, minHeight: 420)
        .background(.ultraThinMaterial)
        .onAppear(perform: setupSession)
        .onChange(of: sampler.accumulator) { _, newVal in
            withAnimation(.spring(duration: 0.4)) { animatedAccumulator = newVal }
        }
        .alert("Save as New Set", isPresented: $showCommitAlert) {
            TextField("Set name", text: $commitSetName)
            Button("Save", action: commitAllToSet)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Creates a new set with \(session.count) generated patch\(session.count == 1 ? "" : "es").")
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("EXPLORE FROM HERE")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                regimeBreadcrumb
            }
            Spacer()
            accumulatorMeter
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var regimeBreadcrumb: some View {
        HStack(spacing: 4) {
            ForEach(Array(sampler.regimeHistory.enumerated()), id: \.element.id) { i, regime in
                if i > 0 {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
                Text(regime.displayLabel)
                    .font(.system(size: 11, weight: i == sampler.regimeHistory.count - 1 ? .semibold : .regular))
                    .foregroundStyle(i == sampler.regimeHistory.count - 1 ? AnyShapeStyle(highlight) : AnyShapeStyle(.secondary))
            }
        }
    }

    private var accumulatorMeter: some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text("SNAP")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.tertiary)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.white.opacity(0.08))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(snapColor)
                        .frame(width: geo.size.width * CGFloat(min(animatedAccumulator / sampler.snapThreshold, 1.0)))
                }
            }
            .frame(width: 100, height: 5)
        }
    }

    private var snapColor: Color {
        let pct = sampler.snapThreshold > 0 ? animatedAccumulator / sampler.snapThreshold : 0
        if pct < 0.5  { return highlight.opacity(0.6) }
        if pct < 0.85 { return .orange }
        return .red
    }

    // MARK: - Main content

    private var mainContent: some View {
        VStack(spacing: 24) {
            Spacer()

            if let entry = currentEntry {
                VStack(spacing: 8) {
                    Text(entry.name)
                        .font(.system(size: 32, weight: .black, design: .rounded))
                        .foregroundStyle(highlight)
                        .contentTransition(.numericText())
                        .animation(.spring(duration: 0.3), value: currentIndex)

                    if let regime = entry.regime {
                        Text(regime.displayLabel)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            } else if isGenerating {
                ProgressView()
                    .controlSize(.regular)
                    .tint(highlight)
            }

            Text("\(currentIndex + 1) of \(session.count)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)
                .animation(.none, value: session.count)

            HStack(spacing: 32) {
                navButton(systemImage: "arrow.left", label: "Prev",
                          enabled: currentIndex > 0) {
                    navigate(by: -1)
                }
                navButton(systemImage: "arrow.right",
                          label: currentIndex < session.count - 1 ? "Next" : "Generate",
                          enabled: !isGenerating, primary: true) {
                    navigateForward()
                }
            }

            Spacer()
        }
        .padding(.horizontal, 32)
    }

    private func navButton(systemImage: String, label: String, enabled: Bool,
                           primary: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 22, weight: .light))
                Text(label)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
            }
            .frame(width: 72, height: 64)
            .background(primary ? highlight.opacity(0.15) : Color.white.opacity(0.05))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(primary ? highlight.opacity(0.5) : Color.white.opacity(0.1), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .foregroundStyle(enabled ? (primary ? AnyShapeStyle(highlight) : AnyShapeStyle(Color.primary)) : AnyShapeStyle(Color.secondary))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .keyboardShortcut(systemImage.contains("right") ? .rightArrow : .leftArrow, modifiers: [])
    }

    // MARK: - Action bar

    private var actionBar: some View {
        HStack(spacing: 12) {
            Button("Cancel") { cancelAndDismiss() }
                .keyboardShortcut(.escape, modifiers: [])

            Spacer()

            Button {
                commitSetName = "Explored \(patch.name ?? patch.patchCategory.rawValue) \(shortDate)"
                showCommitAlert = true
            } label: {
                Label("New Set from All (\(session.count))", systemImage: "square.stack.3d.up")
            }
            .disabled(session.isEmpty)

            Button {
                useThisAndDismiss()
            } label: {
                Label("Use This", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(highlight)
            }
            .keyboardShortcut(.return, modifiers: [])
            .buttonStyle(.borderedProminent)
            .tint(highlight.opacity(0.25))
            .disabled(session.isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Session setup

    private func setupSession() {
        originalValues   = patch.values
        originalRawSysex = patch.rawSysexPayload
        commitSetName    = "Explored \(patch.name ?? patch.patchCategory.rawValue) \(shortDate)"
        sampler.seed(from: patch)
        generateNext()
    }

    // MARK: - Navigation

    private func navigate(by delta: Int) {
        let next = currentIndex + delta
        guard session.indices.contains(next) else { return }
        currentIndex = next
        applyCurrentEntry()
    }

    private func navigateForward() {
        if currentIndex < session.count - 1 {
            currentIndex += 1
            applyCurrentEntry()
        } else {
            generateNext()
        }
    }

    private func generateNext() {
        guard !isGenerating else { return }
        isGenerating = true
        DispatchQueue.main.async {
            guard let data = sampler.generate() else { isGenerating = false; return }
            let regime = sampler.currentRegime
            let index  = session.count + 1
            let catName = patch.patchCategory.rawValue
            let entry   = GeneratedEntry(patchData: data,
                                         name: "\(catName) \(index)",
                                         regime: regime)
            session.append(entry)
            currentIndex = session.count - 1
            isGenerating = false
            applyCurrentEntry()
            // Incorporate into sampler as evidence for the next generation
            _ = sampler.sampler.incorporate(SimilarityEngine.patchToVector(data), weight: 1.0)
        }
    }

    @AppStorage("autoSendPatchOnSelection") private var autoSendPatchOnSelection = false

    // MARK: - Apply entry to patch (live UI + optional hardware audition)

    private func applyCurrentEntry() {
        guard let entry = currentEntry else { return }
        patch.values = entry.patchData
        patch.rebuildRawSysex(name: entry.name)
        NotificationCenter.default.post(name: .waveParameterChanged, object: patch, userInfo: nil)
        if autoSendPatchOnSelection {
            MIDIController.shared.sendToEditBuffer(payload: patch.rawBytes)
        }
    }

    // MARK: - Commit actions

    private func useThisAndDismiss() {
        applyCurrentEntry()
        if let entryName = currentEntry?.name {
            patch.name = entryName
        }
        patch.dateModified = Date()
        try? context.save()
        dismiss()
    }

    private func cancelAndDismiss() {
        patch.values         = originalValues
        patch.rawSysexPayload = originalRawSysex
        NotificationCenter.default.post(name: .waveParameterChanged, object: patch, userInfo: nil)
        dismiss()
    }

    private func commitAllToSet() {
        guard !session.isEmpty else { return }
        let set = PatchSet.create(named: commitSetName.isEmpty ? "Generated Set" : commitSetName,
                                  in: context)
        for (i, entry) in session.enumerated() {
            let newPatch               = Patch(context: context)
            newPatch.uuid              = UUID()
            newPatch.name              = entry.name
            newPatch.category          = patch.category
            newPatch.values            = entry.patchData
            newPatch.rebuildRawSysex(name: entry.name)
            newPatch.dateCreated       = Date()
            newPatch.dateModified      = Date()
            GalaxyEngine.shared.bootstrapLayout(for: newPatch)
            PatchSlot.make(position: i, patch: newPatch, in: set, ctx: context)
        }
        try? context.save()
        applyCurrentEntry()
        dismiss()
    }

    // MARK: - Helpers

    private var currentEntry: GeneratedEntry? {
        session.indices.contains(currentIndex) ? session[currentIndex] : nil
    }

    private var shortDate: String {
        let df = DateFormatter()
        df.dateFormat = "MMM d"
        return df.string(from: Date())
    }
}
