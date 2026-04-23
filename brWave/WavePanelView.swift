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
                    self.layoutService.setPanelSizeLive(self.panelID, size: self.liveDragSize)
                }
                return nil
            case .leftMouseUp where isDragging:
                isDragging = false
                DispatchQueue.main.async {
                    self.layoutService.setPanelSize(self.panelID, size: self.liveDragSize)
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

    @AppStorage("wavePanelGroup") private var selectedGroup: WaveGroup = .a
    @State private var isTuningMode: Bool = false
    @State private var tuningGestureActive = false

    @State private var zoomScale: CGFloat = 1.0
    @State private var lastZoom: CGFloat = 1.0
    @State private var isPinching = false
    @State private var naturalContentSize: CGSize = .zero
    @State private var zoomAnchor: UnitPoint = .center
    @State private var lastMouseLocation: CGPoint = .zero
    @State private var pitchWheelValue: Double = 0
    @State private var modWheelValue: Double = 0
    @State private var showFilterEnvGraph = false
    @State private var showAmpEnvGraph = false
    @State private var showPitchEnvGraph = false
    @State private var selectedWavetableHandle: WaveWavetableHandle = .osc
    @FocusState private var panelEditorFocused: Bool

    @ObservedObject private var canonicalLayoutService = WavePanelLayoutService.shared

    var body: some View {
        ZStack(alignment: .top) {
            Theme.panelBackground.ignoresSafeArea()

            ScrollView([.horizontal, .vertical]) {
                VStack(alignment: .leading, spacing: 0) {
                    headerRow
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)

                    panelCanvas
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
                .coordinateSpace(name: "wavePanel")
                .scaleEffect(zoomScale, anchor: zoomAnchor)
                .frame(
                    width:  naturalContentSize == .zero ? nil : naturalContentSize.width  * zoomScale,
                    height: naturalContentSize == .zero ? nil : naturalContentSize.height * zoomScale
                )
            }
            .scrollDisabled(false)
            .scrollIndicators(.hidden)
            .focusable()
            .focused($panelEditorFocused)
            .onPreferenceChange(NudgeFrameKey.self) { frames in
                DispatchQueue.main.async {
                    for (id, frame) in frames { canonicalLayoutService.reportFrame(id, frame) }
                    canonicalLayoutService.seedControlFramesIfNeeded()
                }
            }
            .onContinuousHover { phase in
                if case .active(let loc) = phase { lastMouseLocation = loc }
            }
            .onTapGesture {
                panelEditorFocused = true
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
            .onAppear {
                lastZoom = zoomScale
                panelEditorFocused = true
            }

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
        .onChange(of: isTuningMode) { _, isActive in
            if !isActive {
                canonicalLayoutService.clearSelection()
            }
        }
        .onKeyPress(.tab) {
            guard isTuningMode else { return .ignored }
            canonicalLayoutService.selectNext()
            return .handled
        }
    }

    private var panelCanvas: some View {
        ZStack(alignment: .topLeading) {
            panelSection("LFO", fallback: defaultPanelFrame(for: "LFO")) { lfoSection }
            panelSection("Modulation", fallback: defaultPanelFrame(for: "Modulation")) { modulationSection }
            panelSection("Waves", fallback: defaultPanelFrame(for: "Waves")) { wavesSection }
            panelSection("Wheels", fallback: defaultPanelFrame(for: "Wheels")) { controlsSection }
            panelSection("Filter · Wave Env", fallback: defaultPanelFrame(for: "Filter · Wave Env")) { filterWaveEnvSection }
            panelSection("Amp Env", fallback: defaultPanelFrame(for: "Amp Env")) { ampEnvSection }
            panelSection("Pitch Env", fallback: defaultPanelFrame(for: "Pitch Env")) { pitchEnvSection }
            panelSection("Routing", fallback: defaultPanelFrame(for: "Routing")) { routingSection }
            panelSection("Performance", fallback: defaultPanelFrame(for: "Performance")) { performanceSection }
        }
        .frame(width: panelCanvasSize.width, height: panelCanvasSize.height, alignment: .topLeading)
    }

    private func panelSection<Content: View>(
        _ title: String,
        fallback: CGRect,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let frame = resolvedPanelFrame(for: title, fallback: fallback)
        return content()
            .frame(width: frame.width, height: frame.height, alignment: .topLeading)
            .position(x: frame.minX + (frame.width / 2), y: frame.minY + (frame.height / 2))
            .onAppear {
                canonicalLayoutService.seedPanelFrameIfNeeded(title, frame: frame)
            }
    }

    private func resolvedPanelFrame(for title: String, fallback: CGRect) -> CGRect {
        guard let stored = canonicalLayoutService.panelFrame(for: title) else {
            if let legacySize = canonicalLayoutService.size(for: title) {
                let minimum = sectionMinimumSize(for: title)
                return CGRect(
                    origin: fallback.origin,
                    size: CGSize(
                        width: max(minimum.width, legacySize.width),
                        height: max(minimum.height, legacySize.height)
                    )
                )
            }
            return fallback
        }
        let minimum = sectionMinimumSize(for: title)
        let width = max(minimum.width, stored.width > 0 ? stored.width : fallback.width)
        let height = max(minimum.height, stored.height > 0 ? stored.height : fallback.height)
        return CGRect(origin: stored.origin, size: CGSize(width: width, height: height))
    }

    private var panelCanvasSize: CGSize {
        let frames = [
            resolvedPanelFrame(for: "LFO", fallback: defaultPanelFrame(for: "LFO")),
            resolvedPanelFrame(for: "Modulation", fallback: defaultPanelFrame(for: "Modulation")),
            resolvedPanelFrame(for: "Waves", fallback: defaultPanelFrame(for: "Waves")),
            resolvedPanelFrame(for: "Wheels", fallback: defaultPanelFrame(for: "Wheels")),
            resolvedPanelFrame(for: "Filter · Wave Env", fallback: defaultPanelFrame(for: "Filter · Wave Env")),
            resolvedPanelFrame(for: "Amp Env", fallback: defaultPanelFrame(for: "Amp Env")),
            resolvedPanelFrame(for: "Pitch Env", fallback: defaultPanelFrame(for: "Pitch Env")),
            resolvedPanelFrame(for: "Routing", fallback: defaultPanelFrame(for: "Routing")),
            resolvedPanelFrame(for: "Performance", fallback: defaultPanelFrame(for: "Performance"))
        ]
        let maxX = frames.map(\.maxX).max() ?? 0
        let maxY = frames.map(\.maxY).max() ?? 0
        return CGSize(width: maxX + 20, height: maxY + 20)
    }

    private func defaultPanelFrame(for title: String) -> CGRect {
        switch title {
        case "LFO":
            return CGRect(x: 0, y: 0, width: 220, height: 204)
        case "Modulation":
            return CGRect(x: 240, y: 0, width: 220, height: 134)
        case "Waves":
            return CGRect(x: 480, y: 0, width: 275, height: 614)
        case "Wheels":
            return CGRect(x: 0, y: 224, width: 120, height: 314)
        case "Filter · Wave Env":
            return CGRect(x: 140, y: 224, width: 520, height: 258)
        case "Amp Env":
            return CGRect(x: 140, y: 502, width: 520, height: 258)
        case "Pitch Env":
            return CGRect(x: 680, y: 224, width: 520, height: 258)
        case "Routing":
            return CGRect(x: 680, y: 502, width: 520, height: 264)
        case "Performance":
            return CGRect(x: 1220, y: 224, width: 380, height: 334)
        default:
            return CGRect(x: 0, y: 0, width: 160, height: 120)
        }
    }

    private func sectionMinimumSize(for title: String) -> CGSize {
        switch title {
        case "LFO":
            return CGSize(width: 160, height: 130)
        case "Modulation":
            return CGSize(width: 160, height: 100)
        case "Waves":
            return CGSize(width: 240, height: 360)
        case "Wheels":
            return CGSize(width: 90, height: 180)
        case "Filter · Wave Env", "Amp Env", "Pitch Env":
            return CGSize(width: 320, height: 140)
        case "Routing":
            return CGSize(width: 320, height: 160)
        case "Performance":
            return CGSize(width: 280, height: 220)
        default:
            return CGSize(width: 120, height: 80)
        }
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

            headerControls
        }
        .padding(.vertical, 12)
    }

    private var headerControls: some View {
        HStack(spacing: 14) {
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

            if isTuningMode {
                Button {
                    canonicalLayoutService.exportToClipboard()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundStyle(Theme.waveHighlight)
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .help("Copy layout overrides as source code")
            }

            Button { isTuningMode.toggle() } label: {
                Image(systemName: "wrench.adjustable")
                    .foregroundStyle(isTuningMode ? Theme.waveHighlight : Color.white.opacity(0.4))
                    .font(.system(size: 15))
            }
            .buttonStyle(.plain)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    // MARK: - Row 1 Sections

    private var lfoSection: some View {
        WavePanelSection(title: "LFO", resetIDs: [
            WaveParamID.delay.rawValue, WaveParamID.waveshape.rawValue, WaveParamID.rate.rawValue, "lfo.graph"
        ]) {
            WaveSectionCanvas(height: 190) {
                WaveControlSlot(id: WaveParamID.delay.rawValue, sectionID: "LFO", naturalFrame: CGRect(x: 8, y: 8, width: 62, height: 112)) {
                    WaveKnobControl(patch: patch, id: .delay, size: Theme.knobSizeSmall, labelOverride: "Delay")
                }
                WaveControlSlot(id: WaveParamID.rate.rawValue, sectionID: "LFO", naturalFrame: CGRect(x: 74, y: 8, width: 62, height: 112)) {
                    WaveKnobControl(patch: patch, id: .rate, size: Theme.knobSizeSmall, labelOverride: "Rate")
                }
                WaveControlSlot(id: WaveParamID.waveshape.rawValue, sectionID: "LFO", naturalFrame: CGRect(x: 140, y: 18, width: 62, height: 66)) {
                    WaveLFOShapeSelector(patch: patch)
                        .nudgeable(id: WaveParamID.waveshape.rawValue, controlType: .menu)
                }
                WaveControlSlot(id: "lfo.graph", sectionID: "LFO", naturalFrame: CGRect(x: 8, y: 116, width: 188, height: 56)) {
                    WaveLFOGraphic(
                        delay: patch.value(for: .delay, group: selectedGroup),
                        shape: patch.value(for: .waveshape, group: selectedGroup),
                        rate: patch.value(for: .rate, group: selectedGroup)
                    )
                    .nudgeable(id: "lfo.graph", controlType: .label)
                }
            }
        }
    }

    private var modulationSection: some View {
        WavePanelSection(title: "Modulation", resetIDs: [
            WaveParamID.modWhl.rawValue, "mod.env2Loud", WaveParamID.env1Waves.rawValue
        ]) {
            WaveSectionCanvas(height: 120) {
                WaveControlSlot(id: WaveParamID.modWhl.rawValue, sectionID: "Modulation", naturalFrame: CGRect(x: 8, y: 8, width: 62, height: 112)) {
                    WaveKnobControl(patch: patch, id: .modWhl, size: Theme.knobSizeSmall, labelOverride: "Mod W")
                }
                WaveControlSlot(id: "mod.env2Loud", sectionID: "Modulation", naturalFrame: CGRect(x: 74, y: 8, width: 62, height: 112)) {
                    WaveKnobControl(patch: patch, id: .env2Loud, size: Theme.knobSizeSmall, labelOverride: "E2→Vol", nudgeIDOverride: "mod.env2Loud")
                }
                WaveControlSlot(id: WaveParamID.env1Waves.rawValue, sectionID: "Modulation", naturalFrame: CGRect(x: 140, y: 8, width: 62, height: 112)) {
                    WaveKnobControl(patch: patch, id: .env1Waves, size: Theme.knobSizeSmall, labelOverride: "E1→WT")
                }
            }
        }
    }

    private var wavesSection: some View {
        WavePanelSection(title: "Waves", resetIDs: [
            WaveParamID.wavesOsc.rawValue, WaveParamID.wavesSub.rawValue, WaveParamID.wavetb.rawValue, "waves.plot", "waves.selector"
        ]) {
            WaveSectionCanvas(height: 600) {
                WaveControlSlot(id: "waves.plot", sectionID: "Waves", naturalFrame: CGRect(x: 8, y: 8, width: 256, height: 128)) {
                    WaveWavetablePlot(
                        patch: patch,
                        tableIndex: currentLocalWavetableIndex,
                        selectedHandle: $selectedWavetableHandle
                    )
                }
                WaveControlSlot(id: WaveParamID.wavesOsc.rawValue, sectionID: "Waves", naturalFrame: CGRect(x: 18, y: 160, width: 78, height: 124)) {
                    WaveKnobControl(patch: patch, id: .wavesOsc, size: Theme.knobSizeMedium, labelOverride: "OSC")
                }
                WaveControlSlot(id: WaveParamID.wavesSub.rawValue, sectionID: "Waves", naturalFrame: CGRect(x: 132, y: 202, width: 62, height: 112)) {
                    WaveKnobControl(patch: patch, id: .wavesSub, size: Theme.knobSizeSmall, labelOverride: "SUB")
                }
                WaveControlSlot(id: WaveParamID.wavetb.rawValue, sectionID: "Waves", naturalFrame: CGRect(x: 18, y: 312, width: 78, height: 112)) {
                    WaveKnobControl(
                        patch: patch,
                        id: .wavetb,
                        size: Theme.knobSizeMedium,
                        labelOverride: "WAVE",
                        valueTextOverride: WaveTables.slotDisplayName(for: currentWavetableSlot)
                    )
                }
                WaveControlSlot(id: "waves.selector", sectionID: "Waves", naturalFrame: CGRect(x: 78, y: 442, width: 150, height: 52)) {
                    WaveWavetableSelectorLauncher(
                        patch: patch,
                        tableIndex: currentLocalWavetableIndex,
                        previewCycle: firstPreviewCycle
                    )
                }
            }
        }
    }

    private var currentWavetableSlot: Int {
        patch.value(for: .wavetb, group: selectedGroup)
    }

    private var currentLocalWavetableIndex: Int? {
        WaveTables.localTableIndex(forSlot: currentWavetableSlot)
    }

    private var currentOscCycle: Int {
        let raw = patch.value(for: .wavesOsc, group: selectedGroup)
        guard let tableIndex = currentLocalWavetableIndex else { return 0 }
        return WaveTables.cycleIndex(forParameterValue: raw, in: tableIndex)
    }

    private var canonicalPreviewCycle: Int {
        let cycleCount = WaveTables.waveTables.first?.count ?? 1
        return max(0, cycleCount - 1)
    }

    private var firstPreviewCycle: Int { 0 }

    private var pitchEnvSection: some View {
        WavePanelSection(title: "Pitch Env", resetIDs: [
            WaveParamID.attack3.rawValue, WaveParamID.decay3.rawValue, WaveParamID.env3Att.rawValue,
            "env.pitch.graph", "env.pitch.mode"
        ]) {
            WaveSectionCanvas(height: 244) {
                WaveControlSlot(id: WaveParamID.attack3.rawValue, sectionID: "Pitch Env", naturalFrame: CGRect(x: 12, y: 142, width: 52, height: 86)) {
                    WaveKnobControl(patch: patch, id: .attack3, size: Theme.knobSizeSmall, labelOverride: "Attack")
                        .opacity(showPitchEnvGraph ? 0 : 1)
                }
                WaveControlSlot(id: WaveParamID.decay3.rawValue, sectionID: "Pitch Env", naturalFrame: CGRect(x: 84, y: 142, width: 52, height: 86)) {
                    WaveKnobControl(patch: patch, id: .decay3, size: Theme.knobSizeSmall, labelOverride: "Decay")
                        .opacity(showPitchEnvGraph ? 0 : 1)
                }
                WaveControlSlot(id: WaveParamID.env3Att.rawValue, sectionID: "Pitch Env", naturalFrame: CGRect(x: 156, y: 142, width: 52, height: 86)) {
                    WaveKnobControl(patch: patch, id: .env3Att, size: Theme.knobSizeSmall, labelOverride: "Amount")
                        .opacity(showPitchEnvGraph ? 0 : 1)
                }
                WaveControlSlot(id: "env.pitch.graph", sectionID: "Pitch Env", naturalFrame: CGRect(x: 8, y: 138, width: 420, height: 92)) {
                    Group {
                        if showPitchEnvGraph {
                            WaveADGraphEditor(
                                patch: patch,
                                group: selectedGroup,
                                attackID: .attack3,
                                decayID: .decay3,
                                amountID: .env3Att
                            )
                        }
                    }
                    .nudgeable(id: "env.pitch.graph", controlType: .label)
                }
                WaveControlSlot(id: "env.pitch.mode", sectionID: "Pitch Env", naturalFrame: CGRect(x: 444, y: 188, width: 32, height: 32)) {
                    Button { withAnimation(.easeInOut(duration: 0.18)) { showPitchEnvGraph.toggle() } } label: {
                        Image(systemName: showPitchEnvGraph ? "dial.low" : "chart.xyaxis.line")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.waveHighlight.opacity(0.7))
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .nudgeable(id: "env.pitch.mode", controlType: .label)
                }
            }
        }
    }

    // MARK: - Row 2 Sections

    private var controlsSection: some View {
        WavePanelSection(title: "Wheels", controlIDs: ["wheel.pitch", "wheel.mod"]) {
            WaveSectionCanvas(height: 300) {
                WaveControlSlot(id: "wheel.pitch", sectionID: "Wheels", naturalFrame: CGRect(x: 0, y: 0, width: 52, height: 142)) {
                    WaveWheelControl(title: "Pitch", value: $pitchWheelValue, isPitch: true, nudgeID: "wheel.pitch")
                }
                WaveControlSlot(id: "wheel.mod", sectionID: "Wheels", naturalFrame: CGRect(x: 0, y: 148, width: 52, height: 142)) {
                    WaveWheelControl(title: "Mod", value: $modWheelValue, isPitch: false, nudgeID: "wheel.mod")
                }
            }
        }
    }

    /// OBsixer-style filter: Freq + Res on top, full wave envelope row below.
    /// ENV1→VCF amount sits at the end of the envelope row as "Env Amt".
    private var filterWaveEnvSection: some View {
        WavePanelSection(title: "Filter · Wave Env", resetIDs: [
            WaveParamID.vcfCutoff.rawValue, WaveParamID.vcfEmphasis.rawValue,
            WaveParamID.a1.rawValue, WaveParamID.d1.rawValue, WaveParamID.s1.rawValue,
            WaveParamID.r1.rawValue, WaveParamID.env1VCF.rawValue,
            "filter.velocity", "filter.normbp", "filter.keyamt", "filter.half", "filter.full", "filter.mode.knob",
            "env.filter.graph", "env.filter.mode"
        ]) {
            WaveSectionCanvas(height: 244) {
                WaveControlSlot(id: "filter.velocity", sectionID: "Filter · Wave Env", naturalFrame: CGRect(x: 10, y: 20, width: 92, height: 16)) {
                    WavePanelBulletLabel(text: "Velocity")
                        .nudgeable(id: "filter.velocity", controlType: .label)
                }
                WaveControlSlot(id: "filter.normbp", sectionID: "Filter · Wave Env", naturalFrame: CGRect(x: 10, y: 40, width: 92, height: 16)) {
                    WavePanelBulletLabel(text: "Norm/BP")
                        .nudgeable(id: "filter.normbp", controlType: .label)
                }
                WaveControlSlot(id: "filter.keyamt", sectionID: "Filter · Wave Env", naturalFrame: CGRect(x: 10, y: 64, width: 92, height: 14)) {
                    Text("KEY AMT")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.5))
                        .tracking(0.6)
                        .nudgeable(id: "filter.keyamt", controlType: .label)
                }
                WaveControlSlot(id: "filter.half", sectionID: "Filter · Wave Env", naturalFrame: CGRect(x: 10, y: 82, width: 92, height: 16)) {
                    WavePanelBulletLabel(text: "1/2")
                        .nudgeable(id: "filter.half", controlType: .label)
                }
                WaveControlSlot(id: "filter.full", sectionID: "Filter · Wave Env", naturalFrame: CGRect(x: 10, y: 102, width: 92, height: 16)) {
                    WavePanelBulletLabel(text: "Full")
                        .nudgeable(id: "filter.full", controlType: .label)
                }
                WaveControlSlot(id: WaveParamID.vcfCutoff.rawValue, sectionID: "Filter · Wave Env", naturalFrame: CGRect(x: 112, y: 2, width: 84, height: 124)) {
                    WaveKnobControl(patch: patch, id: .vcfCutoff, size: Theme.knobSizeMedium, labelOverride: "Freq")
                }
                WaveControlSlot(id: WaveParamID.vcfEmphasis.rawValue, sectionID: "Filter · Wave Env", naturalFrame: CGRect(x: 220, y: 2, width: 84, height: 124)) {
                    WaveKnobControl(patch: patch, id: .vcfEmphasis, size: Theme.knobSizeMedium, labelOverride: "Res")
                }
                WaveControlSlot(id: "filter.mode.knob", sectionID: "Filter · Wave Env", naturalFrame: CGRect(x: 324, y: 10, width: 88, height: 94)) {
                    WaveFilterModeControl(patch: patch)
                        .nudgeable(id: "filter.mode.knob", controlType: .menu)
                }
                WaveControlSlot(id: WaveParamID.a1.rawValue, sectionID: "Filter · Wave Env", naturalFrame: CGRect(x: 12, y: 142, width: 52, height: 86)) {
                    WaveKnobControl(patch: patch, id: .a1, size: Theme.knobSizeSmall, labelOverride: "Attack")
                        .opacity(showFilterEnvGraph ? 0 : 1)
                }
                WaveControlSlot(id: WaveParamID.d1.rawValue, sectionID: "Filter · Wave Env", naturalFrame: CGRect(x: 84, y: 142, width: 52, height: 86)) {
                    WaveKnobControl(patch: patch, id: .d1, size: Theme.knobSizeSmall, labelOverride: "Decay")
                        .opacity(showFilterEnvGraph ? 0 : 1)
                }
                WaveControlSlot(id: WaveParamID.s1.rawValue, sectionID: "Filter · Wave Env", naturalFrame: CGRect(x: 156, y: 142, width: 52, height: 86)) {
                    WaveKnobControl(patch: patch, id: .s1, size: Theme.knobSizeSmall, labelOverride: "Sustain")
                        .opacity(showFilterEnvGraph ? 0 : 1)
                }
                WaveControlSlot(id: WaveParamID.r1.rawValue, sectionID: "Filter · Wave Env", naturalFrame: CGRect(x: 228, y: 142, width: 52, height: 86)) {
                    WaveKnobControl(patch: patch, id: .r1, size: Theme.knobSizeSmall, labelOverride: "Release")
                        .opacity(showFilterEnvGraph ? 0 : 1)
                }
                WaveControlSlot(id: WaveParamID.env1VCF.rawValue, sectionID: "Filter · Wave Env", naturalFrame: CGRect(x: 300, y: 142, width: 52, height: 86)) {
                    WaveKnobControl(patch: patch, id: .env1VCF, size: Theme.knobSizeSmall, labelOverride: "Amt")
                        .opacity(showFilterEnvGraph ? 0 : 1)
                }
                WaveControlSlot(id: "env.filter.graph", sectionID: "Filter · Wave Env", naturalFrame: CGRect(x: 8, y: 138, width: 420, height: 92)) {
                    Group {
                        if showFilterEnvGraph {
                            WaveADSRGraphEditor(
                                patch: patch,
                                group: selectedGroup,
                                attackID: .a1,
                                decayID: .d1,
                                sustainID: .s1,
                                releaseID: .r1,
                                amountID: .env1VCF
                            )
                        }
                    }
                    .nudgeable(id: "env.filter.graph", controlType: .label)
                }
                WaveControlSlot(id: "env.filter.mode", sectionID: "Filter · Wave Env", naturalFrame: CGRect(x: 444, y: 188, width: 32, height: 32)) {
                    Button { withAnimation(.easeInOut(duration: 0.18)) { showFilterEnvGraph.toggle() } } label: {
                        Image(systemName: showFilterEnvGraph ? "dial.low" : "chart.xyaxis.line")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.waveHighlight.opacity(0.7))
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .nudgeable(id: "env.filter.mode", controlType: .label)
                }
            }
        }
    }

    private var ampEnvSection: some View {
        WavePanelSection(title: "Amp Env", resetIDs: [
            WaveParamID.a2.rawValue, WaveParamID.d2.rawValue, WaveParamID.s2.rawValue,
            WaveParamID.r2.rawValue, "amp.env2Loud",
            "amp.velocity", "env.amp.graph", "env.amp.mode"
        ]) {
            WaveSectionCanvas(height: 244) {
                WaveControlSlot(id: "amp.velocity", sectionID: "Amp Env", naturalFrame: CGRect(x: 10, y: 18, width: 92, height: 16)) {
                    WavePanelBulletLabel(text: "Velocity")
                        .nudgeable(id: "amp.velocity", controlType: .label)
                }
                WaveControlSlot(id: WaveParamID.a2.rawValue, sectionID: "Amp Env", naturalFrame: CGRect(x: 12, y: 142, width: 52, height: 86)) {
                    WaveKnobControl(patch: patch, id: .a2, size: Theme.knobSizeSmall, labelOverride: "Attack")
                        .opacity(showAmpEnvGraph ? 0 : 1)
                }
                WaveControlSlot(id: WaveParamID.d2.rawValue, sectionID: "Amp Env", naturalFrame: CGRect(x: 84, y: 142, width: 52, height: 86)) {
                    WaveKnobControl(patch: patch, id: .d2, size: Theme.knobSizeSmall, labelOverride: "Decay")
                        .opacity(showAmpEnvGraph ? 0 : 1)
                }
                WaveControlSlot(id: WaveParamID.s2.rawValue, sectionID: "Amp Env", naturalFrame: CGRect(x: 156, y: 142, width: 52, height: 86)) {
                    WaveKnobControl(patch: patch, id: .s2, size: Theme.knobSizeSmall, labelOverride: "Sustain")
                        .opacity(showAmpEnvGraph ? 0 : 1)
                }
                WaveControlSlot(id: WaveParamID.r2.rawValue, sectionID: "Amp Env", naturalFrame: CGRect(x: 228, y: 142, width: 52, height: 86)) {
                    WaveKnobControl(patch: patch, id: .r2, size: Theme.knobSizeSmall, labelOverride: "Release")
                        .opacity(showAmpEnvGraph ? 0 : 1)
                }
                WaveControlSlot(id: "amp.env2Loud", sectionID: "Amp Env", naturalFrame: CGRect(x: 300, y: 142, width: 52, height: 86)) {
                    WaveKnobControl(patch: patch, id: .env2Loud, size: Theme.knobSizeSmall, labelOverride: "Amt", nudgeIDOverride: "amp.env2Loud")
                        .opacity(showAmpEnvGraph ? 0 : 1)
                }
                WaveControlSlot(id: "env.amp.graph", sectionID: "Amp Env", naturalFrame: CGRect(x: 8, y: 138, width: 420, height: 92)) {
                    Group {
                        if showAmpEnvGraph {
                            WaveADSRGraphEditor(
                                patch: patch,
                                group: selectedGroup,
                                attackID: .a2,
                                decayID: .d2,
                                sustainID: .s2,
                                releaseID: .r2,
                                amountID: .env2Loud
                            )
                        }
                    }
                    .nudgeable(id: "env.amp.graph", controlType: .label)
                }
                WaveControlSlot(id: "env.amp.mode", sectionID: "Amp Env", naturalFrame: CGRect(x: 444, y: 188, width: 32, height: 32)) {
                    Button { withAnimation(.easeInOut(duration: 0.18)) { showAmpEnvGraph.toggle() } } label: {
                        Image(systemName: showAmpEnvGraph ? "dial.low" : "chart.xyaxis.line")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.waveHighlight.opacity(0.7))
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .nudgeable(id: "env.amp.mode", controlType: .label)
                }
            }
        }
    }

    /// All routing matrices — key, mod wheel, velocity, touch — using mini knobs.
    private var routingSection: some View {
        WavePanelSection(title: "Routing", resetIDs: [
            WaveParamID.kw.rawValue, WaveParamID.kf.rawValue, WaveParamID.kl.rawValue,
            WaveParamID.mw.rawValue, WaveParamID.mf.rawValue, WaveParamID.ml.rawValue,
            WaveParamID.vf.rawValue, WaveParamID.vl.rawValue,
            WaveParamID.tw.rawValue, WaveParamID.tf.rawValue, WaveParamID.tl.rawValue, WaveParamID.tm.rawValue,
            "routing.keytrack", "routing.modwheel", "routing.velocity", "routing.touch"
        ]) {
            WaveSectionCanvas(height: 250) {
                WaveControlSlot(id: "routing.keytrack", sectionID: "Routing", naturalFrame: CGRect(x: 6, y: 0, width: 60, height: 16)) {
                    Text("KEY TRACK")
                        .font(.system(size: 8, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(Color.white.opacity(0.3))
                        .nudgeable(id: "routing.keytrack", controlType: .label)
                }
                WaveControlSlot(id: "routing.modwheel", sectionID: "Routing", naturalFrame: CGRect(x: 92, y: 0, width: 68, height: 16)) {
                    Text("MOD WHEEL")
                        .font(.system(size: 8, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(Color.white.opacity(0.3))
                        .nudgeable(id: "routing.modwheel", controlType: .label)
                }
                WaveControlSlot(id: "routing.velocity", sectionID: "Routing", naturalFrame: CGRect(x: 182, y: 0, width: 56, height: 16)) {
                    Text("VELOCITY")
                        .font(.system(size: 8, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(Color.white.opacity(0.3))
                        .nudgeable(id: "routing.velocity", controlType: .label)
                }
                WaveControlSlot(id: "routing.touch", sectionID: "Routing", naturalFrame: CGRect(x: 268, y: 0, width: 44, height: 16)) {
                    Text("TOUCH")
                        .font(.system(size: 8, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(Color.white.opacity(0.3))
                        .nudgeable(id: "routing.touch", controlType: .label)
                }

                WaveControlSlot(id: WaveParamID.kw.rawValue, sectionID: "Routing", naturalFrame: CGRect(x: 0, y: 18, width: 52, height: 86)) { WaveKnobControl(patch: patch, id: .kw, size: Theme.knobSizeMini, labelOverride: "→Wave") }
                WaveControlSlot(id: WaveParamID.kf.rawValue, sectionID: "Routing", naturalFrame: CGRect(x: 0, y: 92, width: 52, height: 86)) { WaveKnobControl(patch: patch, id: .kf, size: Theme.knobSizeMini, labelOverride: "→Filt") }
                WaveControlSlot(id: WaveParamID.kl.rawValue, sectionID: "Routing", naturalFrame: CGRect(x: 0, y: 166, width: 52, height: 86)) { WaveKnobControl(patch: patch, id: .kl, size: Theme.knobSizeMini, labelOverride: "→Loud") }

                WaveControlSlot(id: WaveParamID.mw.rawValue, sectionID: "Routing", naturalFrame: CGRect(x: 84, y: 18, width: 52, height: 86)) { WaveKnobControl(patch: patch, id: .mw, size: Theme.knobSizeMini, labelOverride: "→Wave") }
                WaveControlSlot(id: WaveParamID.mf.rawValue, sectionID: "Routing", naturalFrame: CGRect(x: 84, y: 92, width: 52, height: 86)) { WaveKnobControl(patch: patch, id: .mf, size: Theme.knobSizeMini, labelOverride: "→Filt") }
                WaveControlSlot(id: WaveParamID.ml.rawValue, sectionID: "Routing", naturalFrame: CGRect(x: 84, y: 178, width: 56, height: 34)) { WaveLEDToggle(patch: patch, id: .ml, label: "→Loud") }

                WaveControlSlot(id: WaveParamID.vf.rawValue, sectionID: "Routing", naturalFrame: CGRect(x: 168, y: 61, width: 52, height: 86)) { WaveKnobControl(patch: patch, id: .vf, size: Theme.knobSizeMini, labelOverride: "→Filt") }
                WaveControlSlot(id: WaveParamID.vl.rawValue, sectionID: "Routing", naturalFrame: CGRect(x: 168, y: 135, width: 52, height: 86)) { WaveKnobControl(patch: patch, id: .vl, size: Theme.knobSizeMini, labelOverride: "→Loud") }

                WaveControlSlot(id: WaveParamID.tw.rawValue, sectionID: "Routing", naturalFrame: CGRect(x: 252, y: 18, width: 52, height: 86)) { WaveKnobControl(patch: patch, id: .tw, size: Theme.knobSizeMini, labelOverride: "→Wave") }
                WaveControlSlot(id: WaveParamID.tf.rawValue, sectionID: "Routing", naturalFrame: CGRect(x: 252, y: 92, width: 52, height: 86)) { WaveKnobControl(patch: patch, id: .tf, size: Theme.knobSizeMini, labelOverride: "→Filt") }
                WaveControlSlot(id: WaveParamID.tl.rawValue, sectionID: "Routing", naturalFrame: CGRect(x: 252, y: 166, width: 52, height: 86)) { WaveKnobControl(patch: patch, id: .tl, size: Theme.knobSizeMini, labelOverride: "→Loud") }
                WaveControlSlot(id: WaveParamID.tm.rawValue, sectionID: "Routing", naturalFrame: CGRect(x: 252, y: 214, width: 60, height: 34)) { WaveLEDToggle(patch: patch, id: .tm, label: "→Wheel") }
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
            WaveSectionCanvas(height: 320) {
                Text("OSCILLATOR").font(.system(size: 8, weight: .bold)).tracking(0.8).foregroundStyle(Color.white.opacity(0.3)).position(x: 44, y: 8)
                Text("BENDER").font(.system(size: 8, weight: .bold)).tracking(0.8).foregroundStyle(Color.white.opacity(0.3)).position(x: 132, y: 8)
                Text("TUNING").font(.system(size: 8, weight: .bold)).tracking(0.8).foregroundStyle(Color.white.opacity(0.3)).position(x: 222, y: 8)
                Text("VOICE TUNING").font(.system(size: 8, weight: .bold)).tracking(0.8).foregroundStyle(Color.white.opacity(0.3)).position(x: 320, y: 8)

                WaveControlSlot(id: WaveParamID.uw.rawValue, sectionID: "Performance", naturalFrame: CGRect(x: 0, y: 18, width: 86, height: 120)) {
                    WaveLEDRadio(patch: patch, id: .uw, options: ["128", "2048", "8192"], label: "Upper WT")
                }
                WaveControlSlot(id: WaveParamID.sw.rawValue, sectionID: "Performance", naturalFrame: CGRect(x: 0, y: 142, width: 92, height: 170)) {
                    WaveLEDRadio(patch: patch, id: .sw, options: ["Off", "-1oct", "-2oct", "-3oct", "Sine", "Pulse", "Tri"], label: "Sub Osc")
                }

                WaveControlSlot(id: WaveParamID.bd.rawValue, sectionID: "Performance", naturalFrame: CGRect(x: 92, y: 42, width: 72, height: 152)) {
                    WaveLEDRadio(patch: patch, id: .bd, options: ["Off", "Wave", "Pitch", "Filt", "Loud", "All"], label: "Dest")
                }
                WaveControlSlot(id: WaveParamID.bi.rawValue, sectionID: "Performance", naturalFrame: CGRect(x: 100, y: 204, width: 52, height: 86)) {
                    WaveKnobControl(patch: patch, id: .bi, size: Theme.knobSizeMini, labelOverride: "Int")
                }

                WaveControlSlot(id: WaveParamID.detu.rawValue, sectionID: "Performance", naturalFrame: CGRect(x: 176, y: 18, width: 52, height: 86)) {
                    WaveKnobControl(patch: patch, id: .detu, size: Theme.knobSizeMini, labelOverride: "Detune")
                }
                WaveControlSlot(id: WaveParamID.eo.rawValue, sectionID: "Performance", naturalFrame: CGRect(x: 176, y: 104, width: 52, height: 86)) {
                    WaveKnobControl(patch: patch, id: .eo, size: Theme.knobSizeMini, labelOverride: "E3→Main")
                }
                WaveControlSlot(id: WaveParamID.mo.rawValue, sectionID: "Performance", naturalFrame: CGRect(x: 172, y: 192, width: 68, height: 34)) { WaveLEDToggle(patch: patch, id: .mo, label: "M→Main") }
                WaveControlSlot(id: WaveParamID.ms.rawValue, sectionID: "Performance", naturalFrame: CGRect(x: 172, y: 228, width: 68, height: 34)) { WaveLEDToggle(patch: patch, id: .ms, label: "M→Sub") }
                WaveControlSlot(id: WaveParamID.es.rawValue, sectionID: "Performance", naturalFrame: CGRect(x: 172, y: 264, width: 68, height: 34)) { WaveLEDToggle(patch: patch, id: .es, label: "E3→Sub") }

                WaveControlSlot(id: WaveParamID.semitV1.rawValue, sectionID: "Performance", naturalFrame: CGRect(x: 250, y: 18, width: 52, height: 86)) { WaveKnobControl(patch: patch, id: .semitV1, size: Theme.knobSizeMini, labelOverride: "V1") }
                WaveControlSlot(id: WaveParamID.semitV2.rawValue, sectionID: "Performance", naturalFrame: CGRect(x: 306, y: 18, width: 52, height: 86)) { WaveKnobControl(patch: patch, id: .semitV2, size: Theme.knobSizeMini, labelOverride: "V2") }
                WaveControlSlot(id: WaveParamID.semitV3.rawValue, sectionID: "Performance", naturalFrame: CGRect(x: 250, y: 104, width: 52, height: 86)) { WaveKnobControl(patch: patch, id: .semitV3, size: Theme.knobSizeMini, labelOverride: "V3") }
                WaveControlSlot(id: WaveParamID.semitV4.rawValue, sectionID: "Performance", naturalFrame: CGRect(x: 306, y: 104, width: 52, height: 86)) { WaveKnobControl(patch: patch, id: .semitV4, size: Theme.knobSizeMini, labelOverride: "V4") }
                WaveControlSlot(id: WaveParamID.semitV5.rawValue, sectionID: "Performance", naturalFrame: CGRect(x: 250, y: 190, width: 52, height: 86)) { WaveKnobControl(patch: patch, id: .semitV5, size: Theme.knobSizeMini, labelOverride: "V5") }
                WaveControlSlot(id: WaveParamID.semitV6.rawValue, sectionID: "Performance", naturalFrame: CGRect(x: 306, y: 190, width: 52, height: 86)) { WaveKnobControl(patch: patch, id: .semitV6, size: Theme.knobSizeMini, labelOverride: "V6") }
                WaveControlSlot(id: WaveParamID.semitV7.rawValue, sectionID: "Performance", naturalFrame: CGRect(x: 250, y: 276, width: 52, height: 86)) { WaveKnobControl(patch: patch, id: .semitV7, size: Theme.knobSizeMini, labelOverride: "V7") }
                WaveControlSlot(id: WaveParamID.semitV8.rawValue, sectionID: "Performance", naturalFrame: CGRect(x: 306, y: 276, width: 52, height: 86)) { WaveKnobControl(patch: patch, id: .semitV8, size: Theme.knobSizeMini, labelOverride: "V8") }
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

private enum WaveWavetableHandle {
    case osc
    case sub
}

private struct WaveWavetableEntryStrip: View {
    @ObservedObject var patch: Patch
    let tableIndex: Int?
    @Binding var selectedHandle: WaveWavetableHandle
    var plotOnly: Bool = false

    @Environment(\.waveActiveGroup) private var group
    @State private var isHoveringSurface = false
    @State private var keyMonitor: Any?

    private var table: [[Int8]] {
        guard let tableIndex else { return [] }
        guard WaveTables.waveTables.indices.contains(tableIndex) else { return [] }
        return WaveTables.waveTables[tableIndex].indices.map {
            WaveTables.displayCycleSamples(tableIndex: tableIndex, cycleIndex: $0)
        }
    }

    private var cycleCount: Int { table.count }
    private var framesPerCycle: Int { table.first?.count ?? 0 }
    private var oscValue: Int { patch.value(for: .wavesOsc, group: group) }
    private var subValue: Int { patch.value(for: .wavesSub, group: group) }
    private var oscCycle: Int { cycleIndex(for: oscValue) }
    private var subCycle: Int { cycleIndex(for: subValue) }
    private var titleText: String { WaveTables.slotDisplayName(for: patch.value(for: .wavetb, group: group)) }

    var body: some View {
        Group {
            if plotOnly {
                surfaceView
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        labelPill("OSC", color: Theme.waveHighlight, cycle: oscCycle, isSelected: selectedHandle == .osc)
                            .onTapGesture { selectedHandle = .osc }
                        labelPill("SUB", color: Theme.waveGroupBHighlight, cycle: subCycle, isSelected: selectedHandle == .sub)
                            .onTapGesture { selectedHandle = .sub }
                        Spacer()
                        Text(titleText)
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.42))
                            .lineLimit(1)
                    }

                    surfaceView
                        .frame(height: 78)
                }
            }
        }
        .onAppear { installKeyMonitorIfNeeded() }
        .onDisappear { teardownKeyMonitor() }
    }

    private var surfaceView: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.black.opacity(0.28))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Theme.xrAccentBlue.opacity(0.34), lineWidth: 1)
                    )

                Canvas { ctx, size in
                    drawSurface(in: size, context: &ctx)
                }
            }
            .contentShape(Rectangle())
            .onHover { isHoveringSurface = $0 }
            .onTapGesture { location in
                guard cycleCount > 0 else { return }
                let cycle = resolveCycle(at: location.x, width: geo.size.width)
                selectedHandle = nearestHandle(to: cycle)
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        guard cycleCount > 0 else { return }
                        let cycle = resolveCycle(at: gesture.location.x, width: geo.size.width)
                        if gesture.translation == .zero {
                            selectedHandle = nearestHandle(to: cycle)
                        }
                        setCycle(cycle, for: selectedHandle)
                    }
            )
        }
    }

    private func cycleIndex(for parameterValue: Int) -> Int {
        guard cycleCount > 0 else { return 0 }
        let clamped = min(max(0, parameterValue), 127)
        return Int((Double(clamped) / 127.0 * Double(cycleCount - 1)).rounded())
    }

    private func parameterValue(for cycle: Int) -> Int {
        guard cycleCount > 0 else { return 0 }
        let clamped = min(max(0, cycle), cycleCount - 1)
        guard cycleCount > 1 else { return 0 }
        return Int((Double(clamped) / Double(cycleCount - 1) * 127.0).rounded())
    }

    private func resolveCycle(at x: CGFloat, width: CGFloat) -> Int {
        guard cycleCount > 1 else { return 0 }
        let fraction = min(max(0, x / max(1, width)), 1)
        return Int(round(fraction * CGFloat(cycleCount - 1)))
    }

    private func labelPill(_ title: String, color: Color, cycle: Int, isSelected: Bool) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text("\(title) \(cycle)")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(color.opacity(0.92))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background((isSelected ? color.opacity(0.12) : Color.black.opacity(0.22)), in: Capsule())
        .overlay(
            Capsule()
                .stroke(isSelected ? color.opacity(0.8) : Color.clear, lineWidth: 1)
        )
    }

    private func nearestHandle(to cycle: Int) -> WaveWavetableHandle {
        let distanceToOsc = abs(cycle - oscCycle)
        let distanceToSub = abs(cycle - subCycle)
        return distanceToOsc <= distanceToSub ? .osc : .sub
    }

    private func setCycle(_ cycle: Int, for handle: WaveWavetableHandle) {
        switch handle {
        case .osc:
            patch.setValue(parameterValue(for: cycle), for: .wavesOsc, group: group)
        case .sub:
            patch.setValue(parameterValue(for: cycle), for: .wavesSub, group: group)
        }
    }

    private func nudgeSelectedHandle(by delta: Int) {
        guard cycleCount > 0 else { return }
        switch selectedHandle {
        case .osc:
            setCycle(min(max(0, oscCycle + delta), cycleCount - 1), for: .osc)
        case .sub:
            setCycle(min(max(0, subCycle + delta), cycleCount - 1), for: .sub)
        }
    }

    private func installKeyMonitorIfNeeded() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard isHoveringSurface else { return event }
            let step = event.modifierFlags.contains(.shift) ? 4 : 1
            switch event.keyCode {
            case 123:
                nudgeSelectedHandle(by: -step)
                return nil
            case 124:
                nudgeSelectedHandle(by: step)
                return nil
            default:
                return event
            }
        }
    }

    private func teardownKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    private func drawSurface(in size: CGSize, context: inout GraphicsContext) {
        guard cycleCount > 0, framesPerCycle > 1 else { return }

        let width = max(size.width, 1)
        let height = max(size.height, 1)
        let leftPad: CGFloat = 10
        let rightPad: CGFloat = 10
        let topPad: CGFloat = 8
        let bottomPad: CGFloat = 10

        // Draw each cycle at full width, then shift the next one up and to the
        // right. That is the actual visual model the user described.
        let xShiftTotal = width * 0.32
        let yShiftTotal = height * 0.54
        let xStep = xShiftTotal / CGFloat(max(1, cycleCount - 1))
        let yStep = yShiftTotal / CGFloat(max(1, cycleCount - 1))
        let waveWidth = max(52, width - leftPad - rightPad - xShiftTotal)
        let baseStartX = leftPad + 4
        let baseBaselineY = height - bottomPad - 16
        let ampScale = max(22, height * 0.24)

        let clipRect = CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1)
        context.clip(to: Path(roundedRect: clipRect, cornerRadius: 10))

        for cycle in (0..<cycleCount).reversed() where cycle != oscCycle && cycle != subCycle {
            let depth = CGFloat(cycle) / CGFloat(max(1, cycleCount - 1))
            let opacity = 0.22 + (1.0 - Double(depth)) * 0.14
            let lineWidth: CGFloat = cycle.isMultiple(of: 8) ? 0.92 : 0.72
            drawCycle(
                cycle: cycle,
                color: Theme.xrAccentBlue,
                opacity: opacity,
                lineWidth: lineWidth,
                in: size,
                context: &context,
                baseStartX: baseStartX,
                baseBaselineY: baseBaselineY,
                xStep: xStep,
                yStep: yStep,
                waveWidth: waveWidth,
                ampScale: cycleAmplitudeScale(for: cycle, baseAmpScale: ampScale)
            )
        }

        drawCycle(
            cycle: oscCycle,
            color: Theme.waveHighlight,
            opacity: 0.98,
            lineWidth: 1.15,
            in: size,
            context: &context,
            baseStartX: baseStartX,
            baseBaselineY: baseBaselineY,
            xStep: xStep,
            yStep: yStep,
            waveWidth: waveWidth,
            ampScale: cycleAmplitudeScale(for: oscCycle, baseAmpScale: ampScale)
        )

        if subCycle != oscCycle {
            drawCycle(
                cycle: subCycle,
                color: Theme.waveGroupBHighlight,
                opacity: 0.98,
                lineWidth: 1.1,
                in: size,
                context: &context,
                baseStartX: baseStartX,
                baseBaselineY: baseBaselineY,
                xStep: xStep,
                yStep: yStep,
                waveWidth: waveWidth,
                ampScale: cycleAmplitudeScale(for: subCycle, baseAmpScale: ampScale)
            )
        }

    }

    private func cycleAmplitudeScale(for cycle: Int, baseAmpScale: CGFloat) -> CGFloat {
        baseAmpScale
    }

    private func drawCycle(
        cycle: Int,
        color: Color,
        opacity: Double,
        lineWidth: CGFloat,
        in size: CGSize,
        context: inout GraphicsContext,
        baseStartX: CGFloat,
        baseBaselineY: CGFloat,
        xStep: CGFloat,
        yStep: CGFloat,
        waveWidth: CGFloat,
        ampScale: CGFloat
    ) {
        let depth = CGFloat(cycle)
        let start = CGPoint(x: baseStartX + depth * xStep, y: baseBaselineY - depth * yStep)

        var points: [CGPoint] = []
        points.reserveCapacity(framesPerCycle)
        for sampleIndex in 0..<framesPerCycle {
            let sample = CGFloat(table[cycle][sampleIndex]) / 128.0
            let phase = CGFloat(sampleIndex) / CGFloat(max(1, framesPerCycle - 1))
            let baseline = CGPoint(
                x: start.x + waveWidth * phase,
                y: start.y
            )
            points.append(CGPoint(
                x: clampedFinite(baseline.x, fallback: start.x, min: -4096, max: size.width + 4096),
                y: clampedFinite(baseline.y - (sample * ampScale), fallback: baseline.y, min: -4096, max: size.height + 4096)
            ))
        }

        var path = Path()
        path.addLines(points)

        context.stroke(
            path,
            with: .color(color.opacity(opacity)),
            style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt, lineJoin: .miter)
        )
    }

    private var activeColor: Color {
        selectedHandle == .osc ? Theme.waveHighlight : Theme.waveGroupBHighlight
    }

    private func clampedFinite(_ value: CGFloat, fallback: CGFloat, min minValue: CGFloat, max maxValue: CGFloat) -> CGFloat {
        guard value.isFinite else { return fallback }
        return Swift.min(Swift.max(value, minValue), maxValue)
    }

    private func interpolatedPoint(from start: CGPoint, to end: CGPoint, depth: CGFloat) -> CGPoint {
        CGPoint(
            x: start.x + (end.x - start.x) * depth,
            y: start.y + (end.y - start.y) * depth
        )
    }
}

