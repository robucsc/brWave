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
    @ObservedObject private var canonicalLayoutService = WavePanelLayoutService.shared
    @Environment(\.panelZoomScale) var zoom
    @State private var originXText = ""
    @State private var originYText = ""
    @State private var widthText = ""
    @State private var heightText = ""
    @State private var knobSizeText = ""
    private let knobVisualInset: CGFloat = 12
    private let knobSizePresets: [(label: String, size: CGFloat)] = [
        ("Mini", Theme.knobSizeMini),
        ("Small", Theme.knobSizeSmall),
        ("Medium", Theme.knobSizeMedium),
        ("Large", Theme.knobSizeLarge)
    ]

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
                            let displayed = displayedKnobSize(fromStored: declared)
                            Text(
                                zoom == 1.0
                                    ? "\(Int(displayed))px"
                                    : "\(Int(displayed))px → \(String(format: "%.0f", displayed * zoom))px"
                            )
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

            let origin = canonicalLayoutService.origin(for: id) ?? .zero
            let frame = canonicalLayoutService.frame(for: id) ?? .zero
            let knobSize = canonicalLayoutService.knobSize(for: id) ?? controlType?.knobSize
            if origin != .zero {
                HStack(spacing: 12) {
                    Text("ORIGIN")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                    Text("x \(Int(origin.x))  y \(Int(origin.y))")
                        .font(.system(size: 10, design: .monospaced))
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("EDIT FRAME")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)

                HStack(spacing: 8) {
                    nudgeField(title: "X", text: $originXText) {
                        canonicalLayoutService.setOrigin(
                            CGPoint(x: CGFloat(Int(originXText) ?? Int(origin.x)), y: CGFloat(Int(originYText) ?? Int(origin.y))),
                            for: id
                        )
                    }
                    nudgeField(title: "Y", text: $originYText) {
                        canonicalLayoutService.setOrigin(
                            CGPoint(x: CGFloat(Int(originXText) ?? Int(origin.x)), y: CGFloat(Int(originYText) ?? Int(origin.y))),
                            for: id
                        )
                    }
                }

                HStack(spacing: 8) {
                    nudgeField(title: "W", text: $widthText) {
                        canonicalLayoutService.setSize(
                            CGSize(width: CGFloat(Int(widthText) ?? Int(frame.width)), height: CGFloat(Int(heightText) ?? Int(frame.height))),
                            for: id
                        )
                    }
                    nudgeField(title: "H", text: $heightText) {
                        canonicalLayoutService.setSize(
                            CGSize(width: CGFloat(Int(widthText) ?? Int(frame.width)), height: CGFloat(Int(heightText) ?? Int(frame.height))),
                            for: id
                        )
                    }
                }
            }

            if case .knob = controlType {
                VStack(alignment: .leading, spacing: 8) {
                    Text("KNOB SIZE")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)

                    HStack(spacing: 8) {
                        nudgeField(title: "SIZE", text: $knobSizeText) {
                            let fallback = Int(displayedKnobSize(fromStored: knobSize ?? 44))
                            canonicalLayoutService.setKnobSize(
                                storedKnobSize(fromDisplayed: CGFloat(Int(knobSizeText) ?? fallback)),
                                for: id
                            )
                            syncFields()
                        }
                    }

                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(minimum: 0), spacing: 8),
                            GridItem(.flexible(minimum: 0), spacing: 8)
                        ],
                        alignment: .leading,
                        spacing: 8
                    ) {
                        ForEach(knobSizePresets, id: \.label) { preset in
                            knobSizePresetButton(
                                label: preset.label,
                                size: preset.size,
                                isSelected: Int(knobSize ?? 0) == Int(preset.size)
                            )
                        }
                    }
                }
            }

            Button("Reset Position") {
                canonicalLayoutService.resetControlPosition(id)
            }
            .font(.system(size: 11))
            .foregroundColor(Theme.waveHighlight)
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(width: 280)
        .onAppear {
            syncFields()
        }
    }

    private func iconName(for ct: NudgeControlType) -> String {
        switch ct {
        case .knob:   return "dial.medium"
        case .menu:   return "list.bullet"
        case .toggle: return "togglepower"
        case .label:  return "textformat"
        }
    }

    private func syncFields() {
        let frame = canonicalLayoutService.frame(for: id) ?? .zero
        originXText = "\(Int(frame.origin.x))"
        originYText = "\(Int(frame.origin.y))"
        widthText = "\(Int(frame.size.width))"
        heightText = "\(Int(frame.size.height))"
        let knobSize = canonicalLayoutService.knobSize(for: id) ?? controlType?.knobSize
        knobSizeText = knobSize.map { "\(Int(displayedKnobSize(fromStored: $0)))" } ?? ""
    }

    private func nudgeField(title: String, text: Binding<String>, onCommit: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary)
            TextField(title, text: text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11, design: .monospaced))
                .frame(width: 56)
                .onSubmit(onCommit)
        }
    }

    private func knobSizePresetButton(label: String, size: CGFloat, isSelected: Bool) -> some View {
        Button {
            canonicalLayoutService.setKnobSize(size, for: id)
            syncFields()
        } label: {
            Text("\(label) (\(Int(displayedKnobSize(fromStored: size))))")
                .font(.system(size: 10, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .foregroundStyle(isSelected ? Color.black : Color.primary)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(isSelected ? Color.orange : Color.secondary.opacity(0.12))
                )
        }
        .buttonStyle(.plain)
    }

    private func displayedKnobSize(fromStored stored: CGFloat) -> CGFloat {
        max(1, stored - knobVisualInset)
    }

    private func storedKnobSize(fromDisplayed displayed: CGFloat) -> CGFloat {
        max(24, displayed + knobVisualInset)
    }
}

