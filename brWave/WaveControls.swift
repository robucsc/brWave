//
//  WaveControls.swift
//  brWave
//
//  Reusable panel controls for the Behringer Wave editor.
//  All controls are group-aware (Group A / Group B).
//
//  Key brWave-specific feature: WaveKnobControl shows a ghost arc
//  for the inactive group, giving an instant visual diff without switching.
//

import SwiftUI
import AppKit

// MARK: - Environment Keys

private struct WaveControlHighlightKey: EnvironmentKey {
    static let defaultValue: Color = Theme.waveHighlight
}
private struct WaveGroupBHighlightKey: EnvironmentKey {
    static let defaultValue: Color = Theme.waveGroupBHighlight
}
private struct WaveGroupKey: EnvironmentKey {
    static let defaultValue: WaveGroup = .a
}

extension EnvironmentValues {
    var waveControlHighlight: Color {
        get { self[WaveControlHighlightKey.self] }
        set { self[WaveControlHighlightKey.self] = newValue }
    }
    var waveGroupBHighlight: Color {
        get { self[WaveGroupBHighlightKey.self] }
        set { self[WaveGroupBHighlightKey.self] = newValue }
    }
    var waveActiveGroup: WaveGroup {
        get { self[WaveGroupKey.self] }
        set { self[WaveGroupKey.self] = newValue }
    }
}

// MARK: - WaveKnobControl

/// Rotary knob for one Wave parameter.
/// Outer ring = Group A value (cyan). Inner ring = Group B value (white).
/// Positions are fixed — switching A/B never swaps the rings, only adjusts which is bright.
/// Scroll-wheel + vertical drag to adjust the active group.
struct WaveKnobControl: View {
    @ObservedObject var patch: Patch
    let id: WaveParamID
    var size: CGFloat = Theme.knobSizeMedium
    var labelOverride: String? = nil
    var valueTextOverride: String? = nil
    var nudgeIDOverride: String? = nil

    @Environment(\.undoManager)           private var undoManager
    @Environment(\.isTuningMode)          private var isTuningMode
    @Environment(\.waveControlHighlight)  private var colorA   // cyan — Group A
    @Environment(\.waveGroupBHighlight)   private var colorB   // white — Group B
    @Environment(\.waveActiveGroup)       private var group
    @ObservedObject private var canonicalLayoutService = WavePanelLayoutService.shared

    @State private var dragStartNorm: Double = 0
    @GestureState private var isDragging = false
    @State private var isUserDragging = false
    @State private var isScrolling = false
    @State private var isHovering = false
    @State private var animatedValue: Double = 0  // tracks active group, animated
    @State private var isEditingValue = false
    @State private var editingText = ""
    @State private var shouldFocusEditor = false

    private var descriptor: WaveParamDescriptor? { WaveParameters.byID[id] }
    private var currentValue: Int {
        let raw = patch.value(for: id, group: group)
        guard let d = descriptor else { return raw }
        return min(max(raw, d.range.lowerBound), d.range.upperBound)
    }

    private var isPerGroup: Bool {
        if id == .wavetb { return true }
        guard let d = descriptor else { return false }
        if case .perGroup = d.storage { return true }
        return false
    }

    // Group A and B normalized values — always fixed regardless of active group
    private var normalizedA: Double { normalized(for: .a) }
    private var normalizedB: Double { normalized(for: .b) }
    private func normalized(for g: WaveGroup) -> Double {
        guard let d = descriptor else { return 0 }
        let lo = Double(d.range.lowerBound), hi = Double(d.range.upperBound)
        guard hi > lo else { return 0 }
        let raw = patch.value(for: id, group: g)
        let clamped = min(max(raw, d.range.lowerBound), d.range.upperBound)
        return (Double(clamped) - lo) / (hi - lo)
    }