private struct WaveWavetablePlot: View {
    @ObservedObject var patch: Patch
    let tableIndex: Int?
    @Binding var selectedHandle: WaveWavetableHandle

    var body: some View {
        WaveWavetableEntryStrip(patch: patch, tableIndex: tableIndex, selectedHandle: $selectedHandle, plotOnly: true)
            .nudgeable(id: "waves.plot", controlType: .label)
    }
}

private struct WaveWavetableSelectorLauncher: View {
    @ObservedObject var patch: Patch
    let tableIndex: Int?
    let previewCycle: Int
    @State private var isPresenting = false
    @Environment(\.waveActiveGroup) private var group

    var body: some View {
        Button { isPresenting = true } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.black.opacity(0.42))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Theme.waveHighlight.opacity(0.22), lineWidth: 1)
                    )

                WaveWavetableCyclePreview(tableIndex: tableIndex, cycleIndex: previewCycle)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
            }
            .frame(width: 150, height: 52)
        }
        .buttonStyle(.plain)
        .nudgeable(id: "waves.selector", controlType: .menu)
        .sheet(isPresented: $isPresenting) {
            WaveWavetableSelectorSheet(selectedIndex: Binding(
                get: { patch.value(for: .wavetb, group: group) },
                set: { patch.setValue($0, for: .wavetb, group: group) }
            ))
        }
    }
}