// MARK: - Nudgeable Modifier

struct NudgeableModifier: ViewModifier {
    let id:          String
    var controlType: NudgeControlType? = nil
    @ObservedObject var canonicalLayoutService = WavePanelLayoutService.shared
    @Environment(\.isTuningMode) var isTuningMode

    @State private var showInspector = false
    @State private var tuningDragActive = false
    @State private var shiftToggleHandledOnBegin = false

    func body(content: Content) -> some View {
        let selectionIDs = canonicalLayoutService.selectedIDs
        let keyObjectID = canonicalLayoutService.keyObjectID
        let isSelected = selectionIDs.contains(id)
        let isKeyObject = keyObjectID == id && isSelected
        let wrapped = content
            .allowsHitTesting(!isTuningMode)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: NudgeFrameKey.self,
                        value: [id: proxy.frame(in: .named("wavePanel"))]
                    )
                }
            )
            .overlay {
                if isTuningMode {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected ? Theme.waveHighlight.opacity(0.15) : Color.clear)
                        .stroke(
                            isSelected ? Theme.waveHighlight : Theme.waveHighlight.opacity(0.3),
                            style: StrokeStyle(
                                lineWidth: isKeyObject ? 3 : (isSelected ? 2 : 1),
                                dash: isSelected ? [] : [4]
                            )
                        )
                        .padding(-4)
                        .allowsHitTesting(false)
                }
            }
            .zIndex(isTuningMode && isSelected ? 1000 : 0)

        applyTuningGesture(to: wrapped)
        .contextMenu {
            Button("Control Inspector…") {
                DispatchQueue.main.async {
                    if !canonicalLayoutService.selectedIDs.contains(id) {
                        canonicalLayoutService.select(id)
                    }
                    showInspector = true
                }
            }
            Button(canonicalLayoutService.highlightedID == id ? "Unhighlight Knob" : "Highlight Knob") {
                canonicalLayoutService.toggleHighlight(id)
            }
            Divider()
            Button("Set as Key Object") {
                canonicalLayoutService.select(id, exclusive: false)
            }
            .disabled(!selectionIDs.contains(id))
            Divider()
            Button("Reset Position") {
                canonicalLayoutService.resetControlPosition(id)
            }
        }
        .popover(isPresented: $showInspector, arrowEdge: .leading) {
            NudgeControlInspector(id: id, controlType: controlType)
        }
    }

    @ViewBuilder
    private func applyTuningGesture<Wrapped: View>(to view: Wrapped) -> some View {
        if isTuningMode {
            view
                .contentShape(Rectangle())
                .highPriorityGesture(tuningDragGesture, including: .all)
        } else {
            view
        }
    }

    private var tuningDragGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("wavePanel"))
            .onChanged { value in
                guard isTuningMode else { return }

                if !tuningDragActive {
                    tuningDragActive = true
                    showInspector = false
                    shiftToggleHandledOnBegin = false
                    let shift = NSEvent.modifierFlags.contains(.shift)
                    if shift {
                        canonicalLayoutService.toggleSelection(id)
                        shiftToggleHandledOnBegin = true
                    } else if !canonicalLayoutService.selectedIDs.contains(id) {
                        canonicalLayoutService.select(id)
                    }
                }

                guard canonicalLayoutService.selectedIDs.contains(id) else { return }

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
                defer {
                    tuningDragActive = false
                    shiftToggleHandledOnBegin = false
                }

                let moved = value.translation.width.magnitude > 3 || value.translation.height.magnitude > 3
                if moved {
                    canonicalLayoutService.commitDrag()
                } else {
                    let shift = NSEvent.modifierFlags.contains(.shift)
                    if shift {
                        if !shiftToggleHandledOnBegin {
                            canonicalLayoutService.toggleSelection(id)
                        }
                    } else {
                        canonicalLayoutService.select(id)
                    }
                    canonicalLayoutService.activeDragDelta = .zero
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
