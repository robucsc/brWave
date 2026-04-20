//
//  NudgeableModifier.swift
//  brWave
//
//  Drag-to-nudge overlay for panel editor controls.
//  Activate with the wrench button in the panel header — shows dashed outlines,
//  drag to reposition, right-click for per-control inspector.
//  Ported from OBsixer — renamed OB6 → Wave, ob6Blue → waveHighlight.
//

import SwiftUI

// MARK: - Frame Preference Key

struct NudgeFrameKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

// MARK: - Environment Keys

struct TuningModeKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

struct PanelZoomScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1.0
}

struct WaveUsesCanonicalLayoutKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    var isTuningMode: Bool {
        get { self[TuningModeKey.self] }
        set { self[TuningModeKey.self] = newValue }
    }
    var panelZoomScale: CGFloat {
        get { self[PanelZoomScaleKey.self] }
        set { self[PanelZoomScaleKey.self] = newValue }
    }
    var waveUsesCanonicalLayout: Bool {
        get { self[WaveUsesCanonicalLayoutKey.self] }
        set { self[WaveUsesCanonicalLayoutKey.self] = newValue }
    }
}

// MARK: - Control Type Metadata

enum NudgeControlType {
    case knob(size: CGFloat)
    case menu
    case toggle
    case label

    var displayName: String {
        switch self {
        case .knob:   return "Knob"
        case .menu:   return "Menu"
        case .toggle: return "Toggle"
        case .label:  return "Label"
        }
    }

    var knobSize: CGFloat? {
        if case .knob(let s) = self { return s }
        return nil
    }
}

// MARK: - Control Inspector Popover

struct NudgeControlInspector: View {
    let id:          String
    let controlType: NudgeControlType?
    @ObservedObject var offsetService: LayoutOffsetService
    @ObservedObject private var canonicalLayoutService = WavePanelLayoutService.shared
    @Environment(\.panelZoomScale) var zoom
    @Environment(\.waveUsesCanonicalLayout) private var waveUsesCanonicalLayout

    private var nudgeStyle: NudgeStyle { offsetService.style(for: id) }

    private func effectiveDisplay(_ declared: CGFloat) -> String {
        let effective = declared * zoom
        return zoom == 1.0
            ? "\(Int(declared))pt"
            : "\(Int(declared))pt → \(String(format: "%.1f", effective))pt"
    }

    private func labelDisplay(_ size: CGFloat) -> String {
        size == 0 ? "Default" : effectiveDisplay(size)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text(id)
                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                    .foregroundColor(.secondary)

                if let ct = controlType {
                    HStack(spacing: 8) {
                        Label(ct.displayName, systemImage: iconName(for: ct))
                            .font(.system(size: 11, weight: .semibold))
                        if let declared = ct.knobSize {
                            let active = nudgeStyle.knobSize == 0 ? declared : nudgeStyle.knobSize
                            let eff = active * zoom
                            Text(zoom == 1.0 ? "\(Int(active))px" : "\(Int(active))px → \(String(format: "%.0f", eff))px")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.12))
                                .cornerRadius(3)
                        }
                    }
                }

                if zoom != 1.0 {
                    Text("zoom \(String(format: "%.0f", zoom * 100))%")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(Theme.waveHighlight)
                }
            }

            Divider()

            // Knob size
            if controlType?.knobSize != nil {
                VStack(alignment: .leading, spacing: 6) {
                    Text("KNOB SIZE")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                    Picker("", selection: Binding(
                        get: { nudgeStyle.knobSize == 0 ? (controlType?.knobSize ?? Theme.knobSizeSmall) : nudgeStyle.knobSize },
                        set: { offsetService.setKnobSize(id, size: $0) }
                    )) {
                        Text("Mini (\(Int(Theme.knobSizeMini)))")  .tag(Theme.knobSizeMini)
                        Text("Small (\(Int(Theme.knobSizeSmall)))").tag(Theme.knobSizeSmall)
                        Text("Medium (\(Int(Theme.knobSizeMedium)))").tag(Theme.knobSizeMedium)
                        Text("Large (\(Int(Theme.knobSizeLarge)))") .tag(Theme.knobSizeLarge)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
            }

            // Label font
            VStack(alignment: .leading, spacing: 6) {
                Text("LABEL FONT")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
                HStack(spacing: 8) {
                    Text(labelDisplay(nudgeStyle.labelFontSize))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .frame(width: 80, alignment: .leading)
                    Stepper("", value: Binding(
                        get: { nudgeStyle.labelFontSize == 0 ? 10 : nudgeStyle.labelFontSize },
                        set: { offsetService.setLabelFontSize(id, size: $0) }
                    ), in: 7...20, step: 1)
                    .labelsHidden()
                    Button("↺") { offsetService.setLabelFontSize(id, size: 0) }
                        .buttonStyle(.plain).foregroundColor(.secondary)
                        .help("Reset to theme default")
                }
            }

            // Value font
            VStack(alignment: .leading, spacing: 6) {
                Text("VALUE FONT")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
                HStack(spacing: 8) {
                    Text(labelDisplay(nudgeStyle.valueFontSize))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .frame(width: 80, alignment: .leading)
                    Stepper("", value: Binding(
                        get: { nudgeStyle.valueFontSize == 0 ? 10 : nudgeStyle.valueFontSize },
                        set: { offsetService.setValueFontSize(id, size: $0) }
                    ), in: 7...20, step: 1)
                    .labelsHidden()
                    Button("↺") { offsetService.setValueFontSize(id, size: 0) }
                        .buttonStyle(.plain).foregroundColor(.secondary)
                        .help("Reset to theme default")
                }
            }

            Divider()

            let offset = waveUsesCanonicalLayout
                ? canonicalLayoutService.origin(for: id).map { CGSize(width: $0.x, height: $0.y) } ?? .zero
                : offsetService.offset(for: id)
            if offset != .zero {
                HStack(spacing: 12) {
                    Text(waveUsesCanonicalLayout ? "ORIGIN" : "OFFSET")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                    Text("x \(Int(offset.width))  y \(Int(offset.height))")
                        .font(.system(size: 10, design: .monospaced))
                }
            }

            Button("Reset Position & Fonts") {
                if waveUsesCanonicalLayout {
                    canonicalLayoutService.resetControlPosition(id)
                } else {
                    offsetService.resetOffset(id)
                }
                offsetService.resetStyle(id)
            }
            .font(.system(size: 11))
            .foregroundColor(Theme.waveHighlight)
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(width: 260)
    }

    private func iconName(for ct: NudgeControlType) -> String {
        switch ct {
        case .knob:   return "dial.medium"
        case .menu:   return "list.bullet"
        case .toggle: return "togglepower"
        case .label:  return "textformat"
        }
    }
}