private struct WaveWavetableSelectorSheet: View {
    @Binding var selectedIndex: Int
    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.adaptive(minimum: 100, maximum: 120), spacing: 8)]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Select Wavetable")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.gray)
                        .font(.title2)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color(white: 0.15))

            ScrollView {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(WaveTables.waveTables.indices, id: \.self) { index in
                        WaveWavetableSelectorCell(index: index, isSelected: index == selectedIndex)
                            .onTapGesture {
                                selectedIndex = index
                                dismiss()
                            }
                    }
                }
                .padding()
            }
        }
        .frame(width: 500, height: 600)
        .background(Color(white: 0.1))
    }
}

private struct WaveWavetableSelectorCell: View {
    let index: Int
    let isSelected: Bool
    private let previewCycle = 63

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Theme.waveHighlight.opacity(0.18) : Color.black.opacity(0.4))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isSelected ? Theme.waveHighlight : Color.white.opacity(0.1), lineWidth: 1)
                )

            VStack(spacing: 4) {
                WaveWavetableCyclePreview(tableIndex: index, cycleIndex: previewCycle)
                    .frame(height: 30)
                    .allowsHitTesting(false)
                    .opacity(0.8)

                Text(WaveTables.slotDisplayName(for: index))
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(isSelected ? .white : .gray)
                    .multilineTextAlignment(.center)
                    .frame(height: 24)
                    .lineLimit(2)
            }
            .padding(6)
        }
        .frame(height: 80)
        .contentShape(Rectangle())
    }
}

