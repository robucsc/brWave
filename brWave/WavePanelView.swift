//
//  WavePanelView.swift
//  brWave
//
//  Main patch panel editor — PPG Wave / Axel Hartmann aesthetic.
//  Two-row layout:
//    Row 1: LFO · MODULATION · WAVES · PITCH ENV
//    Row 2: CONTROLS · FILTER/WAVE ENV · AMP ENV · ROUTING · PERFORMANCE
//
//  All stepped digital params use WaveKnobControl (mini) instead of +/– buttons.
//  Concentric dual arcs show A/B group diff on every per-group knob.
//

import SwiftUI
import AppKit

private struct WavePanelResizeHandleView: NSViewRepresentable {
    let panelID: String
    let naturalSize: CGSize
    let layoutService: WavePanelLayoutService

    func makeCoordinator() -> Coordinator {
        Coordinator(panelID: panelID, layoutService: layoutService)
    }

    func makeNSView(context: Context) -> NSView {
        context.coordinator.naturalSize = naturalSize
        return context.coordinator.handleView
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.naturalSize = naturalSize
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.teardown()
    }

    final class Coordinator {
        let panelID: String
        let layoutService: WavePanelLayoutService
        var naturalSize: CGSize = .zero
        private var dragStartSize: CGSize = .zero
        private var liveDragSize: CGSize = .zero
        private var dragStartPoint: NSPoint = .zero
        private var isDragging = false
        private var monitor: Any?
        let handleView = NSView()

        init(panelID: String, layoutService: WavePanelLayoutService) {
            self.panelID = panelID
            self.layoutService = layoutService
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) {
                [weak self] event in self?.handle(event) ?? event
            }
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            guard handleView.window != nil, handleView.superview != nil else { return event }
            let handleInWindow = handleView.convert(handleView.bounds, to: nil)
            let over = handleInWindow.contains(event.locationInWindow)

            switch event.type {
            case .leftMouseDown where over:
                if event.clickCount == 2 {
                    DispatchQueue.main.async {
                        self.layoutService.resetSectionSize(self.panelID)
                    }
                } else {
                    dragStartSize = layoutService.size(for: panelID) ?? naturalSize
                    liveDragSize = dragStartSize
                    dragStartPoint = event.locationInWindow
                    isDragging = true
                }
                return nil
            case .leftMouseDragged where isDragging:
                let dx = event.locationInWindow.x - dragStartPoint.x
                let dy = -(event.locationInWindow.y - dragStartPoint.y)
                liveDragSize = CGSize(
                    width: max(80, dragStartSize.width + dx),
                    height: max(40, dragStartSize.height + dy)
                )
                DispatchQueue.main.async {
                    self.layoutService.setSectionSizeLive(self.panelID, size: self.liveDragSize)
                }
                return nil
            case .leftMouseUp where isDragging:
                isDragging = false
                DispatchQueue.main.async {
                    self.layoutService.setSectionSize(self.panelID, size: self.liveDragSize)
                }
                return nil
            default:
                return event
            }
        }

        func teardown() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }
}

// MARK: - WavePanelView

struct WavePanelView: View {
    @ObservedObject var patch: Patch

    // Give the top row enough working room to keep tuning-mode controls visible.
    // This is intentionally taller than the previous first-pass minimum.
    private let topRowSectionMinHeight: CGFloat = 340

    @AppStorage("wavePanelGroup") private var selectedGroup: WaveGroup = .a
    @State private var isTuningMode: Bool = false
    @State private var tuningGestureActive = false

    @State private var zoomScale: CGFloat = 1.0
    @State private var lastZoom: CGFloat = 1.0
    @State private var isPinching = false
    @State private var naturalContentSize: CGSize = .zero
    @State private var zoomAnchor: UnitPoint = .center
    @State private var lastMouseLocation: CGPoint = .zero

    @ObservedObject private var layoutService = LayoutOffsetService.shared
    @ObservedObject private var canonicalLayoutService = WavePanelLayoutService.shared

