//
//  LayoutOffsetService.swift
//  brWave
//
//  Persistent per-control position and font-size overrides for the panel editor.
//  Ported from OBsixer — renamed UserDefaults keys to brWave namespace.
//

import SwiftUI
import Combine

// Per-element style overrides set via the nudge inspector.
// labelFontSize / valueFontSize of 0 means "use theme default".
struct NudgeStyle: Codable, Equatable {
    var labelFontSize: CGFloat = 0
    var valueFontSize: CGFloat = 0
    var knobSize:      CGFloat = 0   // 0 = use the declared size
    var highlighted:   Bool    = false
}

class LayoutOffsetService: ObservableObject {
    static let shared = LayoutOffsetService()

    @Published var offsets:         [String: CGSize]    = [:]
    @Published var styles:          [String: NudgeStyle] = [:]
    @Published var selectedIDs:     Set<String>          = []
    @Published var keyObjectID:     String?              = nil
    @Published var activeDragDelta: CGSize               = .zero
    @Published var registeredIDs:   Set<String>          = []
    var baseFrames:                  [String: CGRect]    = [:]

    private let saveKey  = "brWaveLayoutOffsets"
    private let styleKey = "brWaveLayoutStyles"
    private var eventMonitor: Any?

    init() {
        loadOffsets()
        loadStyles()
        setupEventMonitor()
    }

    deinit {
        if let monitor = eventMonitor { NSEvent.removeMonitor(monitor) }
    }

    private func setupEventMonitor() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            guard !self.selectedIDs.isEmpty else { return event }

            let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1