private struct WaveWavetableCyclePreview: View {
    let tableIndex: Int?
    let cycleIndex: Int

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let cycle = tableIndex.map { WaveTables.displayCycleSamples(tableIndex: $0, cycleIndex: cycleIndex) } ?? []
            let sampleCount = cycle.count

            Path { path in
                guard sampleCount > 1 else { return }
                let leftPad = width * 0.04
                let usableWidth = max(1, width - (leftPad * 2))
                let centerY = height * 0.5
                let ampScale = height * 0.34

                for i in cycle.indices {
                    let phase = CGFloat(i) / CGFloat(max(1, sampleCount - 1))
                    let point = CGPoint(
                        x: leftPad + phase * usableWidth,
                        y: centerY - (CGFloat(cycle[i]) / 128.0) * ampScale
                    )
                    if i == cycle.startIndex {
                        path.move(to: point)
                    } else {
                        path.addLine(to: point)
                    }
                }
            }
            .stroke(Theme.waveHighlight.opacity(0.95), style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round))
        }
    }
}

private struct WaveWavetableMiniPreview: View {
    let tableIndex: Int

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let table = WaveTables.waveTables.indices.contains(tableIndex) ? WaveTables.waveTables[tableIndex] : []
            let cycle = representativeCycle(for: table)
            let sampleCount = cycle.count