    var body: some View {
        ZStack(alignment: .top) {
            Theme.panelBackground.ignoresSafeArea()

            ScrollView([.horizontal, .vertical]) {
                VStack(alignment: .leading, spacing: 0) {
                    headerRow
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)

                    // ── Row 1: LFO · MODULATION · WAVES · PITCH ENV ─────
                    HStack(alignment: .top, spacing: 20) {
                        lfoSection
                            .frame(width: 220)
                            .frame(minHeight: topRowSectionMinHeight, alignment: .top)
                            .frame(maxHeight: .infinity)
                        modulationSection
                            .frame(width: 220)
                            .frame(minHeight: topRowSectionMinHeight, alignment: .top)
                            .frame(maxHeight: .infinity)
                        wavesSection
                            .frame(width: 220)
                            .frame(minHeight: topRowSectionMinHeight, alignment: .top)
                            .frame(maxHeight: .infinity)
                        pitchEnvSection
                            .frame(width: 220)
                            .frame(minHeight: topRowSectionMinHeight, alignment: .top)
                            .frame(maxHeight: .infinity)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)

                    // ── Row 2: CONTROLS · FILTER+AMP · ROUTING · PERF ───
                    HStack(alignment: .top, spacing: 20) {
                        controlsSection
                            .frame(width: 100)
                            .frame(maxHeight: .infinity)

                        // Filter on top, Amp below — OBsixer pattern
                        VStack(spacing: 20) {
                            filterWaveEnvSection
                                .fixedSize(horizontal: false, vertical: true)
                            ampEnvSection
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(width: 400)
                        .fixedSize(horizontal: false, vertical: true)

                        routingSection
                            .frame(width: 360)
                            .frame(maxHeight: .infinity)

                        performanceSection
                            .frame(maxHeight: .infinity)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 30)
                }
                .background(GeometryReader { geo in
                    Color.clear.onAppear {
                        if naturalContentSize == .zero { naturalContentSize = geo.size }
                    }
                })
                .frame(
                    width:  naturalContentSize == .zero ? nil : naturalContentSize.width,
                    height: naturalContentSize == .zero ? nil : naturalContentSize.height
                )
                .scaleEffect(zoomScale, anchor: zoomAnchor)
                .frame(
                    width:  naturalContentSize == .zero ? nil : naturalContentSize.width  * zoomScale,
                    height: naturalContentSize == .zero ? nil : naturalContentSize.height * zoomScale
                )
            }
            .coordinateSpace(name: "wavePanel")
            .scrollDisabled(isTuningMode)
            .scrollIndicators(.hidden)
            .onPreferenceChange(NudgeFrameKey.self) { frames in
                DispatchQueue.main.async {
                    for (id, frame) in frames { canonicalLayoutService.reportFrame(id, frame) }
                    canonicalLayoutService.migrateLegacyOffsetsIfNeeded(layoutService.offsets)
                }
            }
            .onContinuousHover { phase in
                if case .active(let loc) = phase { lastMouseLocation = loc }
            }
            .gesture(
                MagnificationGesture()
                    .onChanged { val in
                        if !isPinching {
                            isPinching = true
                            let w = max(1, naturalContentSize.width  * zoomScale)
                            let h = max(1, naturalContentSize.height * zoomScale)
                            zoomAnchor = UnitPoint(
                                x: max(0, min(1, lastMouseLocation.x / w)),
                                y: max(0, min(1, lastMouseLocation.y / h))
                            )
                        }
                        zoomScale = max(0.5, min(2.5, val * lastZoom))
                    }
                    .onEnded { _ in isPinching = false; lastZoom = zoomScale }
            )
            .highPriorityGesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("wavePanel"))
                    .onChanged { value in
                        guard isTuningMode else { return }
                        if !tuningGestureActive {
                            tuningGestureActive = true
                            let shift = NSEvent.modifierFlags.contains(.shift)
                            canonicalLayoutService.selectAtPoint(value.startLocation, shift: shift)
                        }
                        guard !canonicalLayoutService.selectedIDs.isEmpty else { return }
                        var translation = value.translation
                        if NSEvent.modifierFlags.contains(.shift) {
                            abs(translation.width) > abs(translation.height)
                                ? (translation.height = 0)
                                : (translation.width = 0)
                        }
                        let grid: CGFloat = 2
                        translation.width = round(translation.width / grid) * grid
                        translation.height = round(translation.height / grid) * grid
                        canonicalLayoutService.updateDrag(delta: translation)
                    }
                    .onEnded { value in
                        guard isTuningMode else { return }
                        tuningGestureActive = false
                        if value.translation.width.magnitude > 3 || value.translation.height.magnitude > 3 {
                            canonicalLayoutService.commitDrag()
                            canonicalLayoutService.flushSaves()
                        } else {
                            canonicalLayoutService.activeDragDelta = .zero
                        }
                    },
                including: isTuningMode ? .all : .subviews
            )
            .onAppear { lastZoom = zoomScale }