            switch event.keyCode {
            case 48:  self.selectNext();                    return nil  // Tab
            case 123: self.nudgeSelection(x: -step, y: 0); return nil  // ←
            case 124: self.nudgeSelection(x:  step, y: 0); return nil  // →
            case 125: self.nudgeSelection(x: 0, y:  step); return nil  // ↓
            case 126: self.nudgeSelection(x: 0, y: -step); return nil  // ↑
            default:  break
            }
            return event
        }
    }

    // MARK: - Offset

    func offset(for id: String) -> CGSize { offsets[id] ?? .zero }
    func setOffset(_ id: String, offset: CGSize) { offsets[id] = offset; saveOffsets() }
    func resetOffset(_ id: String) { offsets.removeValue(forKey: id); saveOffsets() }

    func reportFrame(_ id: String, _ frame: CGRect) { baseFrames[id] = frame }

    // MARK: - Style

    func style(for id: String) -> NudgeStyle { styles[id] ?? NudgeStyle() }

    func setLabelFontSize(_ id: String, size: CGFloat) {
        var s = style(for: id); s.labelFontSize = size; styles[id] = s; saveStyles()
    }
    func setValueFontSize(_ id: String, size: CGFloat) {
        var s = style(for: id); s.valueFontSize = size; styles[id] = s; saveStyles()
    }
    func setKnobSize(_ id: String, size: CGFloat) {
        var s = style(for: id); s.knobSize = size; styles[id] = s; saveStyles()
    }
    func setHighlighted(_ id: String, _ on: Bool) {
        var s = style(for: id); s.highlighted = on; styles[id] = s; saveStyles()
    }
    func resetStyle(_ id: String) { styles.removeValue(forKey: id); saveStyles() }

    func resetAll() {
        offsets.removeAll(); styles.removeAll()
        saveOffsets(); saveStyles()
    }

    // MARK: - Registry

    func register(_ id: String)   { registeredIDs.insert(id) }
    func unregister(_ id: String) { registeredIDs.remove(id) }

    func selectNext() {
        let sorted = registeredIDs.sorted()
        guard !sorted.isEmpty else { return }
        guard let current = selectedIDs.first,
              let idx = sorted.firstIndex(of: current) else {
            sorted.first.map { select($0) }; return
        }
        select(sorted[(idx + 1) % sorted.count])
    }

    // MARK: - Selection

    func select(_ id: String, exclusive: Bool = true) {
        if exclusive {
            selectedIDs = [id]; keyObjectID = id
        } else {
            selectedIDs.insert(id)
            if keyObjectID == nil { keyObjectID = id }
        }
    }

    func deselect(_ id: String) {
        selectedIDs.remove(id)
        if keyObjectID == id { keyObjectID = selectedIDs.first }
    }

    func toggleSelection(_ id: String) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
            if keyObjectID == id { keyObjectID = selectedIDs.first }
        } else {
            selectedIDs.insert(id)
            if keyObjectID == nil { keyObjectID = id }
        }
    }

    func clearSelection() { selectedIDs.removeAll(); keyObjectID = nil }

    func selectAtPoint(_ point: CGPoint, shift: Bool = false) {
        let hits = baseFrames
            .filter { _, frame in frame.insetBy(dx: -6, dy: -6).contains(point) }
            .sorted { a, b in (a.value.width * a.value.height) < (b.value.width * b.value.height) }
        guard let best = hits.first else {
            if !shift { clearSelection() }; return
        }
        if shift { toggleSelection(best.key) } else { select(best.key) }
    }

    // MARK: - Drag

    func updateDrag(delta: CGSize) { activeDragDelta = delta }

    func commitDrag() {
        guard activeDragDelta != .zero else { return }
        for id in selectedIDs {
            let c = offsets[id] ?? .zero
            offsets[id] = CGSize(width: c.width + activeDragDelta.width,
                                 height: c.height + activeDragDelta.height)
        }
        activeDragDelta = .zero
        saveOffsets()
    }

    // MARK: - Nudge

    func nudgeSelection(x: CGFloat, y: CGFloat) {
        guard !selectedIDs.isEmpty else { return }
        for id in selectedIDs {
            let c = offsets[id] ?? .zero
            offsets[id] = CGSize(width: c.width + x, height: c.height + y)
        }
        saveOffsets()
    }

    // MARK: - Alignment

    enum AlignmentEdge { case left, center, right, top, middle, bottom }

    private func vMinX(_ id: String) -> CGFloat { baseFrames[id]?.minX ?? 0 }
    private func vMaxX(_ id: String) -> CGFloat { baseFrames[id]?.maxX ?? 0 }
    private func vMidX(_ id: String) -> CGFloat { baseFrames[id]?.midX ?? 0 }
    private func vMinY(_ id: String) -> CGFloat { baseFrames[id]?.minY ?? 0 }
    private func vMaxY(_ id: String) -> CGFloat { baseFrames[id]?.maxY ?? 0 }
    private func vMidY(_ id: String) -> CGFloat { baseFrames[id]?.midY ?? 0 }

    func alignSelected(to edge: AlignmentEdge) {
        guard selectedIDs.count > 1 else { return }
        let anchor = keyObjectID ?? selectedIDs.first!
        guard baseFrames[anchor] != nil else { return }
        let ids = Array(selectedIDs)

        switch edge {
        case .left:
            let t = vMinX(anchor)
            for id in ids { guard let f = baseFrames[id] else { continue }
                var o = offsets[id] ?? .zero; o.width += t - f.minX; offsets[id] = o }
        case .right:
            let t = vMaxX(anchor)
            for id in ids { guard let f = baseFrames[id] else { continue }
                var o = offsets[id] ?? .zero; o.width += t - f.maxX; offsets[id] = o }
        case .center:
            let t = vMidX(anchor)
            for id in ids { guard let f = baseFrames[id] else { continue }
                var o = offsets[id] ?? .zero; o.width += t - f.midX; offsets[id] = o }
        case .top:
            let t = vMinY(anchor)
            for id in ids { guard let f = baseFrames[id] else { continue }
                var o = offsets[id] ?? .zero; o.height += t - f.minY; offsets[id] = o }
        case .bottom:
            let t = vMaxY(anchor)
            for id in ids { guard let f = baseFrames[id] else { continue }
                var o = offsets[id] ?? .zero; o.height += t - f.maxY; offsets[id] = o }
        case .middle:
            let t = vMidY(anchor)
            for id in ids { guard let f = baseFrames[id] else { continue }
                var o = offsets[id] ?? .zero; o.height += t - f.midY; offsets[id] = o }
        }
        saveOffsets()
    }

    func distributeSelected(horizontal: Bool) {
        guard selectedIDs.count > 2 else { return }
        let ids = Array(selectedIDs).filter { baseFrames[$0] != nil }
        guard ids.count > 2 else { return }

        if horizontal {
            let sorted = ids.sorted { vMidX($0) < vMidX($1) }
            guard let first = sorted.first, let last = sorted.last else { return }
            let startX = vMidX(first); let endX = vMidX(last)
            guard endX > startX else { return }
            let step = (endX - startX) / CGFloat(sorted.count - 1)
            for (i, id) in sorted.enumerated() {
                guard let f = baseFrames[id] else { continue }
                var o = offsets[id] ?? .zero; o.width += (startX + CGFloat(i) * step) - f.midX; offsets[id] = o
            }
        } else {
            let sorted = ids.sorted { vMidY($0) < vMidY($1) }
            guard let first = sorted.first, let last = sorted.last else { return }
            let startY = vMidY(first); let endY = vMidY(last)
            guard endY > startY else { return }
            let step = (endY - startY) / CGFloat(sorted.count - 1)
            for (i, id) in sorted.enumerated() {
                guard let f = baseFrames[id] else { continue }
                var o = offsets[id] ?? .zero; o.height += (startY + CGFloat(i) * step) - f.midY; offsets[id] = o
            }
        }
        saveOffsets()
    }

    // MARK: - Persistence

    private func saveOffsets() {
        if let data = try? JSONEncoder().encode(offsets) {
            UserDefaults.standard.set(data, forKey: saveKey)
        }
    }
    private func loadOffsets() {
        if let data = UserDefaults.standard.data(forKey: saveKey),
           let decoded = try? JSONDecoder().decode([String: CGSize].self, from: data) {
            offsets = decoded
        }
    }
    private func saveStyles() {
        if let data = try? JSONEncoder().encode(styles) {
            UserDefaults.standard.set(data, forKey: styleKey)
        }
    }
    private func loadStyles() {
        if let data = UserDefaults.standard.data(forKey: styleKey),
           let decoded = try? JSONDecoder().decode([String: NudgeStyle].self, from: data) {
            styles = decoded
        }
    }

    // MARK: - Export overrides → clipboard

    func exportOverridesToClipboard() {
        var lines: [String] = ["=== brWave Layout Overrides – \(formattedDate()) ===", ""]

        let knobSizes:  [(String, CGFloat)] = styles.compactMap { id, s in s.knobSize      > 0 ? (id, s.knobSize)      : nil }.sorted { $0.0 < $1.0 }
        let labelFonts: [(String, CGFloat)] = styles.compactMap { id, s in s.labelFontSize > 0 ? (id, s.labelFontSize) : nil }.sorted { $0.0 < $1.0 }
        let valueFonts: [(String, CGFloat)] = styles.compactMap { id, s in s.valueFontSize > 0 ? (id, s.valueFontSize) : nil }.sorted { $0.0 < $1.0 }
        let offsetList: [(String, CGSize)]  = offsets.filter { $0.value != .zero }.sorted { $0.key < $1.key }

        if !knobSizes.isEmpty {
            lines.append("-- Knob size overrides --")
            for (id, sz) in knobSizes { lines.append("  \(id): \(knobSizeName(sz))  (\(Int(sz))px)") }
            lines.append("")
        }
        if !labelFonts.isEmpty {
            lines.append("-- Label font overrides --")
            for (id, sz) in labelFonts { lines.append("  \(id): labelFontSize: \(Int(sz))pt") }
            lines.append("")
        }
        if !valueFonts.isEmpty {
            lines.append("-- Value font overrides --")
            for (id, sz) in valueFonts { lines.append("  \(id): valueFontSize: \(Int(sz))pt") }
            lines.append("")
        }
        if !offsetList.isEmpty {
            lines.append("-- Position offsets --")
            for (id, off) in offsetList { lines.append("  \(id): x \(Int(off.width))  y \(Int(off.height))") }
            lines.append("")
        }
        if lines.count == 2 { lines.append("(no overrides active)") }

        let text = lines.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        print(text)
    }

    private func knobSizeName(_ size: CGFloat) -> String {
        switch size {
        case Theme.knobSizeMini:   return "Theme.knobSizeMini"
        case Theme.knobSizeSmall:  return "Theme.knobSizeSmall"
        case Theme.knobSizeMedium: return "Theme.knobSizeMedium"
        case Theme.knobSizeLarge:  return "Theme.knobSizeLarge"
        default:                   return "\(Int(size))px"
        }
    }

    private func formattedDate() -> String {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short
        return f.string(from: Date())
    }
}