            Path { path in
                guard sampleCount > 1 else { return }
                let leftPad = width * 0.03
                let usableWidth = max(1, width - (leftPad * 2))
                let centerY = height * 0.50
                let ampScale = height * 0.40
                for i in cycle.indices {
                    let phase = CGFloat(i) / CGFloat(max(1, sampleCount - 1))
                    let rawX = leftPad + phase * usableWidth
                    let rawY = centerY - (CGFloat(cycle[i]) / 128.0) * ampScale
                    let point = CGPoint(x: rawX, y: rawY)
                    if i == cycle.startIndex {
                        path.move(to: point)
                    } else {
                        path.addLine(to: point)
                    }
                }
            }
            .stroke(Theme.waveHighlight.opacity(0.95), style: StrokeStyle(lineWidth: 1, lineCap: .butt, lineJoin: .miter))
        }
    }

    private func representativeCycle(for table: [[Int8]]) -> [Int8] {
        guard !table.isEmpty else { return [] }
        let centerIndex = min(max(0, table.count / 2), table.count - 1)
        return table[centerIndex]
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

private struct WavePanelBulletLabel: View {
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.white.opacity(0.16))
                .frame(width: 7, height: 7)
            Text(text.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.46))
                .tracking(0.5)
        }
    }
}

private struct WaveStaticKnob: View {
    let title: String
    let valueText: String
    var size: CGFloat = Theme.knobSizeMedium
    var nudgeID: String? = nil
    @ObservedObject private var canonicalLayoutService = WavePanelLayoutService.shared

