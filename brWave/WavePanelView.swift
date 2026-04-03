//
//  WavePanelView.swift
//  brWave
//
//  Main patch panel editor — PPG Wave / Axel Hartmann aesthetic.
//  Two-row layout:
//    Row 1: LFO · MODULATION · WAVES · PITCH ENV
//    Row 2: CONTROLS · FILTER · WAVE ENV · AMP ENV · ROUTING · PERFORMANCE
//
//  All stepped digital params use WaveKnobControl (mini) instead of +/– buttons.
//  Concentric dual arcs show A/B group diff on every per-group knob.
//

import SwiftUI

// MARK: - WavePanelView

struct WavePanelView: View {
    @ObservedObject var patch: Patch

    @AppStorage("wavePanelGroup") private var selectedGroup: WaveGroup = .a
    @State private var isTuningMode: Bool = false

    @State private var zoomScale: CGFloat = 1.0
    @State private var lastZoom: CGFloat = 1.0
    @State private var isPinching = false
    @State private var naturalContentSize: CGSize = .zero
    @State private var zoomAnchor: UnitPoint = .center
    @State private var lastMouseLocation: CGPoint = .zero
    @State private var tuningDragStart: CGPoint = .zero

    @ObservedObject private var layoutService = LayoutOffsetService.shared

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
                            .frame(maxHeight: .infinity)
                        modulationSection
                            .frame(width: 220)
                            .frame(maxHeight: .infinity)
                        wavesPitchSection
                            .frame(width: 270)
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
            .scrollIndicators(.hidden)
            .onPreferenceChange(NudgeFrameKey.self) { frames in
                DispatchQueue.main.async {
                    for (id, frame) in frames { layoutService.reportFrame(id, frame) }
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
            .if(isTuningMode) { view in
                view.gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { drag in
                            if drag.translation == .zero {
                                let shift = NSEvent.modifierFlags.contains(.shift)
                                layoutService.selectAtPoint(drag.location, shift: shift)
                                tuningDragStart = drag.location
                            } else {
                                layoutService.updateDrag(delta: drag.translation)
                            }
                        }
                        .onEnded { _ in layoutService.commitDrag() }
                )
            }
            .onAppear { lastZoom = zoomScale }

            if isTuningMode {
                AlignmentToolbar()
                    .padding(.top, 56)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .allowsHitTesting(true)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(100)
            }
        }
        .background(Theme.panelBackground)
        .environment(\.waveControlHighlight, Theme.waveHighlight)
        .environment(\.waveGroupBHighlight, Theme.waveGroupBHighlight)
        .environment(\.waveActiveGroup, selectedGroup)
        .environment(\.isTuningMode, isTuningMode)
        .environment(\.panelZoomScale, zoomScale)
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(spacing: 20) {
            // Patch name prominent, synth model as small subtitle
            VStack(alignment: .leading, spacing: 2) {
                Text((patch.name ?? "Untitled").uppercased())
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundStyle(Theme.waveHighlight)
                Text("WAVE")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.secondary)
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
        WavePanelSection(title: "LFO") {
            HStack(spacing: 8) {
                WaveKnobControl(patch: patch, id: .delay,     size: Theme.knobSizeSmall, labelOverride: "Delay")
                WaveKnobControl(patch: patch, id: .waveshape, size: Theme.knobSizeSmall, labelOverride: "Shape")
                WaveKnobControl(patch: patch, id: .rate,      size: Theme.knobSizeSmall, labelOverride: "Rate")
            }
        }
    }

    private var modulationSection: some View {
        WavePanelSection(title: "Modulation") {
            HStack(spacing: 8) {
                WaveKnobControl(patch: patch, id: .modWhl,   size: Theme.knobSizeSmall, labelOverride: "Mod W")
                WaveKnobControl(patch: patch, id: .env2Loud, size: Theme.knobSizeSmall, labelOverride: "E2→Vol")
                WaveKnobControl(patch: patch, id: .env1Waves,size: Theme.knobSizeSmall, labelOverride: "E1→WT")
            }
        }
    }