    private var normalizedValue: Double { group == .a ? normalizedA : normalizedB }
    private var label: String { labelOverride ?? descriptor?.shortName ?? id.rawValue }
    private var nudgeID: String { nudgeIDOverride ?? id.rawValue }
    private var effectiveKnobSize: CGFloat {
        canonicalLayoutService.knobSize(for: nudgeID) ?? size
    }
    private let effectiveLabelSize: CGFloat = 9
    private let effectiveValueSize: CGFloat = 9

    // Active group colour for value readout
    private var activeColor: Color { group == .a ? colorA : colorB }
    private var tuningSelectionIDs: Set<String> {
        canonicalLayoutService.selectedIDs
    }
    private var tuningKeyObjectID: String? {
        canonicalLayoutService.keyObjectID
    }
    private var isPersistentHighlight: Bool {
        canonicalLayoutService.highlightedID == nudgeID
    }

    var body: some View {
        VStack(spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: effectiveLabelSize, weight: .bold))
                .tracking(1.0)
                .foregroundStyle(Color.white.opacity(0.4))
                .lineLimit(1)

            knobGraphic(size: effectiveKnobSize)
                .gesture(dragGesture)
                .modifier(WaveScrollModifier(
                    onScroll: { delta in adjustValue(by: delta) },
                    isScrolling: $isScrolling
                ))
                .onHover { isHovering = $0 }
                .onAppear { animatedValue = normalizedValue }
                .onChange(of: normalizedValue) { _, v in
                    if isUserDragging {
                        animatedValue = v
                    } else {
                        withAnimation(.easeInOut(duration: 0.2)) { animatedValue = v }
                    }
                }