// MARK: - Nudgeable Modifier

struct NudgeableModifier: ViewModifier {
    let id:          String
    var controlType: NudgeControlType? = nil
    @ObservedObject var offsetService  = LayoutOffsetService.shared
    @ObservedObject var canonicalLayoutService = WavePanelLayoutService.shared
    @Environment(\.isTuningMode) var isTuningMode
    @Environment(\.waveUsesCanonicalLayout) private var waveUsesCanonicalLayout

    @State private var showInspector = false

    func body(content: Content) -> some View {
        let baseFrame = canonicalLayoutService.baseFrames[id] ?? .zero
        let storedOffset = if waveUsesCanonicalLayout,
                              let origin = canonicalLayoutService.origin(for: id),
                              baseFrame != .zero {
            CGSize(width: origin.x - baseFrame.minX, height: origin.y - baseFrame.minY)
        } else {
            offsetService.offset(for: id)
        }
        let dynamicDelta = if waveUsesCanonicalLayout {
            canonicalLayoutService.selectedIDs.contains(id) ? canonicalLayoutService.activeDragDelta : .zero
        } else {
            offsetService.selectedIDs.contains(id) ? offsetService.activeDragDelta : .zero
        }
        let currentOffset = CGSize(
            width:  storedOffset.width  + dynamicDelta.width,
            height: storedOffset.height + dynamicDelta.height
        )

        content
            .allowsHitTesting(!(isTuningMode && waveUsesCanonicalLayout) && !isTuningMode)
            .overlay(
                ZStack {
                    if isTuningMode {
                        let selectionIDs = waveUsesCanonicalLayout ? canonicalLayoutService.selectedIDs : offsetService.selectedIDs
                        let keyObjectID = waveUsesCanonicalLayout ? canonicalLayoutService.keyObjectID : offsetService.keyObjectID
                        let isSelected  = selectionIDs.contains(id)
                        let isKeyObject = keyObjectID == id && isSelected

                        RoundedRectangle(cornerRadius: 6)
                            .fill(isSelected ? Theme.waveHighlight.opacity(0.15) : Color.clear)
                            .stroke(
                                isSelected ? Theme.waveHighlight : Theme.waveHighlight.opacity(0.3),
                                style: StrokeStyle(lineWidth: isKeyObject ? 3 : (isSelected ? 2 : 1),
                                                   dash: isSelected ? [] : [4])
                            )
                            .padding(-4)
                            .allowsHitTesting(false)

                        Color.white.opacity(0.001)
                            .contentShape(Rectangle())
                            .contextMenu {
                                Button("Control Inspector…") { showInspector = true }
                                Divider()
                                let isHighlighted = offsetService.style(for: id).highlighted
                                Button(isHighlighted ? "Remove Highlight" : "Highlight Knob") {
                                    offsetService.setHighlighted(id, !isHighlighted)
                                }
                                Button("Set as Key Object") {
                                    if waveUsesCanonicalLayout {
                                        canonicalLayoutService.select(id, exclusive: false)
                                    } else {
                                        offsetService.select(id, exclusive: false)
                                        offsetService.keyObjectID = id
                                    }
                                }
                                .disabled(!selectionIDs.contains(id))
                                Divider()
                                Button("Reset Position") {
                                    if waveUsesCanonicalLayout {
                                        canonicalLayoutService.resetControlPosition(id)
                                    } else {
                                        offsetService.resetOffset(id)
                                    }
                                }
                                Button("Reset Fonts")    { offsetService.resetStyle(id)  }
                                Button("Reset All") {
                                    if waveUsesCanonicalLayout {
                                        canonicalLayoutService.resetControlPosition(id)
                                    } else {
                                        offsetService.resetOffset(id)
                                    }
                                    offsetService.resetStyle(id)
                                }
                            }
                            .popover(isPresented: $showInspector, arrowEdge: .leading) {
                                NudgeControlInspector(id: id, controlType: controlType,
                                                      offsetService: offsetService)
                            }
                    }
                }
            )
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: NudgeFrameKey.self,
                        value: [id: proxy.frame(in: .named("wavePanel"))]
                    )
                }
            )
            .offset(currentOffset)
            .onAppear {
                if !waveUsesCanonicalLayout {
                    DispatchQueue.main.async { offsetService.register(id) }
                }
            }
            .onDisappear {
                if !waveUsesCanonicalLayout {
                    DispatchQueue.main.async { offsetService.unregister(id) }
                }
            }
    }
}

// MARK: - View extension

extension View {
    func nudgeable(id: String, controlType: NudgeControlType? = nil) -> some View {
        self.modifier(NudgeableModifier(id: id, controlType: controlType))
    }
}