    var body: some View {
        let knobSize = canonicalLayoutService.knobSize(for: nudgeID ?? title) ?? size
        let capSize = knobSize - 12

        VStack(spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold))
                .tracking(1.0)
                .foregroundStyle(Color.white.opacity(0.4))
                .lineLimit(1)

            ZStack {
                Circle()
                    .trim(from: 0, to: 0.75)
                    .stroke(Color(white: 0.24).opacity(0.42), style: StrokeStyle(lineWidth: 3.5, lineCap: .butt))
                    .rotationEffect(.degrees(135))
                    .frame(width: knobSize, height: knobSize)

                Circle()
                    .fill(LinearGradient(
                        colors: [Color(white: 0.22), Color(white: 0.10)],
                        startPoint: .top, endPoint: .bottom
                    ))
                    .overlay(
                        Circle().strokeBorder(
                            LinearGradient(colors: [Color(white: 0.3), Color(white: 0.05)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            lineWidth: 1
                        )
                    )
                    .frame(width: capSize, height: capSize)
                    .shadow(color: .black.opacity(0.5), radius: 3, x: 0, y: 2)

                Rectangle()
                    .fill(Color.white.opacity(0.85))
                    .frame(width: 1.5, height: capSize * 0.35)
                    .offset(y: -(capSize * 0.24))
                    .rotationEffect(.degrees(225))
            }

            Text(valueText)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.waveHighlight.opacity(0.9))
        }
    }
}

private struct WaveFilterModeControl: View {
    @ObservedObject var patch: Patch
    @Environment(\.waveActiveGroup) private var group
    @Environment(\.waveControlHighlight) private var highlight
    @Environment(\.waveGroupBHighlight) private var secondaryHighlight
    @State private var selectedIndex: Int = 0

    private let options = ["Norm", "BP", "1/2", "Full"]

    private var storageKey: String {
        let patchKey = patch.uuid?.uuidString ?? "default"
        return "brWave.filterMode.\(patchKey).\(group.rawValue)"
    }

    private var storedSelection: Int {
        min(max(UserDefaults.standard.integer(forKey: storageKey), 0), options.count - 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("MODE")
                .font(.system(size: 9, weight: .bold))
                .tracking(1.0)
                .foregroundStyle(Color.white.opacity(0.4))

            Menu {
                ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                    Button(option) {
                        selectedIndex = index
                        UserDefaults.standard.set(index, forKey: storageKey)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(group == .a ? highlight : secondaryHighlight)
                        .frame(width: 6, height: 6)
                    Text(options[selectedIndex])
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.9))
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.5))
                }
                .padding(.horizontal, 8)
                .frame(height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.black.opacity(0.42))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(highlight.opacity(0.28), lineWidth: 1)
                        )
                )
            }
            .menuStyle(.borderlessButton)
            .buttonStyle(.plain)

            Text("\(selectedIndex)")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(highlight.opacity(0.9))
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .onAppear {
            selectedIndex = storedSelection
        }
        .onChange(of: group) { _, _ in
            selectedIndex = storedSelection
        }
    }
}

private struct WaveADSRGraphEditor: View {
    @ObservedObject var patch: Patch
    let group: WaveGroup
    let attackID: WaveParamID
    let decayID: WaveParamID
    let sustainID: WaveParamID
    let releaseID: WaveParamID
    let amountID: WaveParamID

    private func value(_ id: WaveParamID) -> Int {
        patch.value(for: id, group: group)
    }

    private func range(for id: WaveParamID) -> ClosedRange<Int> {
        WaveParameters.all.first(where: { $0.id == id })?.range ?? 0...127
    }

    private func normalized(_ value: Int, for id: WaveParamID) -> CGFloat {
        let r = range(for: id)
        guard r.upperBound > r.lowerBound else { return 0 }
        return CGFloat(value - r.lowerBound) / CGFloat(r.upperBound - r.lowerBound)
    }

    private func denormalized(_ norm: CGFloat, for id: WaveParamID) -> Int {
        let r = range(for: id)
        let clamped = min(max(norm, 0), 1)
        return r.lowerBound + Int(round(clamped * CGFloat(r.upperBound - r.lowerBound)))
    }

    private enum ActiveHandle {
        case attack
        case decaySustain
        case sustain
        case release
        case amount
    }

    var body: some View {
        GeometryReader { geo in
            let attack = value(attackID)
            let decay = value(decayID)
            let sustain = value(sustainID)
            let release = value(releaseID)
            let amount = value(amountID)

            let w = geo.size.width
            let h = geo.size.height
            let graphW = max(1, w - 42)
            let maxSeg = graphW * 0.25
            let xA = normalized(attack, for: attackID) * maxSeg
            let xD = xA + normalized(decay, for: decayID) * maxSeg
            let yS = h - normalized(sustain, for: sustainID) * h
            let xS = xD + graphW * 0.2
            let xR = xS + normalized(release, for: releaseID) * maxSeg
            let sliderX = w - 18
            let sliderHeight = normalized(amount, for: amountID) * h
            let attackPoint = CGPoint(x: xA, y: 0)
            let decayPoint = CGPoint(x: xD, y: yS)
            let sustainPoint = CGPoint(x: xS, y: yS)
            let releasePoint = CGPoint(x: xR, y: h)
            let amountPoint = CGPoint(x: sliderX, y: h - sliderHeight)

            ZStack(alignment: .topLeading) {
                WaveGraphGridBackground()

                Path { p in
                    p.move(to: CGPoint(x: 0, y: h))
                    p.addLine(to: CGPoint(x: xA, y: 0))
                    p.addLine(to: CGPoint(x: xD, y: yS))
                    p.addLine(to: CGPoint(x: xS, y: yS))
                    p.addLine(to: CGPoint(x: xR, y: h))
                    p.closeSubpath()
                }
                .fill(LinearGradient(colors: [Theme.waveHighlight.opacity(0.22), Theme.waveHighlight.opacity(0.04)], startPoint: .top, endPoint: .bottom))

                Path { p in
                    p.move(to: CGPoint(x: 0, y: h))
                    p.addLine(to: CGPoint(x: xA, y: 0))
                    p.addLine(to: CGPoint(x: xD, y: yS))
                    p.addLine(to: CGPoint(x: xS, y: yS))
                    p.addLine(to: CGPoint(x: xR, y: h))
                }
                .stroke(Theme.waveHighlight, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                Path { p in
                    p.move(to: CGPoint(x: sliderX, y: h))
                    p.addLine(to: CGPoint(x: sliderX, y: h - sliderHeight))
                }
                .stroke(Theme.waveHighlight, style: StrokeStyle(lineWidth: 3, lineCap: .round))

                WaveStaticHandleDot().offset(x: -22, y: h - 22)

                WaveHandleDot()
                    .offset(x: xA - 22, y: -22)
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .named("WaveADSRGraph"))
                            .onChanged { drag in
                                let newValue = denormalized(drag.location.x / maxSeg, for: attackID)
                                patch.setValue(newValue, for: attackID, group: group)
                            }
                    )

                WaveHandleDot()
                    .offset(x: xD - 22, y: yS - 22)
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .named("WaveADSRGraph"))
                            .onChanged { drag in
                                let relative = max(0, drag.location.x - xA)
                                let newDecay = denormalized(relative / maxSeg, for: decayID)
                                let newSustain = denormalized(1 - (drag.location.y / max(h, 1)), for: sustainID)
                                patch.setValue(newDecay, for: decayID, group: group)
                                patch.setValue(newSustain, for: sustainID, group: group)
                            }
                    )

                WaveHandleDot()
                    .offset(x: xS - 22, y: yS - 22)
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .named("WaveADSRGraph"))
                            .onChanged { drag in
                                let newSustain = denormalized(1 - (drag.location.y / max(h, 1)), for: sustainID)
                                patch.setValue(newSustain, for: sustainID, group: group)
                            }
                    )

                WaveHandleDot()
                    .offset(x: xR - 22, y: h - 22)
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .named("WaveADSRGraph"))
                            .onChanged { drag in
                                let relative = max(0, drag.location.x - xS)
                                let newRelease = denormalized(relative / maxSeg, for: releaseID)
                                patch.setValue(newRelease, for: releaseID, group: group)
                            }
                    )

                WaveHandleDot()
                    .offset(x: sliderX - 22, y: (h - sliderHeight) - 22)
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .named("WaveADSRGraph"))
                            .onChanged { drag in
                                let newAmount = denormalized(1 - (drag.location.y / max(h, 1)), for: amountID)
                                patch.setValue(newAmount, for: amountID, group: group)
                            }
                    )

                HStack(spacing: 6) {
                    Text("A:\(attack)")
                    Text("D:\(decay)")
                    Text("S:\(sustain)")
                    Text("R:\(release)")
                    Text("Amt:\(amount)")
                }
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(Color.secondary)
                .padding(.top, 4)
                .padding(.trailing, 34)
                .frame(maxWidth: .infinity, alignment: .topTrailing)
                .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("WaveADSRGraph"))
                    .onChanged { drag in
                        switch nearestHandle(
                            to: drag.location,
                            attack: attackPoint,
                            decay: decayPoint,
                            sustain: sustainPoint,
                            release: releasePoint,
                            amount: amountPoint
                        ) {
                        case .attack:
                            let newValue = denormalized(drag.location.x / maxSeg, for: attackID)
                            patch.setValue(newValue, for: attackID, group: group)
                        case .decaySustain:
                            let relative = max(0, drag.location.x - xA)
                            let newDecay = denormalized(relative / maxSeg, for: decayID)
                            let newSustain = denormalized(1 - (drag.location.y / max(h, 1)), for: sustainID)
                            patch.setValue(newDecay, for: decayID, group: group)
                            patch.setValue(newSustain, for: sustainID, group: group)
                        case .sustain:
                            let newSustain = denormalized(1 - (drag.location.y / max(h, 1)), for: sustainID)
                            patch.setValue(newSustain, for: sustainID, group: group)
                        case .release:
                            let relative = max(0, drag.location.x - xS)
                            let newRelease = denormalized(relative / maxSeg, for: releaseID)
                            patch.setValue(newRelease, for: releaseID, group: group)
                        case .amount:
                            let newAmount = denormalized(1 - (drag.location.y / max(h, 1)), for: amountID)
                            patch.setValue(newAmount, for: amountID, group: group)
                        }
                    }
            )
            .coordinateSpace(name: "WaveADSRGraph")
        }
    }

    private func nearestHandle(
        to location: CGPoint,
        attack: CGPoint,
        decay: CGPoint,
        sustain: CGPoint,
        release: CGPoint,
        amount: CGPoint
    ) -> ActiveHandle {
        let candidates: [(ActiveHandle, CGPoint)] = [
            (.attack, attack),
            (.decaySustain, decay),
            (.sustain, sustain),
            (.release, release),
            (.amount, amount)
        ]
        return candidates.min { lhs, rhs in
            lhs.1.distanceSquared(to: location) < rhs.1.distanceSquared(to: location)
        }?.0 ?? .attack
    }
}