    private var wavesPitchSection: some View {
        WavePanelSection(title: "Waves · Pitch Env") {
            VStack(spacing: 10) {
                // Wave table positions — the signature PPG params
                HStack(spacing: 16) {
                    WaveKnobControl(patch: patch, id: .wavesOsc, size: Theme.knobSizeMedium, labelOverride: "OSC")
                    WaveKnobControl(patch: patch, id: .wavesSub, size: Theme.knobSizeMedium, labelOverride: "SUB")
                }
                panelDivider
                // Env 3 — Pitch
                HStack(spacing: 8) {
                    WaveKnobControl(patch: patch, id: .attack3, size: Theme.knobSizeSmall, labelOverride: "Att")
                    WaveKnobControl(patch: patch, id: .decay3,  size: Theme.knobSizeSmall, labelOverride: "Dec")
                    WaveKnobControl(patch: patch, id: .env3Att, size: Theme.knobSizeSmall, labelOverride: "Amt")
                }
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
        WavePanelSection(title: "Filter · Wave Env") {
            VStack(spacing: 10) {
                // Filter controls
                HStack(spacing: 16) {
                    WaveKnobControl(patch: patch, id: .vcfCutoff,   size: Theme.knobSizeMedium, labelOverride: "Freq")
                    WaveKnobControl(patch: patch, id: .vcfEmphasis, size: Theme.knobSizeMedium, labelOverride: "Res")
                }
                panelDivider
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
        WavePanelSection(title: "Amp Env") {
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
        WavePanelSection(title: "Routing") {
            HStack(alignment: .top, spacing: 16) {
                // Key tracking
                VStack(alignment: .leading, spacing: 8) {
                    sectionLabel("Key Track")
                    WaveKnobControl(patch: patch, id: .kw, size: Theme.knobSizeMini, labelOverride: "→Wave")
                    WaveKnobControl(patch: patch, id: .kf, size: Theme.knobSizeMini, labelOverride: "→Filt")
                    WaveKnobControl(patch: patch, id: .kl, size: Theme.knobSizeMini, labelOverride: "→Loud")
                }

                sectionDivider

                // Mod wheel
                VStack(alignment: .leading, spacing: 8) {
                    sectionLabel("Mod Wheel")
                    WaveKnobControl(patch: patch, id: .mw, size: Theme.knobSizeMini, labelOverride: "→Wave")
                    WaveKnobControl(patch: patch, id: .mf, size: Theme.knobSizeMini, labelOverride: "→Filt")
                    WaveLEDToggle(patch: patch, id: .ml, label: "→Loud")
                }

                sectionDivider

                // Velocity
                VStack(alignment: .leading, spacing: 8) {
                    sectionLabel("Velocity")
                    WaveKnobControl(patch: patch, id: .vf, size: Theme.knobSizeMini, labelOverride: "→Filt")
                    WaveKnobControl(patch: patch, id: .vl, size: Theme.knobSizeMini, labelOverride: "→Loud")
                }

                sectionDivider

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
        WavePanelSection(title: "Performance") {
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

                sectionDivider

                // Bender
                VStack(alignment: .leading, spacing: 8) {
                    sectionLabel("Bender")
                    WaveLEDRadio(patch: patch, id: .bd,
                                 options: ["Off", "Wave", "Pitch", "Filt", "Loud", "All"],
                                 label: "Dest")
                    WaveKnobControl(patch: patch, id: .bi, size: Theme.knobSizeMini, labelOverride: "Int")
                }

                sectionDivider

                // Tuning
                VStack(alignment: .leading, spacing: 8) {
                    sectionLabel("Tuning")
                    WaveKnobControl(patch: patch, id: .detu, size: Theme.knobSizeMini, labelOverride: "Detune")
                    WaveKnobControl(patch: patch, id: .eo,   size: Theme.knobSizeMini, labelOverride: "E3→Main")
                    WaveLEDToggle(patch: patch, id: .mo, label: "M→Main")
                    WaveLEDToggle(patch: patch, id: .ms, label: "M→Sub")
                    WaveLEDToggle(patch: patch, id: .es, label: "E3→Sub")
                }

                sectionDivider

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

    private var panelDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.07))
            .frame(height: 1)
    }

    private var sectionDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.07))
            .frame(width: 1)
            .padding(.vertical, 4)
    }

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
    @ViewBuilder let content: () -> Content

    private let accent = Theme.xrAccentBlue

    var body: some View {
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
                Rectangle()
                    .fill(accent)
                    .frame(maxWidth: .infinity, maxHeight: 14)
            }
            .fixedSize(horizontal: false, vertical: true)

            content()
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Theme.xrSectionBackground)
        }
        .clipShape(RoundedRectangle(cornerRadius: 2))
        .overlay(RoundedRectangle(cornerRadius: 2).stroke(accent.opacity(0.35), lineWidth: 1))
    }
}
