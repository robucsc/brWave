import SwiftUI
import Combine
import AppKit

// MARK: - PanelLayoutService
//
// Single source of truth for all panel and control layout positions.
// Persists to PanelLayout.plist in the source directory (git-tracked).
// #filePath locates the file at compile time — no App Support, no hardcoded paths.
// Edit mode is DEBUG-only; the plist ships in the bundle for release builds.

@MainActor
final class PanelLayoutService: ObservableObject {

    static let shared = PanelLayoutService()

    // MARK: - Published state

    @Published private(set) var panelFrames:  [String: CGRect] = [:]
    @Published var knobSizes:                 [String: CGFloat] = [:]
    @Published var controlFrames:             [String: CGRect]  = [:]
    @Published var selectedIDs:               Set<String>       = []
    @Published var keyObjectID:               String?           = nil
    @Published var highlightedID:             String?           = nil
    @Published var activeDragDelta:           CGSize            = .zero

    // Live frame tracking (populated by GeometryReader, not persisted)
    private(set) var baseFrames:        [String: CGRect]  = [:]
    private(set) var liveSectionFrames: [String: CGRect]  = [:]
    private(set) var controlSectionIDs: [String: String]  = [:]

    private var eventMonitor:      Any?
    private var terminateObserver: Any?
    private var saveWorkItem:      DispatchWorkItem?

    private static let panelSelectionPrefix = "panel:"
    private let panelGap: CGFloat = 20

    // MARK: - Codable storage

    private struct StoredRect: Codable {
        var x, y, w, h: Double
        var cgRect: CGRect { CGRect(x: x, y: y, width: w, height: h) }
        init(_ r: CGRect) { x = r.minX; y = r.minY; w = r.width; h = r.height }
    }

    private struct LayoutFile: Codable {
        var panels:    [String: StoredRect] = [:]
        var controls:  [String: StoredRect] = [:]
        var knobSizes: [String: Double]     = [:]
    }

    // App Support — writable under sandbox. Bundle plist seeds it on first launch.
    private static let fileURL: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("brWave", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("PanelLayout.plist")
    }()

    // MARK: - Init / deinit