            if isTuningMode {
                VStack(spacing: 6) {
                    AlignmentToolbar()
                    TuningSelectionInfo()
                }
                .padding(.top, 56)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .allowsHitTesting(true)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(100)
            }

            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isTuningMode.toggle() }
            } label: {
                Image(systemName: isTuningMode ? "wrench.and.screwdriver.fill" : "wrench.and.screwdriver")
                    .font(.system(size: 15))
                    .foregroundStyle(isTuningMode ? Theme.waveHighlight : Color.secondary)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .background(.ultraThinMaterial, in: Circle())
            .overlay(Circle().stroke(Color.white.opacity(isTuningMode ? 0.4 : 0.12), lineWidth: 1))
            .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .zIndex(200)
        }
        .background(Theme.panelBackground)
        .environment(\.waveControlHighlight, Theme.waveHighlight)
        .environment(\.waveGroupBHighlight, Theme.waveGroupBHighlight)
        .environment(\.waveActiveGroup, selectedGroup)
        .environment(\.isTuningMode, isTuningMode)
        .environment(\.panelZoomScale, zoomScale)
        .environment(\.waveUsesCanonicalLayout, true)
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(spacing: 20) {
            // Patch name prominent, synth model as small subtitle
            VStack(alignment: .leading, spacing: 2) {
                Text(patch.name ?? "Untitled")
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .foregroundStyle(Theme.waveHighlight)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text("WAVE")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.secondary)
                if let designer = patch.designer, !designer.isEmpty {
                    Text(designer)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.secondary.opacity(0.8))
                        .lineLimit(1)
                }
            }

            Spacer()

            // Wavetable
            HStack(spacing: 6) {
                Text("WT").font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary)
                Picker("", selection: Binding(
                    get: { patch.value(for: .wavetb, group: .a) },
                    set: { patch.setValue($0, for: .wavetb, group: .a) }
                )) {
                    ForEach(0...127, id: \.self) { i in Text("\(i)").tag(i) }
                }
                .labelsHidden().pickerStyle(.menu).controlSize(.small)
                .tint(Theme.waveHighlight).frame(width: 50)
            }
            .pillBackground()

            // Keyboard mode
            HStack(spacing: 6) {
                Text("KEYB").font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary)
                Picker("", selection: Binding(
                    get: { patch.value(for: .keyb, group: .a) },
                    set: { patch.setValue($0, for: .keyb, group: .a) }
                )) {
                    ForEach(Array(WaveParamID.keybModeNames.sorted(by: { $0.key < $1.key })), id: \.key) { k, v in
                        Text(v).tag(k)
                    }
                }
                .labelsHidden().pickerStyle(.menu).controlSize(.small)
                .tint(Theme.waveHighlight).frame(width: 90)
            }
            .pillBackground()

            // A/B toggle — each button wears its group's arc colour
            HStack(spacing: 0) {
                let colors: [WaveGroup: Color] = [.a: Theme.waveHighlight, .b: Theme.waveGroupBHighlight]
                ForEach([WaveGroup.a, WaveGroup.b], id: \.rawValue) { g in
                    let c = colors[g] ?? Theme.waveHighlight
                    Button(g.rawValue.uppercased()) { selectedGroup = g }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(selectedGroup == g ? c : c.opacity(0.35))
                        .frame(width: 28, height: 22)
                        .background(selectedGroup == g ? c.opacity(0.18) : Color.clear)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.12), lineWidth: 1))

            if isTuningMode && LayoutOffsetService.shared.hasBackup {
                Button {
                    LayoutOffsetService.shared.restoreBackup()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .foregroundStyle(.green)
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .help("Restore last backup of panel positions and styles")
            }

            if isTuningMode {
                Button {
                    LayoutOffsetService.shared.exportOverridesToClipboard()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundStyle(Theme.waveHighlight)
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .help("Copy layout overrides as source code")
            }

            // Tuning wrench
            Button { isTuningMode.toggle() } label: {
                Image(systemName: "wrench.adjustable")
                    .foregroundStyle(isTuningMode ? Theme.waveHighlight : Color.white.opacity(0.4))
                    .font(.system(size: 15))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 12)
    }

    // MARK: - Row 1 Sections

    private var lfoSection: some View {
        WavePanelSection(title: "LFO", resetIDs: [
            WaveParamID.delay.rawValue, WaveParamID.waveshape.rawValue, WaveParamID.rate.rawValue
        ]) {
            HStack(spacing: 8) {
                WaveKnobControl(patch: patch, id: .delay,     size: Theme.knobSizeSmall, labelOverride: "Delay")
                WaveKnobControl(patch: patch, id: .waveshape, size: Theme.knobSizeSmall, labelOverride: "Shape")
                WaveKnobControl(patch: patch, id: .rate,      size: Theme.knobSizeSmall, labelOverride: "Rate")
            }
        }
    }

    private var modulationSection: some View {
        WavePanelSection(title: "Modulation", resetIDs: [
            WaveParamID.modWhl.rawValue, WaveParamID.env2Loud.rawValue, WaveParamID.env1Waves.rawValue
        ]) {
            HStack(spacing: 8) {
                WaveKnobControl(patch: patch, id: .modWhl,   size: Theme.knobSizeSmall, labelOverride: "Mod W")
                WaveKnobControl(patch: patch, id: .env2Loud, size: Theme.knobSizeSmall, labelOverride: "E2→Vol")
                WaveKnobControl(patch: patch, id: .env1Waves,size: Theme.knobSizeSmall, labelOverride: "E1→WT")
            }
        }
    }

    private var wavesSection: some View {
        WavePanelSection(title: "Waves", resetIDs: [
            WaveParamID.wavesOsc.rawValue, WaveParamID.wavesSub.rawValue
        ]) {
            HStack(spacing: 16) {
                WaveKnobControl(patch: patch, id: .wavesOsc, size: Theme.knobSizeMedium, labelOverride: "OSC")
                WaveKnobControl(patch: patch, id: .wavesSub, size: Theme.knobSizeMedium, labelOverride: "SUB")
            }
        }
    }

    private var pitchEnvSection: some View {
        WavePanelSection(title: "Pitch Env", resetIDs: [
            WaveParamID.attack3.rawValue, WaveParamID.decay3.rawValue, WaveParamID.env3Att.rawValue
        ]) {
            HStack(spacing: 8) {
                WaveKnobControl(patch: patch, id: .attack3, size: Theme.knobSizeSmall, labelOverride: "Att")
                WaveKnobControl(patch: patch, id: .decay3,  size: Theme.knobSizeSmall, labelOverride: "Dec")
                WaveKnobControl(patch: patch, id: .env3Att, size: Theme.knobSizeSmall, labelOverride: "Amt")
            }
        }
    }

    // MARK: - Row 2 Sections

    private var controlsSection: some View {
        WavePanelSection(title: "Controls") {
            VStack(spacing: 12) {
                WaveWheelControl(title: "Pitch", value: .constant(0), isPitch: true)
                WaveWheelControl(title: "Mod",   value: .constant(0), isPitch: false)
            }
        }
    }

    /// OBsixer-style filter: Freq + Res on top, full wave envelope row below.
    /// ENV1→VCF amount sits at the end of the envelope row as "Env Amt".
    private var filterWaveEnvSection: some View {
        WavePanelSection(title: "Filter · Wave Env", resetIDs: [
            WaveParamID.vcfCutoff.rawValue, WaveParamID.vcfEmphasis.rawValue,
            WaveParamID.a1.rawValue, WaveParamID.d1.rawValue, WaveParamID.s1.rawValue,
            WaveParamID.r1.rawValue, WaveParamID.env1VCF.rawValue
        ]) {
            VStack(spacing: 10) {
                // Filter controls
                HStack(spacing: 16) {
                    WaveKnobControl(patch: patch, id: .vcfCutoff,   size: Theme.knobSizeMedium, labelOverride: "Freq")
                    WaveKnobControl(patch: patch, id: .vcfEmphasis, size: Theme.knobSizeMedium, labelOverride: "Res")
                }
                // Wave Env (Env 1) + filter routing amount
                HStack(spacing: 8) {
                    WaveKnobControl(patch: patch, id: .a1,       size: Theme.knobSizeSmall, labelOverride: "Att")
                    WaveKnobControl(patch: patch, id: .d1,       size: Theme.knobSizeSmall, labelOverride: "Dec")
                    WaveKnobControl(patch: patch, id: .s1,       size: Theme.knobSizeSmall, labelOverride: "Sus")
                    WaveKnobControl(patch: patch, id: .r1,       size: Theme.knobSizeSmall, labelOverride: "Rel")
                    WaveKnobControl(patch: patch, id: .env1VCF,  size: Theme.knobSizeSmall, labelOverride: "Env→F")
                }
            }
        }
    }

    private var ampEnvSection: some View {
        WavePanelSection(title: "Amp Env", resetIDs: [
            WaveParamID.a2.rawValue, WaveParamID.d2.rawValue, WaveParamID.s2.rawValue, WaveParamID.r2.rawValue
        ]) {
            HStack(spacing: 8) {
                WaveKnobControl(patch: patch, id: .a2, size: Theme.knobSizeSmall, labelOverride: "Att")
                WaveKnobControl(patch: patch, id: .d2, size: Theme.knobSizeSmall, labelOverride: "Dec")
                WaveKnobControl(patch: patch, id: .s2, size: Theme.knobSizeSmall, labelOverride: "Sus")
                WaveKnobControl(patch: patch, id: .r2, size: Theme.knobSizeSmall, labelOverride: "Rel")
            }
        }
    }

    /// All routing matrices — key, mod wheel, velocity, touch — using mini knobs.
    private var routingSection: some View {
        WavePanelSection(title: "Routing", resetIDs: [
            WaveParamID.kw.rawValue, WaveParamID.kf.rawValue, WaveParamID.kl.rawValue,
            WaveParamID.mw.rawValue, WaveParamID.mf.rawValue, WaveParamID.ml.rawValue,
            WaveParamID.vf.rawValue, WaveParamID.vl.rawValue,
            WaveParamID.tw.rawValue, WaveParamID.tf.rawValue, WaveParamID.tl.rawValue, WaveParamID.tm.rawValue
        ]) {
            HStack(alignment: .top, spacing: 16) {
                // Key tracking
                VStack(alignment: .leading, spacing: 8) {
                    sectionLabel("Key Track")
                    WaveKnobControl(patch: patch, id: .kw, size: Theme.knobSizeMini, labelOverride: "→Wave")
                    WaveKnobControl(patch: patch, id: .kf, size: Theme.knobSizeMini, labelOverride: "→Filt")
                    WaveKnobControl(patch: patch, id: .kl, size: Theme.knobSizeMini, labelOverride: "→Loud")
                }

                // Mod wheel
                VStack(alignment: .leading, spacing: 8) {
                    sectionLabel("Mod Wheel")
                    WaveKnobControl(patch: patch, id: .mw, size: Theme.knobSizeMini, labelOverride: "→Wave")
                    WaveKnobControl(patch: patch, id: .mf, size: Theme.knobSizeMini, labelOverride: "→Filt")
                    WaveLEDToggle(patch: patch, id: .ml, label: "→Loud")
                }

                // Velocity
                VStack(alignment: .leading, spacing: 8) {
                    sectionLabel("Velocity")
                    WaveKnobControl(patch: patch, id: .vf, size: Theme.knobSizeMini, labelOverride: "→Filt")
                    WaveKnobControl(patch: patch, id: .vl, size: Theme.knobSizeMini, labelOverride: "→Loud")
                }

                // Touch / aftertouch
                VStack(alignment: .leading, spacing: 8) {
                    sectionLabel("Touch")
                    WaveKnobControl(patch: patch, id: .tw, size: Theme.knobSizeMini, labelOverride: "→Wave")
                    WaveKnobControl(patch: patch, id: .tf, size: Theme.knobSizeMini, labelOverride: "→Filt")
                    WaveKnobControl(patch: patch, id: .tl, size: Theme.knobSizeMini, labelOverride: "→Loud")
                    WaveLEDToggle(patch: patch, id: .tm, label: "→Wheel")
                }
            }
        }
    }

    /// Oscillator config, bender, tuning, and voice semitone offsets.
    private var performanceSection: some View {
        WavePanelSection(title: "Performance", resetIDs: [
            WaveParamID.uw.rawValue, WaveParamID.sw.rawValue,
            WaveParamID.bd.rawValue, WaveParamID.bi.rawValue,
            WaveParamID.detu.rawValue, WaveParamID.eo.rawValue,
            WaveParamID.mo.rawValue, WaveParamID.ms.rawValue, WaveParamID.es.rawValue,
            WaveParamID.semitV1.rawValue, WaveParamID.semitV2.rawValue, WaveParamID.semitV3.rawValue, WaveParamID.semitV4.rawValue,
            WaveParamID.semitV5.rawValue, WaveParamID.semitV6.rawValue, WaveParamID.semitV7.rawValue, WaveParamID.semitV8.rawValue
        ]) {
            HStack(alignment: .top, spacing: 16) {
                // Oscillator config
                VStack(alignment: .leading, spacing: 8) {
                    sectionLabel("Oscillator")
                    WaveLEDRadio(patch: patch, id: .uw,
                                 options: ["128", "2048", "8192"],
                                 label: "Upper WT")
                    WaveLEDRadio(patch: patch, id: .sw,
                                 options: ["Off", "-1oct", "-2oct", "-3oct", "Sine", "Pulse", "Tri"],
                                 label: "Sub Osc")
                }

                // Bender
                VStack(alignment: .leading, spacing: 8) {
                    sectionLabel("Bender")
                    WaveLEDRadio(patch: patch, id: .bd,
                                 options: ["Off", "Wave", "Pitch", "Filt", "Loud", "All"],
                                 label: "Dest")
                    WaveKnobControl(patch: patch, id: .bi, size: Theme.knobSizeMini, labelOverride: "Int")
                }

                // Tuning
                VStack(alignment: .leading, spacing: 8) {
                    sectionLabel("Tuning")
                    WaveKnobControl(patch: patch, id: .detu, size: Theme.knobSizeMini, labelOverride: "Detune")
                    WaveKnobControl(patch: patch, id: .eo,   size: Theme.knobSizeMini, labelOverride: "E3→Main")
                    WaveLEDToggle(patch: patch, id: .mo, label: "M→Main")
                    WaveLEDToggle(patch: patch, id: .ms, label: "M→Sub")
                    WaveLEDToggle(patch: patch, id: .es, label: "E3→Sub")
                }

                // Voice semi offsets — 2×4 mini knob grid
                VStack(alignment: .leading, spacing: 8) {
                    sectionLabel("Voice Tuning")
                    let pairs: [(WaveParamID, String)] = [
                        (.semitV1, "V1"), (.semitV2, "V2"),
                        (.semitV3, "V3"), (.semitV4, "V4"),
                        (.semitV5, "V5"), (.semitV6, "V6"),
                        (.semitV7, "V7"), (.semitV8, "V8"),
                    ]
                    LazyVGrid(columns: [GridItem(.fixed(52)), GridItem(.fixed(52))], spacing: 6) {
                        ForEach(pairs, id: \.0.rawValue) { id, lbl in
                            WaveKnobControl(patch: patch, id: id, size: Theme.knobSizeMini, labelOverride: lbl)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 8, weight: .bold))
            .tracking(0.8)
            .foregroundStyle(Color.white.opacity(0.3))
    }
}

// MARK: - Pill background helper

private extension View {
    func pillBackground() -> some View {
        self
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

// MARK: - WavePanelSection

struct WavePanelSection<Content: View>: View {
    let title: String
    var resetIDs: [String] = []
    @ViewBuilder let content: () -> Content

    private let accent = Theme.xrAccentBlue
    @Environment(\.isTuningMode) private var isTuningMode
    @ObservedObject private var offsetService = LayoutOffsetService.shared
    @ObservedObject private var canonicalLayoutService = WavePanelLayoutService.shared
    @State private var currentNaturalSize: CGSize = .zero

    var body: some View {
        let storedSize = canonicalLayoutService.size(for: title)

        VStack(alignment: .leading, spacing: 0) {
            // Title bar: solid accent left block, title text, accent fill to right edge
            HStack(spacing: 0) {
                Rectangle()
                    .fill(accent)
                    .frame(width: 10, height: 14)
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.0)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                if isTuningMode && !resetIDs.isEmpty {
                    Button {
                        offsetService.resetIDs(resetIDs)
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 9))
                            .foregroundStyle(Color.orange.opacity(0.9))
                    }
                    .buttonStyle(.plain)
                    .help("Reset \(title) positions")
                    .padding(.trailing, 6)
                }
                Rectangle()
                    .fill(accent)
                    .frame(maxWidth: .infinity, maxHeight: 14)
            }
            .fixedSize(horizontal: false, vertical: true)

            ZStack(alignment: .bottomTrailing) {
                content()
                    .padding(16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                if isTuningMode {
                    ZStack {
                        WavePanelResizeHandleView(
                            panelID: title,
                            naturalSize: currentNaturalSize,
                            layoutService: canonicalLayoutService
                        )
                        Image(systemName: "arrow.down.right.and.arrow.up.left")
                            .font(.system(size: 9))
                            .foregroundStyle(accent.opacity(0.9))
                            .allowsHitTesting(false)
                    }
                    .frame(width: 20, height: 20)
                    .background(Color.black.opacity(0.55))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .padding(4)
                    .help("Drag to resize. Double-click to reset.")
                }
            }
            .if(storedSize != nil) { $0.frame(width: storedSize!.width, height: storedSize!.height) }
            .background(
                GeometryReader { geo in
                    Theme.xrSectionBackground
                        .onAppear {
                            currentNaturalSize = geo.size
                            canonicalLayoutService.seedSectionSizeIfNeeded(title, size: geo.size)
                        }
                        .onChange(of: geo.size) { _, size in
                            currentNaturalSize = size
                            canonicalLayoutService.seedSectionSizeIfNeeded(title, size: size)
                        }
                }
            )
        }
        .if(!isTuningMode) { $0.clipShape(RoundedRectangle(cornerRadius: 2)) }
        .overlay(RoundedRectangle(cornerRadius: 2).stroke(accent.opacity(0.35), lineWidth: 1))
    }
}

struct TuningSelectionInfo: View {
    @ObservedObject private var service = LayoutOffsetService.shared
    @ObservedObject private var canonicalLayoutService = WavePanelLayoutService.shared
    @Environment(\.waveUsesCanonicalLayout) private var waveUsesCanonicalLayout

    var body: some View {
        let ids = Array(waveUsesCanonicalLayout ? canonicalLayoutService.selectedIDs : service.selectedIDs)
        if ids.isEmpty { return AnyView(EmptyView()) }

        return AnyView(
            Group {
                if ids.count == 1 {
                    singleItemChip(id: ids[0])
                } else {
                    multiChip(count: ids.count)
                }
            }
        )
    }

    private func singleItemChip(id: String) -> some View {
        let descriptor = WaveParamID(rawValue: id).flatMap { WaveParameters.byID[$0] }
        let offset = waveUsesCanonicalLayout
            ? canonicalLayoutService.origin(for: id).map { CGSize(width: $0.x, height: $0.y) } ?? .zero
            : service.offset(for: id)

        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                if let d = descriptor {
                    Text(d.displayName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(d.group.rawValue.uppercased())
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.waveHighlight)
                } else {
                    Text(id)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.primary)
                    Text("LAYOUT ITEM")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.secondary)
                }
            }

            if offset != .zero {
                Divider().frame(height: 20)
                Text("x \(Int(offset.width))  y \(Int(offset.height))")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Color.secondary)
            }

            Divider().frame(height: 20)
            Button("Reset") {
                if waveUsesCanonicalLayout {
                    canonicalLayoutService.resetControlPosition(id)
                } else {
                    service.resetOffset(id)
                }
                service.resetStyle(id)
            }
            .font(.system(size: 10))
            .foregroundStyle(Theme.waveHighlight)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.82))
                .overlay(Capsule().strokeBorder(Theme.waveHighlight.opacity(0.35), lineWidth: 1))
        )
        .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2)
    }

    private func multiChip(count: Int) -> some View {
        Text("\(count) items selected")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Color.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.75))
                    .overlay(Capsule().strokeBorder(Theme.waveHighlight.opacity(0.25), lineWidth: 1))
            )
    }
}