            valueEditor
        }
        .contentShape(Rectangle())
        .nudgeable(id: nudgeID, controlType: .knob(size: effectiveKnobSize))
    }

    // MARK: - Knob graphic

    private func knobGraphic(size s: CGFloat) -> some View {
        let outerArcW: CGFloat = 3.5
        let innerArcW: CGFloat = 2.8
        let capS = s - 20
        let innerS = s - 14
        let trenchColor = Color(white: 0.24)

        // Outer ring = Group A (always), inner ring = Group B (always)
        let aNorm = group == .a ? CGFloat(animatedValue) : CGFloat(normalizedA)
        let bNorm = group == .b ? CGFloat(animatedValue) : CGFloat(normalizedB)
        let aOpacity: Double = group == .a ? 1.0 : 0.88
        let bOpacity: Double = group == .b ? 1.0 : 0.96

        return ZStack {
            // Persistent UI highlight: a soft blue halo around the knob body,
            // not another value arc lane.
            if !isTuningMode && isPersistentHighlight {
                Circle()
                    .strokeBorder(colorA.opacity(0.82), lineWidth: max(1.2, s * 0.02))
                    .frame(width: capS + 10, height: capS + 10)
                    .shadow(color: colorA.opacity(0.45), radius: 4, x: 0, y: 0)
            }

            // Outer track — Group A lane
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(trenchColor.opacity(0.42),
                        style: StrokeStyle(lineWidth: outerArcW, lineCap: .butt))
                .rotationEffect(.degrees(135))
                .frame(width: s, height: s)

            // Inner track — Group B lane
            if isPerGroup {
                Circle()
                    .trim(from: 0, to: 0.75)
                    .stroke(trenchColor.opacity(0.34),
                            style: StrokeStyle(lineWidth: innerArcW, lineCap: .butt))
                    .rotationEffect(.degrees(135))
                    .frame(width: innerS, height: innerS)
            }

            // Group A arc — always outer ring, cyan
            Circle()
                .trim(from: 0, to: aNorm * 0.75)
                .stroke(colorA.opacity(aOpacity),
                        style: StrokeStyle(lineWidth: outerArcW, lineCap: .round))
                .rotationEffect(.degrees(135))
                .frame(width: s, height: s)

            // Group B arc — always inner ring, white
            if isPerGroup {
                Circle()
                    .trim(from: 0, to: bNorm * 0.75)
                    .stroke(Color.black.opacity(0.55),
                            style: StrokeStyle(lineWidth: innerArcW + 1.0, lineCap: .round))
                    .rotationEffect(.degrees(135))
                    .frame(width: innerS, height: innerS)
                Circle()
                    .trim(from: 0, to: bNorm * 0.75)
                    .stroke(colorB.opacity(bOpacity),
                            style: StrokeStyle(lineWidth: innerArcW, lineCap: .round))
                    .rotationEffect(.degrees(135))
                    .frame(width: innerS, height: innerS)
            }

            // Cap
            Circle()
                .fill(LinearGradient(
                    colors: [Color(white: 0.22), Color(white: 0.12)],
                    startPoint: .top, endPoint: .bottom
                ))
                .overlay(
                    Circle().strokeBorder(
                        LinearGradient(
                            colors: [Color(white: 0.3), Color(white: 0.05)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
                )
                .frame(width: capS, height: capS)
                .shadow(color: .black.opacity(0.5), radius: 3, x: 0, y: 2)
                .overlay(
                    Capsule()
                        .fill(activeColor.opacity(0.95))
                        .frame(width: max(1.75, s * 0.035), height: capS * 0.35)
                        .offset(y: -capS * 0.24)
                        .rotationEffect(.degrees(animatedValue * 270 - 135))
                )

            // Tuning mode selection ring
            if isTuningMode && tuningSelectionIDs.contains(id.rawValue) {
                let isKey = tuningKeyObjectID == id.rawValue
                Circle()
                    .strokeBorder(activeColor.opacity(isKey ? 1.0 : 0.55),
                                  lineWidth: isKey ? 2.5 : 1.5)
                    .frame(width: s + 8, height: s + 8)
            } else if isHovering || isDragging {
                Circle()
                    .strokeBorder(activeColor.opacity(0.4), lineWidth: 1)
                    .frame(width: s + 4, height: s + 4)
            }
        }
        .frame(width: s, height: s)
        .contentShape(Circle())
    }

    // MARK: - Drag

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($isDragging) { _, state, _ in
                if !state { undoManager?.beginUndoGrouping() }
                state = true
            }
            .onChanged { drag in
                isUserDragging = true
                if drag.translation == .zero { dragStartNorm = normalizedValue }
                let delta = Double(-drag.translation.height) * 0.005
                setNormalized(dragStartNorm + delta)
            }
            .onEnded { _ in
                isUserDragging = false
                undoManager?.endUndoGrouping()
            }
    }

    private func adjustValue(by delta: Double) { setNormalized(normalizedValue + delta) }

    private func setNormalized(_ norm: Double) {
        guard let d = descriptor else { return }
        let clamped = min(max(norm, 0), 1)
        let lo = Double(d.range.lowerBound), hi = Double(d.range.upperBound)
        let raw = Int(round(lo + clamped * (hi - lo)))
        patch.setValue(raw, for: id, group: group)
        MIDIController.shared.sendParameterChange(id: id, value: raw, group: group)
        animatedValue = clamped
    }

    @ViewBuilder
    private var valueEditor: some View {
        if let valueTextOverride {
            Text(valueTextOverride)
                .font(.system(size: effectiveValueSize, weight: .black, design: .monospaced))
                .foregroundStyle(activeColor)
                .frame(minWidth: max(42, effectiveKnobSize + 10), minHeight: 18)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        } else if isEditingValue {
            WaveInlineNumberTextField(
                text: $editingText,
                shouldFocus: $shouldFocusEditor,
                onCommit: commitValueEdit,
                onCancel: cancelValueEdit,
                textColor: activeColor
            )
            .frame(width: max(42, effectiveKnobSize - 12), height: 18)
        } else {
            Text("\(currentValue)")
                .font(.system(size: effectiveValueSize, weight: .black, design: .monospaced))
                .foregroundStyle(activeColor)
                .frame(minWidth: max(42, effectiveKnobSize - 12), minHeight: 18)
                .lineLimit(1)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { beginValueEdit() }
        }
    }

    private func beginValueEdit() {
        editingText = "\(currentValue)"
        isEditingValue = true
        shouldFocusEditor = true
    }

    private func commitValueEdit() {
        guard let d = descriptor,
              let typedValue = Int(editingText.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            cancelValueEdit()
            return
        }

        let raw = min(max(typedValue, d.range.lowerBound), d.range.upperBound)
        let lo = Double(d.range.lowerBound)
        let hi = Double(d.range.upperBound)
        let normalized = hi > lo ? (Double(raw) - lo) / (hi - lo) : 0
        patch.setValue(raw, for: id, group: group)
        MIDIController.shared.sendParameterChange(id: id, value: raw, group: group)
        animatedValue = normalized
        isEditingValue = false
        shouldFocusEditor = false
    }

    private func cancelValueEdit() {
        isEditingValue = false
        shouldFocusEditor = false
    }
}

private struct WaveInlineNumberTextField: NSViewRepresentable {
    @Binding var text: String
    @Binding var shouldFocus: Bool

    let onCommit: () -> Void
    let onCancel: () -> Void
    let textColor: Color

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, shouldFocus: $shouldFocus, onCommit: onCommit, onCancel: onCancel)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.delegate = context.coordinator
        field.isBordered = false
        field.focusRingType = .none
        field.drawsBackground = true
        field.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.35)
        field.textColor = NSColor(textColor)
        field.alignment = .center
        field.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
        field.stringValue = text
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        nsView.textColor = NSColor(textColor)

        if shouldFocus, nsView.window != nil, nsView.currentEditor() == nil {
            nsView.window?.makeFirstResponder(nsView)
            DispatchQueue.main.async {
                nsView.currentEditor()?.selectAll(nil)
                shouldFocus = false
            }
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding var text: String
        @Binding var shouldFocus: Bool

        let onCommit: () -> Void
        let onCancel: () -> Void
        private var didHandleCommand = false

        init(text: Binding<String>, shouldFocus: Binding<Bool>, onCommit: @escaping () -> Void, onCancel: @escaping () -> Void) {
            _text = text
            _shouldFocus = shouldFocus
            self.onCommit = onCommit
            self.onCancel = onCancel
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)):
                didHandleCommand = true
                onCommit()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                didHandleCommand = true
                onCancel()
                return true
            default:
                return false
            }
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            defer { didHandleCommand = false }
            if didHandleCommand { return }
            onCancel()
        }
    }
}