private struct WaveADGraphEditor: View {
    @ObservedObject var patch: Patch
    let group: WaveGroup
    let attackID: WaveParamID
    let decayID: WaveParamID
    let amountID: WaveParamID

    private func value(_ id: WaveParamID) -> Int {
        patch.value(for: id, group: group)
    }

    private func range(for id: WaveParamID) -> ClosedRange<Int> {
        WaveParameters.all.first(where: { $0.id == id })?.range ?? 0...127
    }

    private func normalized(_ value: Int, for id: WaveParamID) -> CGFloat {
        let r = range(for: id)
        guard r.upperBound > r.lowerBound else { return 0 }
        return CGFloat(value - r.lowerBound) / CGFloat(r.upperBound - r.lowerBound)
    }

    private func denormalized(_ norm: CGFloat, for id: WaveParamID) -> Int {
        let r = range(for: id)
        let clamped = min(max(norm, 0), 1)
        return r.lowerBound + Int(round(clamped * CGFloat(r.upperBound - r.lowerBound)))
    }

    private enum ActiveHandle {
        case attack
        case decay
        case amount
    }

    var body: some View {
        GeometryReader { geo in
            let attack = value(attackID)
            let decay = value(decayID)
            let amount = value(amountID)

            let w = geo.size.width
            let h = geo.size.height
            let graphW = max(1, w - 30)
            let maxSeg = graphW * 0.28
            let startX: CGFloat = 8
            let baseY = h * 0.76
            let peakY = h * 0.14
            let xA = startX + normalized(attack, for: attackID) * maxSeg
            let xD = xA + normalized(decay, for: decayID) * maxSeg
            let holdX = graphW - 14
            let sliderX = w - 10
            let sliderHeight = normalized(amount, for: amountID) * h
            let attackPoint = CGPoint(x: xA, y: peakY)
            let decayPoint = CGPoint(x: xD, y: baseY)
            let amountPoint = CGPoint(x: sliderX, y: h - sliderHeight)

            ZStack(alignment: .topLeading) {
                WaveGraphGridBackground()

                Path { p in
                    p.move(to: CGPoint(x: startX, y: baseY))
                    p.addLine(to: CGPoint(x: xA, y: peakY))
                    p.addLine(to: CGPoint(x: xD, y: baseY))
                    p.addLine(to: CGPoint(x: holdX, y: baseY))
                }
                .stroke(Theme.waveHighlight, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                Path { p in
                    p.move(to: CGPoint(x: startX, y: baseY))
                    p.addLine(to: CGPoint(x: xA, y: peakY))
                    p.addLine(to: CGPoint(x: xD, y: baseY))
                    p.addLine(to: CGPoint(x: holdX, y: baseY))
                    p.addLine(to: CGPoint(x: holdX, y: h))
                    p.addLine(to: CGPoint(x: startX, y: h))
                    p.closeSubpath()
                }
                .fill(LinearGradient(colors: [Theme.waveHighlight.opacity(0.18), Theme.waveHighlight.opacity(0.03)], startPoint: .top, endPoint: .bottom))

                Path { p in
                    p.move(to: CGPoint(x: sliderX, y: h))
                    p.addLine(to: CGPoint(x: sliderX, y: h - sliderHeight))
                }
                .stroke(Theme.waveHighlight, style: StrokeStyle(lineWidth: 3, lineCap: .round))

                WaveStaticHandleDot().offset(x: startX - 22, y: baseY - 22)

                WaveHandleDot()
                    .offset(x: xA - 22, y: peakY - 22)
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .named("WaveADGraph"))
                            .onChanged { drag in
                                let relative = max(0, drag.location.x - startX)
                                let newAttack = denormalized(relative / maxSeg, for: attackID)
                                patch.setValue(newAttack, for: attackID, group: group)
                            }
                    )

                WaveHandleDot()
                    .offset(x: xD - 22, y: baseY - 22)
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .named("WaveADGraph"))
                            .onChanged { drag in
                                let relative = max(0, drag.location.x - xA)
                                let newDecay = denormalized(relative / maxSeg, for: decayID)
                                patch.setValue(newDecay, for: decayID, group: group)
                            }
                    )

                WaveHandleDot()
                    .offset(x: sliderX - 22, y: (h - sliderHeight) - 22)
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .named("WaveADGraph"))
                            .onChanged { drag in
                                let newAmount = denormalized(1 - (drag.location.y / max(h, 1)), for: amountID)
                                patch.setValue(newAmount, for: amountID, group: group)
                            }
                    )

                HStack(spacing: 6) {
                    Text("A:\(attack)")
                    Text("D:\(decay)")
                    Text("Amt:\(amount)")
                }
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(Color.secondary)
                .padding(.top, 4)
                .frame(maxWidth: .infinity, alignment: .topTrailing)
                .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("WaveADGraph"))
                    .onChanged { drag in
                        switch nearestHandle(to: drag.location, attack: attackPoint, decay: decayPoint, amount: amountPoint) {
                        case .attack:
                            let relative = max(0, drag.location.x - startX)
                            let newAttack = denormalized(relative / maxSeg, for: attackID)
                            patch.setValue(newAttack, for: attackID, group: group)
                        case .decay:
                            let relative = max(0, drag.location.x - xA)
                            let newDecay = denormalized(relative / maxSeg, for: decayID)
                            patch.setValue(newDecay, for: decayID, group: group)
                        case .amount:
                            let newAmount = denormalized(1 - (drag.location.y / max(h, 1)), for: amountID)
                            patch.setValue(newAmount, for: amountID, group: group)
                        }
                    }
            )
            .coordinateSpace(name: "WaveADGraph")
        }
    }

    private func nearestHandle(to location: CGPoint, attack: CGPoint, decay: CGPoint, amount: CGPoint) -> ActiveHandle {
        let candidates: [(ActiveHandle, CGPoint)] = [
            (.attack, attack),
            (.decay, decay),
            (.amount, amount)
        ]
        return candidates.min { lhs, rhs in
            lhs.1.distanceSquared(to: location) < rhs.1.distanceSquared(to: location)
        }?.0 ?? .attack
    }
}

private extension CGPoint {
    func distanceSquared(to other: CGPoint) -> CGFloat {
        let dx = x - other.x
        let dy = y - other.y
        return (dx * dx) + (dy * dy)
    }
}

private struct WaveHandleDot: View {
    var body: some View {
        ZStack {
            Circle().fill(Color.black)
            Circle().fill(Theme.waveHighlight.opacity(0.75))
        }
        .frame(width: 11, height: 11)
        .overlay(Circle().stroke(Theme.waveHighlight, lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 2)
        .frame(width: 44, height: 44)
    }
}

private struct WaveStaticHandleDot: View {
    var body: some View {
        ZStack {
            Circle().fill(Color.black)
            Circle().fill(Theme.waveHighlight.opacity(0.45))
        }
        .frame(width: 10, height: 10)
        .frame(width: 44, height: 44)
    }
}

private struct WaveGraphGridBackground: View {
    var body: some View {
        GeometryReader { geo in
            Path { path in
                for i in 1...3 {
                    let y = geo.size.height * (CGFloat(i) / 4.0)
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: geo.size.width, y: y))
                }
                for i in 1...3 {
                    let x = geo.size.width * (CGFloat(i) / 4.0)
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: geo.size.height))
                }
            }
            .stroke(Color.white.opacity(0.06), lineWidth: 1)
        }
    }
}

private struct WaveLFOGraphic: View {
    let delay: Int
    let shape: Int
    let rate: Int

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            Canvas { context, _ in
                let rect = CGRect(origin: .zero, size: size).insetBy(dx: 4, dy: 4)
                context.stroke(Path(roundedRect: rect, cornerRadius: 6), with: .color(Theme.xrAccentBlue.opacity(0.16)), lineWidth: 1)
                let delayFraction = CGFloat(delay) / 127
                let delayX = rect.minX + rect.width * delayFraction * 0.45

                var base = Path()
                base.move(to: CGPoint(x: rect.minX + 4, y: rect.maxY - 6))
                base.addLine(to: CGPoint(x: delayX, y: rect.maxY - 6))
                context.stroke(base, with: .color(Theme.waveHighlight.opacity(0.9)), lineWidth: 2)

                let shapeIndex = min(max(Int(round(Double(shape) / 127.0 * 4.0)), 0), 4)
                let lfoPath = Self.shapePath(for: shapeIndex, in: rect)
                let speedScale = 1 + CGFloat(rate) / 127 * 0.25
                let transformed = lfoPath.applying(
                    CGAffineTransform(translationX: -rect.minX, y: -rect.minY)
                        .translatedBy(x: rect.minX, y: rect.midY)
                        .scaledBy(x: speedScale, y: 1)
                        .translatedBy(x: 0, y: -rect.midY)
                )
                context.stroke(transformed, with: .color(Theme.waveHighlight.opacity(0.92)), lineWidth: 1.8)
            }
        }
        .frame(height: 56)
        .allowsHitTesting(false)
    }

    static func shapePath(for shape: Int, in rect: CGRect) -> Path {
        let midY = rect.height / 2
        let amp = rect.height * 0.4
        let w = rect.width
        var p = Path()

        switch shape {
        case 0:
            let steps = max(1, Int(w))
            for i in 0...steps {
                let x = w * CGFloat(i) / CGFloat(steps)
                let y = midY - amp * CGFloat(sin(Double(i) / Double(steps) * 2 * .pi))
                if i == 0 { p.move(to: CGPoint(x: x, y: y)) }
                else { p.addLine(to: CGPoint(x: x, y: y)) }
            }
        case 1:
            p.move(to: CGPoint(x: 0, y: midY + amp))
            p.addLine(to: CGPoint(x: w, y: midY - amp))
        case 2:
            p.move(to: CGPoint(x: 0, y: midY - amp))
            p.addLine(to: CGPoint(x: w, y: midY + amp))
        case 3:
            p.move(to: CGPoint(x: 0, y: midY - amp))
            p.addLine(to: CGPoint(x: w * 0.5, y: midY - amp))
            p.addLine(to: CGPoint(x: w * 0.5, y: midY + amp))
            p.addLine(to: CGPoint(x: w, y: midY + amp))
        case 4:
            let steps: [CGFloat] = [0.3, 0.8, 0.1, 0.6, 0.9, 0.2, 0.7, 0.4]
            let stepW = w / CGFloat(steps.count)
            for (i, frac) in steps.enumerated() {
                let x = CGFloat(i) * stepW
                let y = midY + amp - frac * 2 * amp
                if i == 0 { p.move(to: CGPoint(x: 0, y: y)) }
                else {
                    p.addLine(to: CGPoint(x: x, y: p.currentPoint?.y ?? y))
                    p.addLine(to: CGPoint(x: x, y: y))
                }
                p.addLine(to: CGPoint(x: x + stepW, y: y))
            }
        default:
            break
        }

        return p
    }
}