    private init() {
        load()
        setupEventMonitor()
        terminateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.saveNow() } }
    }

    deinit {
        if let eventMonitor      { NSEvent.removeMonitor(eventMonitor) }
        if let terminateObserver { NotificationCenter.default.removeObserver(terminateObserver) }
    }

    // MARK: - Persistence

    private func load() {
        // Try App Support (live working copy)
        if let data = try? Data(contentsOf: Self.fileURL),
           let file = try? PropertyListDecoder().decode(LayoutFile.self, from: data) {
            panelFrames   = file.panels.mapValues(\.cgRect)
            controlFrames = file.controls.mapValues(\.cgRect)
            knobSizes     = file.knobSizes.mapValues { CGFloat($0) }
            return
        }
        // First launch — seed from bundle plist, then write to App Support
        guard let bundleURL = Bundle.main.url(forResource: "PanelLayout", withExtension: "plist"),
              let data = try? Data(contentsOf: bundleURL),
              let file = try? PropertyListDecoder().decode(LayoutFile.self, from: data) else { return }
        panelFrames   = file.panels.mapValues(\.cgRect)
        controlFrames = file.controls.mapValues(\.cgRect)
        knobSizes     = file.knobSizes.mapValues { CGFloat($0) }
        saveNow()
    }

    private func saveSoon() {
        saveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: item)
    }

    private func saveNow() {
        saveWorkItem?.cancel()
        saveWorkItem = nil
        let file = LayoutFile(
            panels:    panelFrames.mapValues   { StoredRect($0) },
            controls:  controlFrames.mapValues { StoredRect($0) },
            knobSizes: knobSizes.mapValues     { Double($0) }
        )
        guard let data = try? PropertyListEncoder().encode(file) else { return }
        try? data.write(to: Self.fileURL)
    }

    // MARK: - Accessors

    func panelFrame(for id: String) -> CGRect?  { panelFrames[id] }
    func size(for id: String) -> CGSize?         { panelFrames[id]?.size }
    func knobSize(for id: String) -> CGFloat?    { knobSizes[id] }
    func frame(for id: String) -> CGRect?        { controlFrames[id] }
    func origin(for id: String) -> CGPoint?      { controlFrames[id]?.origin }

    // MARK: - Panel selection IDs

    func isPanelSelectionID(_ id: String) -> Bool { id.hasPrefix(Self.panelSelectionPrefix) }
    func panelSelectionID(for sectionID: String) -> String { Self.panelSelectionPrefix + sectionID }
    func sectionID(for selectionID: String) -> String? {
        guard isPanelSelectionID(selectionID) else { return nil }
        return String(selectionID.dropFirst(Self.panelSelectionPrefix.count))
    }

    // MARK: - Panel frame mutations

    func seedPanelFrameIfNeeded(_ id: String, frame: CGRect) {
        guard frame != .zero, panelFrames[id] == nil else { return }
        objectWillChange.send()
        panelFrames[id] = frame
        saveSoon()
    }

    func setPanelFrame(_ id: String, frame: CGRect) {
        objectWillChange.send()
        panelFrames[id] = clamped(frame)
        saveSoon()
    }

    func setPanelFrameLive(_ id: String, frame: CGRect) {
        objectWillChange.send()
        panelFrames[id] = clamped(frame)
        saveSoon()
    }

    func setPanelOrigin(_ id: String, origin: CGPoint) {
        let size = panelFrames[id]?.size ?? .zero
        objectWillChange.send()
        panelFrames[id] = CGRect(origin: origin, size: size)
        saveSoon()
    }

    func setPanelOriginLive(_ id: String, origin: CGPoint) {
        let size = panelFrames[id]?.size ?? .zero
        objectWillChange.send()
        panelFrames[id] = CGRect(origin: origin, size: size)
        saveSoon()
    }

    func setPanelSize(_ id: String, size: CGSize) {
        let origin = panelFrames[id]?.origin ?? .zero
        objectWillChange.send()
        panelFrames[id] = CGRect(origin: origin, size: clampedSize(size))
        saveSoon()
    }

    func setPanelSizeLive(_ id: String, size: CGSize) {
        let origin = panelFrames[id]?.origin ?? .zero
        objectWillChange.send()
        panelFrames[id] = CGRect(origin: origin, size: clampedSize(size))
        saveSoon()
    }

    /// Remove the stored frame for a panel. The panel re-seeds from its default on next display.
    func removePanelFrame(_ id: String) {
        guard panelFrames[id] != nil else { return }
        objectWillChange.send()
        panelFrames.removeValue(forKey: id)
        saveSoon()
    }

    // MARK: - Control frame mutations

    func setOrigin(_ origin: CGPoint, for id: String) {
        let size = (controlFrames[id] ?? baseFrames[id] ?? .zero).size
        objectWillChange.send()
        controlFrames[id] = CGRect(origin: origin, size: size)
        saveSoon()
    }

    func setSize(_ size: CGSize, for id: String) {
        let origin = (controlFrames[id] ?? baseFrames[id] ?? .zero).origin
        objectWillChange.send()
        controlFrames[id] = CGRect(origin: origin, size: clampedSize(size))
        saveSoon()
    }

    func resetControlPosition(_ id: String) {
        objectWillChange.send()
        controlFrames.removeValue(forKey: id)
        saveSoon()
    }

    func resetControlPositions(_ ids: [String]) {
        var changed = false
        for id in ids where controlFrames.removeValue(forKey: id) != nil { changed = true }
        if changed { saveSoon() }
    }

    // MARK: - Knob size mutations

    func setKnobSize(_ size: CGFloat, for id: String) {
        objectWillChange.send()
        knobSizes[id] = max(24, size)
        saveSoon()
    }

    func resetKnobSize(for id: String) {
        objectWillChange.send()
        knobSizes.removeValue(forKey: id)
        saveSoon()
    }

    // MARK: - Frame reporting (live, not persisted)

    func reportFrame(_ id: String, _ frame: CGRect) {
        let previous = baseFrames[id]
        baseFrames[id] = frame
        if previous != frame { objectWillChange.send() }
    }

    func reportSectionFrame(_ id: String, _ frame: CGRect, controlIDs: [String]) {
        let previous = liveSectionFrames[id]
        liveSectionFrames[id] = frame
        if previous != frame { objectWillChange.send() }
    }

    func registerControl(_ id: String, sectionID: String, frame: CGRect) {
        if controlSectionIDs[id] != sectionID { controlSectionIDs[id] = sectionID }
        guard frame != .zero else { return }
        if controlFrames[id] == nil {
            objectWillChange.send()
            controlFrames[id] = frame
            saveSoon()
            return
        }
        if let stored = controlFrames[id], stored.size != frame.size {
            objectWillChange.send()
            controlFrames[id] = CGRect(origin: stored.origin, size: frame.size)
            saveSoon()
        }
    }

    func frame(for id: String, in sectionID: String, fallback localFrame: CGRect) -> CGRect {
        controlFrames[id] ?? localFrame
    }

    func displayFrame(for id: String, in sectionID: String, fallback localFrame: CGRect) -> CGRect {
        var f = frame(for: id, in: sectionID, fallback: localFrame)
        if selectedIDs.contains(id) {
            f.origin.x += activeDragDelta.width
            f.origin.y += activeDragDelta.height
        }
        return f
    }

    func seedControlFramesIfNeeded() {
        // Control frames are seeded directly by WaveControlSlot on first display.
    }

    // MARK: - Selection

    func selectSection(_ sectionID: String, exclusive: Bool = true) {
        select(panelSelectionID(for: sectionID), exclusive: exclusive)
    }

    func toggleSectionSelection(_ sectionID: String) {
        toggleSelection(panelSelectionID(for: sectionID))
    }

    func select(_ id: String, exclusive: Bool = true) {
        if exclusive {
            selectedIDs = [id]
            keyObjectID = id
        } else {
            selectedIDs.insert(id)
            if keyObjectID == nil { keyObjectID = id }
        }
    }

    func clearSelection() {
        selectedIDs.removeAll()
        keyObjectID = nil
        activeDragDelta = .zero
    }

    func toggleHighlight(_ id: String) {
        highlightedID = highlightedID == id ? nil : id
    }

    func clearHighlight() {
        highlightedID = nil
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

    func selectNext() {
        let panelIDs = panelFrames.keys.map(panelSelectionID(for:))
        let candidates = Array(Set(baseFrames.keys).union(panelIDs))
            .filter { displayedFrame(for: $0) != .zero }
        let sorted = candidates.sorted { a, b in
            let af = displayedFrame(for: a), bf = displayedFrame(for: b)
            if af.minY != bf.minY { return af.minY < bf.minY }
            if af.minX != bf.minX { return af.minX < bf.minX }
            return a < b
        }
        guard !sorted.isEmpty else { return }
        let current = keyObjectID.flatMap { sorted.contains($0) ? $0 : nil }
            ?? sorted.first(where: { selectedIDs.contains($0) })
        if let c = current, let i = sorted.firstIndex(of: c) {
            select(sorted[(i + 1) % sorted.count])
        } else if let first = sorted.first {
            select(first)
        }
    }

    func selectAtPoint(_ point: CGPoint, shift: Bool = false) {
        let hits = hitFrames(containing: point)
        guard let best = hits.first else { if !shift { clearSelection() }; return }
        shift ? toggleSelection(best.id) : select(best.id)
    }

    // MARK: - Drag

    func updateDrag(delta: CGSize) {
        objectWillChange.send()
        activeDragDelta = delta
    }

    func commitDrag() {
        guard activeDragDelta != .zero else { return }
        objectWillChange.send()
        for id in selectedIDs {
            if let sid = sectionID(for: id) {
                let r = panelFrames[sid] ?? .zero
                panelFrames[sid] = CGRect(
                    origin: CGPoint(x: r.origin.x + activeDragDelta.width, y: r.origin.y + activeDragDelta.height),
                    size: r.size
                )
            } else {
                let r = controlFrames[id] ?? .zero
                controlFrames[id] = CGRect(
                    origin: CGPoint(x: r.origin.x + activeDragDelta.width, y: r.origin.y + activeDragDelta.height),
                    size: r.size
                )
            }
        }
        activeDragDelta = .zero
        saveSoon()
    }

    func nudgeSelection(x: CGFloat, y: CGFloat) {
        guard !selectedIDs.isEmpty else { return }
        objectWillChange.send()
        for id in selectedIDs {
            if let sid = sectionID(for: id) {
                let r = panelFrames[sid] ?? .zero
                panelFrames[sid] = CGRect(
                    origin: CGPoint(x: r.origin.x + x, y: r.origin.y + y), size: r.size)
            } else {
                let r = controlFrames[id] ?? .zero
                controlFrames[id] = CGRect(
                    origin: CGPoint(x: r.origin.x + x, y: r.origin.y + y), size: r.size)
            }
        }
        saveSoon()
    }

    // MARK: - Alignment

    enum AlignmentEdge { case left, center, right, top, middle, bottom }

    func alignSelected(to edge: AlignmentEdge) {
        let ids = Array(selectedIDs).filter { displayedFrame(for: $0) != .zero }
        guard ids.count > 1 else { return }
        let snapshots = Dictionary(uniqueKeysWithValues: ids.map { ($0, displayedFrame(for: $0)) })
        let anchor = keyObjectID.flatMap { snapshots[$0] != nil ? $0 : nil } ?? ids.first!
        guard let anchorFrame = snapshots[anchor] else { return }
        for id in ids {
            guard let frame = snapshots[id] else { continue }
            let newOrigin = targetOrigin(currentFrame: frame, alignedTo: edge, anchorFrame: anchorFrame)
            if let sid = sectionID(for: id) {
                objectWillChange.send()
                panelFrames[sid] = CGRect(origin: newOrigin, size: frame.size)
            } else {
                setGlobalOrigin(for: id, globalOrigin: newOrigin, size: frame.size)
            }
        }
        saveSoon()
    }

    func distributeSelected(horizontal: Bool) {
        let ids = Array(selectedIDs)
            .filter { !isPanelSelectionID($0) }
            .filter { displayedFrame(for: $0) != .zero }
        guard ids.count > 2 else { return }
        let snapshots = Dictionary(uniqueKeysWithValues: ids.map { ($0, displayedFrame(for: $0)) })
        let axis = horizontal
            ? ids.sorted { (snapshots[$0]?.midX ?? 0) < (snapshots[$1]?.midX ?? 0) }
            : ids.sorted { (snapshots[$0]?.midY ?? 0) < (snapshots[$1]?.midY ?? 0) }
        guard let first = axis.first, let last = axis.last,
              let startVal = snapshots[first].map({ horizontal ? $0.midX : $0.midY }),
              let endVal   = snapshots[last].map({ horizontal ? $0.midX : $0.midY }),
              endVal > startVal else { return }
        let step = (endVal - startVal) / CGFloat(axis.count - 1)
        for (i, id) in axis.enumerated() {
            guard let frame = snapshots[id] else { continue }
            let target = startVal + CGFloat(i) * step
            let delta  = target - (horizontal ? frame.midX : frame.midY)
            setGlobalOrigin(
                for: id,
                globalOrigin: horizontal
                    ? CGPoint(x: frame.origin.x + delta, y: frame.origin.y)
                    : CGPoint(x: frame.origin.x, y: frame.origin.y + delta),
                size: frame.size
            )
        }
        saveSoon()
    }

    func matchSelectedSize(width: Bool, height: Bool) {
        guard width || height else { return }
        let ids = Array(selectedIDs).filter { displayedFrame(for: $0) != .zero }
        guard ids.count > 1 else { return }
        let snapshots = Dictionary(uniqueKeysWithValues: ids.map { ($0, displayedFrame(for: $0)) })
        let anchor = keyObjectID.flatMap { snapshots[$0] != nil ? $0 : nil } ?? ids.first!
        guard let anchorFrame = snapshots[anchor] else { return }
        for id in ids where id != anchor {
            guard let frame = snapshots[id] else { continue }
            setSelectionSize(
                CGSize(
                    width:  width  ? anchorFrame.width  : frame.width,
                    height: height ? anchorFrame.height : frame.height
                ),
                for: id
            )
        }
        saveSoon()
    }

    func applyPanelGap(horizontal: Bool) {
        let ids = Array(selectedIDs).filter(isPanelSelectionID).filter { displayedFrame(for: $0) != .zero }
        guard ids.count == 2 else { return }
        let snapshots = Dictionary(uniqueKeysWithValues: ids.map { ($0, displayedFrame(for: $0)) })
        let anchor = keyObjectID.flatMap { snapshots[$0] != nil ? $0 : nil } ?? ids.first!
        guard let movingID     = ids.first(where: { $0 != anchor }),
              let anchorFrame  = snapshots[anchor],
              let movingFrame  = snapshots[movingID],
              let movingSID    = sectionID(for: movingID) else { return }
        let newOrigin: CGPoint
        if horizontal {
            newOrigin = movingFrame.midX >= anchorFrame.midX
                ? CGPoint(x: anchorFrame.maxX + panelGap, y: movingFrame.origin.y)
                : CGPoint(x: anchorFrame.minX - panelGap - movingFrame.width, y: movingFrame.origin.y)
        } else {
            newOrigin = movingFrame.midY >= anchorFrame.midY
                ? CGPoint(x: movingFrame.origin.x, y: anchorFrame.maxY + panelGap)
                : CGPoint(x: movingFrame.origin.x, y: anchorFrame.minY - panelGap - movingFrame.height)
        }
        objectWillChange.send()
        panelFrames[movingSID] = CGRect(origin: newOrigin, size: movingFrame.size)
        saveSoon()
    }

    // MARK: - Export (generates Swift code for baking tuned values into source)

    func exportToClipboard() {
        var lines: [String] = []

        lines.append("// MARK: - Panel Frames  →  paste into defaultPanelFrame(for:)")
        for (id, frame) in panelFrames.sorted(by: { $0.key < $1.key }) {
            lines.append("case \"\(id)\": return CGRect(x: \(Int(frame.minX)), y: \(Int(frame.minY)), width: \(Int(frame.width)), height: \(Int(frame.height)))")
        }

        lines.append("")
        lines.append("// MARK: - Control Frames  →  paste as naturalFrame in WaveControlSlot calls")
        for (id, frame) in controlFrames.sorted(by: { $0.key < $1.key }) {
            lines.append("// \"\(id)\": CGRect(x: \(Int(frame.minX)), y: \(Int(frame.minY)), width: \(Int(frame.width)), height: \(Int(frame.height)))")
        }

        if !knobSizes.isEmpty {
            lines.append("")
            lines.append("// MARK: - Knob Sizes")
            for (id, size) in knobSizes.sorted(by: { $0.key < $1.key }) {
                lines.append("// \"\(id)\": \(Int(size))")
            }
        }

        let text = lines.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    // MARK: - Private helpers

    private func clamped(_ rect: CGRect) -> CGRect {
        CGRect(origin: rect.origin, size: clampedSize(rect.size))
    }

    private func clampedSize(_ size: CGSize) -> CGSize {
        CGSize(width: max(1, size.width), height: max(1, size.height))
    }

    private func displayedFrame(for id: String) -> CGRect {
        if let sid = sectionID(for: id) { return panelFrames[sid] ?? .zero }
        let local = controlFrames[id] ?? baseFrames[id] ?? .zero
        guard let sid = controlSectionIDs[id], let sectionFrame = panelFrames[sid] else { return local }
        return CGRect(
            x: sectionFrame.minX + local.minX, y: sectionFrame.minY + local.minY,
            width: local.width, height: local.height
        )
    }

    private func setGlobalOrigin(for id: String, globalOrigin: CGPoint, size: CGSize) {
        objectWillChange.send()
        if let sid = controlSectionIDs[id], let sectionFrame = panelFrames[sid] {
            controlFrames[id] = CGRect(
                origin: CGPoint(x: globalOrigin.x - sectionFrame.minX, y: globalOrigin.y - sectionFrame.minY),
                size: size
            )
        } else {
            controlFrames[id] = CGRect(origin: globalOrigin, size: size)
        }
    }

    private func setSelectionSize(_ size: CGSize, for id: String) {
        let clamped = clampedSize(size)
        if let sid = sectionID(for: id) {
            objectWillChange.send()
            panelFrames[sid] = CGRect(origin: (panelFrames[sid] ?? .zero).origin, size: clamped)
        } else {
            let origin = (controlFrames[id] ?? baseFrames[id] ?? .zero).origin
            objectWillChange.send()
            controlFrames[id] = CGRect(origin: origin, size: clamped)
        }
    }

    private func targetOrigin(
        currentFrame: CGRect,
        alignedTo edge: AlignmentEdge,
        anchorFrame: CGRect
    ) -> CGPoint {
        let o = currentFrame.origin
        switch edge {
        case .left:   return CGPoint(x: o.x + (anchorFrame.minX - currentFrame.minX), y: o.y)
        case .center: return CGPoint(x: o.x + (anchorFrame.midX - currentFrame.midX), y: o.y)
        case .right:  return CGPoint(x: o.x + (anchorFrame.maxX - currentFrame.maxX), y: o.y)
        case .top:    return CGPoint(x: o.x, y: o.y + (anchorFrame.minY - currentFrame.minY))
        case .middle: return CGPoint(x: o.x, y: o.y + (anchorFrame.midY - currentFrame.midY))
        case .bottom: return CGPoint(x: o.x, y: o.y + (anchorFrame.maxY - currentFrame.maxY))
        }
    }

    private typealias FrameHit = (id: String, frame: CGRect)

    private func hitFrames(containing point: CGPoint) -> [FrameHit] {
        let controlHits: [FrameHit] = baseFrames.compactMap { id, _ in
            let f = displayedFrame(for: id)
            guard f.insetBy(dx: -6, dy: -6).contains(point) else { return nil }
            return (id: id, frame: f)
        }
        let panelHits: [FrameHit] = panelFrames.compactMap { sid, frame in
            guard frame.insetBy(dx: -6, dy: -6).contains(point) else { return nil }
            return (id: panelSelectionID(for: sid), frame: frame)
        }
        return (controlHits + panelHits).sorted { lhs, rhs in
            let ld = distanceSquared(from: point, to: CGPoint(x: lhs.frame.midX, y: lhs.frame.midY))
            let rd = distanceSquared(from: point, to: CGPoint(x: rhs.frame.midX, y: rhs.frame.midY))
            return ld != rd ? ld < rd : (lhs.frame.width * lhs.frame.height) < (rhs.frame.width * rhs.frame.height)
        }
    }

    private func distanceSquared(from a: CGPoint, to b: CGPoint) -> CGFloat {
        (a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)
    }

    private func setupEventMonitor() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, !self.selectedIDs.isEmpty else { return event }
            let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
            switch event.keyCode {
            case 123: self.nudgeSelection(x: -step, y: 0); return nil
            case 124: self.nudgeSelection(x:  step, y: 0); return nil
            case 125: self.nudgeSelection(x: 0, y:  step); return nil
            case 126: self.nudgeSelection(x: 0, y: -step); return nil
            default:  return event
            }
        }
    }
}