// MARK: - WaveLEDRadio

/// Vertical radio list with concentric dual-group indicators.
/// Outer dot = active group selection. Inner dot = other group selection.
/// Same highlight colour as knob arcs — consistent visual language.
struct WaveLEDRadio: View {
    @ObservedObject var patch: Patch
    let id: WaveParamID
    let options: [String]
    var label: String? = nil

    @Environment(\.waveActiveGroup)      private var group
    @Environment(\.waveControlHighlight) private var colorA
    @Environment(\.waveGroupBHighlight)  private var colorB

    private var isPerGroup: Bool {
        guard let d = WaveParameters.descriptor(for: id) else { return false }
        if case .perGroup = d.storage { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let label {
                Text(label.uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                ForEach(0..<options.count, id: \.self) { index in
                    HStack(spacing: 7) {
                        // Outer dot = Group A (always), Inner dot = Group B (always)
                        ZStack {
                            let aOn = patch.value(for: id, group: .a) == index
                            Circle()
                                .fill(aOn ? colorA.opacity(group == .a ? 1.0 : 0.35) : Color.white.opacity(0.07))
                                .frame(width: 8, height: 8)
                                .shadow(color: aOn ? colorA.opacity(0.45) : .clear, radius: 3)
                            if isPerGroup {
                                let bOn = patch.value(for: id, group: .b) == index
                                Circle()
                                    .fill(bOn ? colorB.opacity(group == .b ? 1.0 : 0.35) : Color.black.opacity(0.55))
                                    .frame(width: 3.5, height: 3.5)
                            }
                        }
                        .frame(width: 10, height: 10)

                        Text(options[index])
                            .font(.system(size: 10,
                                          weight: patch.value(for: id, group: group) == index ? .semibold : .regular))
                            .foregroundStyle(patch.value(for: id, group: group) == index
                                             ? Color.white : Color.white.opacity(0.4))
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { patch.setValue(index, for: id, group: group) }
                }
            }
        }
        .nudgeable(id: id.rawValue, controlType: .toggle)
    }
}

// MARK: - WaveStepControl

struct WaveStepControl: View {
    @ObservedObject var patch: Patch
    let id: WaveParamID
    var label: String? = nil

    @Environment(\.waveActiveGroup) private var group
    private var descriptor: WaveParamDescriptor? { WaveParameters.descriptor(for: id) }
    private var val: Int { patch.value(for: id, group: group) }

    var body: some View {
        HStack(spacing: 8) {
            if let label {
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.5))
                    .frame(width: 70, alignment: .leading)
            }
            
            HStack(spacing: 0) {
                Button(action: { decrement() }) {
                    Image(systemName: "minus")
                        .font(.system(size: 8, weight: .bold))
                        .frame(width: 20, height: 18)
                        .background(Color.white.opacity(0.05))
                }
                .buttonStyle(.plain)
                
                Text("\(val)")
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .foregroundStyle(Theme.waveHighlight)
                    .frame(width: 24, height: 18)
                    .background(Color.black.opacity(0.3))
                
                Button(action: { increment() }) {
                    Image(systemName: "plus")
                        .font(.system(size: 8, weight: .bold))
                        .frame(width: 20, height: 18)
                        .background(Color.white.opacity(0.05))
                }
                .buttonStyle(.plain)
            }
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.white.opacity(0.1), lineWidth: 1))
        }
        .nudgeable(id: id.rawValue, controlType: .toggle)
    }

    private func increment() {
        guard let d = descriptor else { return }
        if val < d.range.upperBound { patch.setValue(val + 1, for: id, group: group) }
    }
    private func decrement() {
        guard let d = descriptor else { return }
        if val > d.range.lowerBound { patch.setValue(val - 1, for: id, group: group) }
    }
}