private struct WaveLFOShapeSelector: View {
    @ObservedObject var patch: Patch

    @Environment(\.waveActiveGroup) private var group
    @State private var showPopup = false
    @State private var scrollAccum = 0.0

    private let shapeNames = ["Sine", "Saw", "Rev", "Sq", "Rnd"]

    private var currentShapeIndex: Int {
        min(max(Int(round(Double(patch.value(for: .waveshape, group: group)) / 127.0 * 4.0)), 0), 4)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.black.opacity(0.35))

            GeometryReader { geo in
                WaveLFOGraphic.shapePath(for: currentShapeIndex, in: geo.frame(in: .local))
                    .stroke(Theme.waveHighlight, lineWidth: 1.5)
            }

            Text(shapeNames[currentShapeIndex])
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.waveHighlight.opacity(0.7))
                .padding(3)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .frame(height: 40)
        .contentShape(Rectangle())
        .modifier(WaveScrollModifier(onScroll: { delta in
            scrollAccum += delta
            guard abs(scrollAccum) >= 1.5 else { return }
            let dir = scrollAccum > 0 ? 1 : -1
            let next = ((currentShapeIndex + dir) % shapeNames.count + shapeNames.count) % shapeNames.count
            applyShape(next)
            scrollAccum = 0
        }))
        .onTapGesture { showPopup = true }
        .popover(isPresented: $showPopup, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(shapeNames.indices, id: \.self) { idx in
                    Button {
                        applyShape(idx)
                        showPopup = false
                    } label: {
                        HStack(spacing: 8) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.black.opacity(0.4))
                                GeometryReader { geo in
                                    WaveLFOGraphic.shapePath(for: idx, in: geo.frame(in: .local))
                                        .stroke(idx == currentShapeIndex ? Theme.waveHighlight : Color.secondary.opacity(0.5), lineWidth: 1.5)
                                }
                            }
                            .frame(width: 56, height: 22)

                            Text(shapeNames[idx])
                                .font(.system(size: 11))
                                .lineLimit(1)
                                .foregroundStyle(idx == currentShapeIndex ? Color.primary : Color.secondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(idx == currentShapeIndex ? Theme.waveHighlight.opacity(0.12) : Color.clear)
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .fixedSize()
        }
    }

    private func applyShape(_ idx: Int) {
        let clamped = min(max(0, idx), shapeNames.count - 1)
        let raw = Int(round((Double(clamped) / Double(shapeNames.count - 1)) * 127.0))
        patch.setValue(raw, for: .waveshape, group: group)
    }
}

// MARK: - WavePanelSection

struct WavePanelSection<Content: View>: View {
    let title: String
    var resetIDs: [String] = []
    var controlIDs: [String]? = nil
    @ViewBuilder let content: () -> Content

    private let accent = Theme.xrHeaderBackground
    @Environment(\.isTuningMode) private var isTuningMode
    @ObservedObject private var canonicalLayoutService = WavePanelLayoutService.shared
    @State private var currentNaturalSize: CGSize = .zero
    @State private var panelDragOrigin: CGPoint?

    var body: some View {
        let panelSelectionID = canonicalLayoutService.panelSelectionID(for: title)
        let storedFrame = canonicalLayoutService.panelFrame(for: title)
        let storedSize = storedFrame?.size
        let trackedControlIDs = controlIDs ?? resetIDs
        let defaultSize = defaultSectionSize
        let minimumSize = minimumSectionSize
        let effectiveWidth = max(minimumSize.width, storedSize?.width ?? defaultSize.width)
        let effectiveHeight = max(minimumSize.height, storedSize?.height ?? defaultSize.height)
        let selectedInSection = isTuningMode && trackedControlIDs.contains { canonicalLayoutService.selectedIDs.contains($0) }
        let panelSelected = isTuningMode && canonicalLayoutService.selectedIDs.contains(panelSelectionID)
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
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                if isTuningMode && !resetIDs.isEmpty {
                    Button {
                        canonicalLayoutService.resetControlPositions(resetIDs)
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
            .contentShape(Rectangle())
            .onTapGesture {
                guard isTuningMode else { return }
                if NSEvent.modifierFlags.contains(.shift) {
                    canonicalLayoutService.toggleSectionSelection(title)
                } else {
                    canonicalLayoutService.selectSection(title)
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        guard isTuningMode else { return }
                        if panelDragOrigin == nil {
                            panelDragOrigin = canonicalLayoutService.panelFrame(for: title)?.origin ?? .zero
                            canonicalLayoutService.selectSection(title)
                        }
                        let start = panelDragOrigin ?? .zero
                        canonicalLayoutService.setPanelOriginLive(
                            title,
                            origin: CGPoint(
                                x: start.x + value.translation.width,
                                y: start.y + value.translation.height
                            )
                        )
                    }
                    .onEnded { value in
                        guard isTuningMode else { return }
                        let start = panelDragOrigin ?? canonicalLayoutService.panelFrame(for: title)?.origin ?? .zero
                        canonicalLayoutService.setPanelOrigin(
                            title,
                            origin: CGPoint(
                                x: start.x + value.translation.width,
                                y: start.y + value.translation.height
                            )
                        )
                        panelDragOrigin = nil
                    }
            )

            ZStack(alignment: .topLeading) {
                content()
                    .padding(16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                if panelSelected {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Theme.waveHighlight.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 2)
                                .stroke(Theme.waveHighlight, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                        )
                        .allowsHitTesting(false)
                }
            }
        }
        .frame(width: effectiveWidth, height: effectiveHeight, alignment: .topLeading)
        .background(Theme.xrSectionBackground)
        .overlay(RoundedRectangle(cornerRadius: 2).stroke(accent.opacity(0.35), lineWidth: 1))
        .overlay(alignment: .bottomTrailing) {
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
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear {
                        currentNaturalSize = geo.size
                        canonicalLayoutService.reportSectionFrame(title, geo.frame(in: .named("wavePanel")), controlIDs: trackedControlIDs)
                    }
                    .onChange(of: geo.size) { _, size in
                        currentNaturalSize = size
                        canonicalLayoutService.reportSectionFrame(title, geo.frame(in: .named("wavePanel")), controlIDs: trackedControlIDs)
                    }
            }
        )
        .if(!isTuningMode) { $0.clipShape(RoundedRectangle(cornerRadius: 2)) }
        .zIndex((selectedInSection || panelSelected) ? 100 : 0)
        .frame(width: effectiveWidth > 0 ? effectiveWidth : nil, height: effectiveHeight > 0 ? effectiveHeight : nil, alignment: .topLeading)
    }

    private var defaultSectionSize: CGSize {
        switch title {
        case "LFO":
            return CGSize(width: 220, height: 204)
        case "Modulation":
            return CGSize(width: 220, height: 134)
        case "Waves":
            return CGSize(width: 275, height: 614)
        case "Wheels":
            return CGSize(width: 120, height: 314)
        case "Filter · Wave Env":
            return CGSize(width: 520, height: 258)
        case "Amp Env":
            return CGSize(width: 520, height: 258)
        case "Pitch Env":
            return CGSize(width: 520, height: 258)
        case "Routing":
            return CGSize(width: 520, height: 264)
        case "Performance":
            return CGSize(width: 380, height: 334)
        default:
            return currentNaturalSize == .zero ? CGSize(width: 160, height: 120) : currentNaturalSize
        }
    }

    private var minimumSectionSize: CGSize {
        switch title {
        case "LFO":
            return CGSize(width: 160, height: 144)
        case "Modulation":
            return CGSize(width: 160, height: 114)
        case "Waves":
            return CGSize(width: 240, height: 374)
        case "Wheels":
            return CGSize(width: 90, height: 194)
        case "Filter · Wave Env", "Amp Env", "Pitch Env":
            return CGSize(width: 320, height: 154)
        case "Routing":
            return CGSize(width: 320, height: 174)
        case "Performance":
            return CGSize(width: 280, height: 234)
        default:
            return CGSize(width: 120, height: 94)
        }
    }

}

private struct WaveSectionCanvas<Content: View>: View {
    let height: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack(alignment: .topLeading) {
            content()
        }
        .frame(maxWidth: .infinity, minHeight: height, alignment: .topLeading)
    }
}

private struct WaveControlSlot<Content: View>: View {
    let id: String
    let sectionID: String
    let naturalFrame: CGRect
    @ViewBuilder let content: () -> Content

    @ObservedObject private var canonicalLayoutService = WavePanelLayoutService.shared

    var body: some View {
        let frame = canonicalLayoutService.displayFrame(for: id, in: sectionID, fallback: naturalFrame)

        content()
            .frame(width: frame.width, height: frame.height, alignment: .topLeading)
            .position(x: frame.midX, y: frame.midY)
            .onAppear {
                canonicalLayoutService.registerControl(id, sectionID: sectionID, frame: naturalFrame)
            }
    }
}

struct TuningSelectionInfo: View {
    @ObservedObject private var canonicalLayoutService = WavePanelLayoutService.shared

    var body: some View {
        let ids = Array(canonicalLayoutService.selectedIDs)
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

    @ViewBuilder
    private func singleItemChip(id: String) -> some View {
        if let sectionID = canonicalLayoutService.sectionID(for: id) {
            let size = canonicalLayoutService.size(for: sectionID) ?? .zero

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(sectionID)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text("PANEL")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.waveHighlight)
                }

                if size != .zero {
                    Divider().frame(height: 20)
                    Text("w \(Int(size.width))  h \(Int(size.height))")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Color.secondary)
                }

                Divider().frame(height: 20)
                Button("Reset Size") {
                    canonicalLayoutService.resetSectionSize(sectionID)
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
        } else {
            let descriptor = WaveParamID(rawValue: id).flatMap { WaveParameters.byID[$0] }
            let offset = canonicalLayoutService.origin(for: id).map { CGSize(width: $0.x, height: $0.y) } ?? .zero

            HStack(spacing: 10) {
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
                    canonicalLayoutService.resetControlPosition(id)
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