// MARK: - WaveLEDToggle

/// Single on/off LED with concentric dual-group indicator.
/// Outer dot = active group state. Inner dot = other group state.
struct WaveLEDToggle: View {
    @ObservedObject var patch: Patch
    let id: WaveParamID
    var label: String? = nil

    @Environment(\.waveActiveGroup)      private var group
    @Environment(\.waveControlHighlight) private var colorA
    @Environment(\.waveGroupBHighlight)  private var colorB

    private var isOn: Bool { patch.value(for: id, group: group) != 0 }
    private var aIsOn: Bool { patch.value(for: id, group: .a) != 0 }
    private var bIsOn: Bool { patch.value(for: id, group: .b) != 0 }
    private var isPerGroup: Bool {
        guard let d = WaveParameters.descriptor(for: id) else { return false }
        if case .perGroup = d.storage { return true }
        return false
    }

    var body: some View {
        Button {
            patch.setValue(isOn ? 0 : 1, for: id, group: group)
        } label: {
            HStack(spacing: 7) {
                // Outer dot = Group A, inner dot = Group B — fixed positions
                ZStack {
                    Circle()
                        .fill(aIsOn ? colorA.opacity(group == .a ? 1.0 : 0.35) : Color.white.opacity(0.07))
                        .frame(width: 8, height: 8)
                        .shadow(color: aIsOn ? colorA.opacity(0.45) : .clear, radius: 3)
                    if isPerGroup {
                        Circle()
                            .fill(bIsOn ? colorB.opacity(group == .b ? 1.0 : 0.35) : Color.black.opacity(0.55))
                            .frame(width: 3.5, height: 3.5)
                    }
                }
                .frame(width: 10, height: 10)

                if let label {
                    Text(label.uppercased())
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(isOn ? Color.white : Color.white.opacity(0.4))
                        .lineLimit(1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .nudgeable(id: id.rawValue, controlType: .toggle)
    }
}

// MARK: - WaveMenuPicker

struct WaveMenuPicker: View {
    @ObservedObject var patch: Patch
    let id: WaveParamID
    let options: [String]
    var label: String? = nil

    @Environment(\.waveActiveGroup)      private var group
    @Environment(\.waveControlHighlight) private var highlight

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let label {
                Text(label.uppercased())
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.secondary)
            }
            Picker("", selection: Binding(
                get: { patch.value(for: id, group: group) },
                set: { patch.setValue($0, for: id, group: group) }
            )) {
                ForEach(Array(options.enumerated()), id: \.offset) { index, name in
                    Text(name).tag(index)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .tint(highlight)
            .controlSize(.small)
        }
        .nudgeable(id: id.rawValue, controlType: .menu)
    }
}

// MARK: - Scroll wheel support

struct WaveScrollModifier: ViewModifier {
    let onScroll: (Double) -> Void
    var isScrolling: Binding<Bool>?
    @State private var isHovering = false
    @State private var scrollEndTask: DispatchWorkItem?

    func body(content: Content) -> some View {
        content
            .onHover { isHovering = $0 }
            .background(
                WaveScrollMonitor(isHovering: $isHovering, onScroll: { delta in
                    if let isScrolling {
                        isScrolling.wrappedValue = true
                        scrollEndTask?.cancel()
                        let task = DispatchWorkItem { isScrolling.wrappedValue = false }
                        scrollEndTask = task
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: task)
                    }
                    onScroll(delta)
                })
            )
    }
}

struct WaveScrollMonitor: NSViewRepresentable {
    @Binding var isHovering: Bool
    let onScroll: (Double) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = PassthroughView()
        let monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) {
            [weak coordinator = context.coordinator] event in
            guard let coordinator else { return event }
            if coordinator.parent.isHovering {
                let delta = Double(-event.scrollingDeltaY) * 0.005
                DispatchQueue.main.async { coordinator.parent.onScroll(delta) }
                return nil
            }
            return event
        }
        context.coordinator.monitor = monitor
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.parent = self
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        if let m = coordinator.monitor { NSEvent.removeMonitor(m) }
    }

    class Coordinator {
        var parent: WaveScrollMonitor
        var monitor: Any?
        init(parent: WaveScrollMonitor) { self.parent = parent }
    }

    final class PassthroughView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }
    }
}

struct WaveKnobDragCapture: NSViewRepresentable {
    let onBegin: () -> Void
    let onDrag: (CGFloat) -> Void
    let onEnd: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onBegin: onBegin, onDrag: onDrag, onEnd: onEnd)
    }

    func makeNSView(context: Context) -> DragView {
        let view = DragView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: DragView, context: Context) {
        nsView.coordinator = context.coordinator
    }

    final class Coordinator {
        let onBegin: () -> Void
        let onDrag: (CGFloat) -> Void
        let onEnd: () -> Void

        init(onBegin: @escaping () -> Void, onDrag: @escaping (CGFloat) -> Void, onEnd: @escaping () -> Void) {
            self.onBegin = onBegin
            self.onDrag = onDrag
            self.onEnd = onEnd
        }
    }

    final class DragView: NSView {
        var coordinator: Coordinator?
        private var startPoint: NSPoint = .zero
        private var dragging = false

        override var acceptsFirstResponder: Bool { true }

        override func hitTest(_ point: NSPoint) -> NSView? {
            self
        }

        override func mouseDown(with event: NSEvent) {
            dragging = true
            startPoint = convert(event.locationInWindow, from: nil)
            coordinator?.onBegin()
        }

        override func mouseDragged(with event: NSEvent) {
            guard dragging else { return }
            let point = convert(event.locationInWindow, from: nil)
            coordinator?.onDrag(point.y - startPoint.y)
        }

        override func mouseUp(with event: NSEvent) {
            guard dragging else { return }
            dragging = false
            coordinator?.onEnd()
        }
    }
}
