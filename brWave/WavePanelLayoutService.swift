import SwiftUI
import Combine
import AppKit

struct WavePanelLayoutFile: Codable {
    struct Size: Codable {
        var width: CGFloat
        var height: CGFloat

        var cgSize: CGSize { CGSize(width: width, height: height) }

        init(_ size: CGSize) {
            self.width = size.width
            self.height = size.height
        }
    }

    struct Rect: Codable {
        var x: CGFloat
        var y: CGFloat
        var width: CGFloat
        var height: CGFloat

        var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }

        init(_ rect: CGRect) {
            self.x = rect.origin.x
            self.y = rect.origin.y
            self.width = rect.size.width
            self.height = rect.size.height
        }
    }

    var sectionSizes: [String: Size] = [:]
    var sectionFrames: [String: Rect] = [:]
    var knobSizes: [String: CGFloat] = [:]
    var controlFrames: [String: Rect] = [:]

    private enum CodingKeys: String, CodingKey {
        case sectionSizes
        case sectionFrames
        case knobSizes
        case controlFrames
    }

    init() {}

    init(
        sectionSizes: [String: Size] = [:],
        sectionFrames: [String: Rect] = [:],
        knobSizes: [String: CGFloat] = [:],
        controlFrames: [String: Rect] = [:]
    ) {
        self.sectionSizes = sectionSizes
        self.sectionFrames = sectionFrames
        self.knobSizes = knobSizes
        self.controlFrames = controlFrames
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sectionSizes = try container.decodeIfPresent([String: Size].self, forKey: .sectionSizes) ?? [:]
        sectionFrames = try container.decodeIfPresent([String: Rect].self, forKey: .sectionFrames) ?? [:]
        knobSizes = try container.decodeIfPresent([String: CGFloat].self, forKey: .knobSizes) ?? [:]
        controlFrames = try container.decodeIfPresent([String: Rect].self, forKey: .controlFrames) ?? [:]
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sectionSizes, forKey: .sectionSizes)
        try container.encode(sectionFrames, forKey: .sectionFrames)
        try container.encode(knobSizes, forKey: .knobSizes)
        try container.encode(controlFrames, forKey: .controlFrames)
    }
}

@MainActor
final class WavePanelLayoutService: ObservableObject {
    private typealias FrameHit = (id: String, frame: CGRect)
    private static let panelSelectionPrefix = "panel:"

    static let shared = WavePanelLayoutService()
    private static let storageKey = "brWaveCanonicalLayout_v2"
    private static let legacyStorageKeys = [
        "brWaveCanonicalLayout_v9",
        "brWaveCanonicalLayout_v8",
        "brWaveCanonicalLayout_v7",
        "brWaveCanonicalLayout_v6",
        "brWaveCanonicalLayout_v5",
        "brWaveCanonicalLayout_v4"
    ]

    @Published private(set) var panelFrames: [String: CGRect] = [:]
    @Published var knobSizes: [String: CGFloat] = [:]
    @Published var controlFrames: [String: CGRect] = [:]
    @Published var selectedIDs: Set<String> = []
    @Published var keyObjectID: String? = nil
    @Published var highlightedID: String? = nil
    @Published var activeDragDelta: CGSize = .zero

    private(set) var baseFrames: [String: CGRect] = [:]
    private(set) var liveSectionFrames: [String: CGRect] = [:]
    private(set) var controlSectionIDs: [String: String] = [:]
    private var legacySectionSizes: [String: CGSize] = [:]
    private var saveWorkItem: DispatchWorkItem?
    private var eventMonitor: Any?

    #if DEBUG
    private static let sourceFileURL: URL = URL(fileURLWithPath: #file)
        .deletingLastPathComponent()
        .appendingPathComponent("WavePanelLayout.json")
    #endif

    private static let appSupportFileURL: URL = {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let bundleID = Bundle.main.bundleIdentifier ?? "brWave"
        return base
            .appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("WavePanelLayout_v2.json")
    }()

    private init() {
        load()
        setupEventMonitor()
    }

    deinit {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
    }

    func size(for id: String) -> CGSize? { panelFrames[id]?.size ?? legacySectionSizes[id] }
    func panelFrame(for id: String) -> CGRect? { panelFrames[id] }
    func knobSize(for id: String) -> CGFloat? { knobSizes[id] }
    func frame(for id: String) -> CGRect? { controlFrames[id] }
    func origin(for id: String) -> CGPoint? { controlFrames[id]?.origin }
    func isPanelSelectionID(_ id: String) -> Bool {
        id.hasPrefix(Self.panelSelectionPrefix)
    }

    func panelSelectionID(for sectionID: String) -> String {
        Self.panelSelectionPrefix + sectionID
    }

    func sectionID(for selectionID: String) -> String? {
        guard isPanelSelectionID(selectionID) else { return nil }
        return String(selectionID.dropFirst(Self.panelSelectionPrefix.count))
    }

    func selectSection(_ sectionID: String, exclusive: Bool = true) {
        select(panelSelectionID(for: sectionID), exclusive: exclusive)
    }

    func toggleSectionSelection(_ sectionID: String) {
        toggleSelection(panelSelectionID(for: sectionID))
    }
    func setOrigin(_ origin: CGPoint, for id: String) {
        let current = controlFrames[id] ?? baseFrames[id] ?? .zero
        objectWillChange.send()
        controlFrames[id] = CGRect(origin: origin, size: current.size)
        saveSoon()
    }

    func setSize(_ size: CGSize, for id: String) {
        let current = controlFrames[id] ?? baseFrames[id] ?? .zero
        let clampedSize = CGSize(width: max(1, size.width), height: max(1, size.height))
        objectWillChange.send()
        controlFrames[id] = CGRect(origin: current.origin, size: clampedSize)
        saveSoon()
    }

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

    func seedPanelFrameIfNeeded(_ id: String, frame: CGRect) {
        guard frame != .zero, panelFrames[id] == nil else { return }
        objectWillChange.send()
        panelFrames[id] = frame
        saveSoon()
    }

    func setPanelFrame(_ id: String, frame: CGRect) {
        objectWillChange.send()
        panelFrames[id] = CGRect(
            origin: frame.origin,
            size: CGSize(width: max(1, frame.width), height: max(1, frame.height))
        )
        saveSoon()
    }

    func setPanelFrameLive(_ id: String, frame: CGRect) {
        objectWillChange.send()
        panelFrames[id] = CGRect(
            origin: frame.origin,
            size: CGSize(width: max(1, frame.width), height: max(1, frame.height))
        )
    }

    func setPanelOrigin(_ id: String, origin: CGPoint) {
        let current = panelFrames[id] ?? .zero
        objectWillChange.send()
        panelFrames[id] = CGRect(origin: origin, size: current.size)
        saveSoon()
    }

    func setPanelOriginLive(_ id: String, origin: CGPoint) {
        let current = panelFrames[id] ?? .zero
        objectWillChange.send()
        panelFrames[id] = CGRect(origin: origin, size: current.size)
    }

    func setPanelSize(_ id: String, size: CGSize) {
        let current = panelFrames[id] ?? .zero
        // Keep the top-left fixed so resize only moves the lower-right corner.
        let clamped = CGSize(width: max(1, size.width), height: max(1, size.height))
        objectWillChange.send()
        panelFrames[id] = CGRect(origin: current.origin, size: clamped)
        saveSoon()
    }

    func setPanelSizeLive(_ id: String, size: CGSize) {
        let current = panelFrames[id] ?? .zero
        // Keep the top-left fixed so resize only moves the lower-right corner.
        let clamped = CGSize(width: max(1, size.width), height: max(1, size.height))
        objectWillChange.send()
        panelFrames[id] = CGRect(origin: current.origin, size: clamped)
    }

    func resetSectionSize(_ id: String) {
        guard let current = panelFrames[id] else { return }
        objectWillChange.send()
        panelFrames[id] = CGRect(origin: current.origin, size: .zero)
        saveSoon()
    }

    func reportFrame(_ id: String, _ frame: CGRect) {
        let previous = baseFrames[id]
        baseFrames[id] = frame
        guard previous != frame else { return }
        objectWillChange.send()
    }

    func registerControl(_ id: String, sectionID: String, frame: CGRect) {
        if controlSectionIDs[id] != sectionID {
            controlSectionIDs[id] = sectionID
        }

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

    func reportSectionFrame(_ id: String, _ frame: CGRect, controlIDs: [String]) {
        let previous = liveSectionFrames[id]
        liveSectionFrames[id] = frame
        guard previous != frame else { return }
        objectWillChange.send()
    }

    func frame(for id: String, in sectionID: String, fallback localFrame: CGRect) -> CGRect {
        guard let storedFrame = controlFrames[id] else { return localFrame }
        return storedFrame
    }

    func displayFrame(for id: String, in sectionID: String, fallback localFrame: CGRect) -> CGRect {
        var frame = frame(for: id, in: sectionID, fallback: localFrame)
        if selectedIDs.contains(id) {
            frame.origin.x += activeDragDelta.width
            frame.origin.y += activeDragDelta.height
        }
        return frame
    }

    func seedControlFramesIfNeeded() {
        // Section-local control frames are now seeded directly by WaveControlSlot.
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
        let candidateIDs = Array(Set(baseFrames.keys).union(panelIDs))
            .filter { displayedFrame(for: $0) != .zero }

        let sorted = candidateIDs.sorted { lhs, rhs in
            let lhsFrame = displayedFrame(for: lhs)
            let rhsFrame = displayedFrame(for: rhs)
            if lhsFrame.minY != rhsFrame.minY {
                return lhsFrame.minY < rhsFrame.minY
            }
            if lhsFrame.minX != rhsFrame.minX {
                return lhsFrame.minX < rhsFrame.minX
            }
            return lhs < rhs
        }
        guard !sorted.isEmpty else { return }
        let currentID = keyObjectID.flatMap { sorted.contains($0) ? $0 : nil }
            ?? sorted.first(where: { selectedIDs.contains($0) })
        guard let current = currentID,
              let index = sorted.firstIndex(of: current) else {
            if let first = sorted.first {
                select(first)
            }
            return
        }
        select(sorted[(index + 1) % sorted.count])
    }

    func selectAtPoint(_ point: CGPoint, shift: Bool = false) {
        let hits = hitFrames(containing: point)
        guard let best = hits.first else {
            if !shift { clearSelection() }
            return
        }
        if shift {
            toggleSelection(best.id)
        } else {
            select(best.id)
        }
    }

    func updateDrag(delta: CGSize) {
        objectWillChange.send()
        activeDragDelta = delta
    }

    func commitDrag() {
        guard activeDragDelta != .zero else { return }
        objectWillChange.send()
        for id in selectedIDs {
            if let sectionID = sectionID(for: id) {
                let current = panelFrames[sectionID] ?? .zero
                panelFrames[sectionID] = CGRect(
                    origin: CGPoint(
                        x: current.origin.x + activeDragDelta.width,
                        y: current.origin.y + activeDragDelta.height
                    ),
                    size: current.size
                )
                continue
            }
            let current = controlFrames[id]?.origin ?? .zero
            let size = controlFrames[id]?.size ?? .zero
            controlFrames[id] = CGRect(
                origin: CGPoint(
                    x: current.x + activeDragDelta.width,
                    y: current.y + activeDragDelta.height
                ),
                size: size
            )
        }
        activeDragDelta = .zero
        saveSoon()
    }

    func nudgeSelection(x: CGFloat, y: CGFloat) {
        guard !selectedIDs.isEmpty else { return }
        objectWillChange.send()
        for id in selectedIDs {
            if let sectionID = sectionID(for: id) {
                let frame = panelFrames[sectionID] ?? .zero
                panelFrames[sectionID] = CGRect(
                    origin: CGPoint(x: frame.origin.x + x, y: frame.origin.y + y),
                    size: frame.size
                )
                continue
            }
            let frame = controlFrames[id] ?? .zero
            controlFrames[id] = CGRect(
                origin: CGPoint(x: frame.origin.x + x, y: frame.origin.y + y),
                size: frame.size
            )
        }
        saveSoon()
    }

    func resetControlPosition(_ id: String) {
        objectWillChange.send()
        controlFrames.removeValue(forKey: id)
        saveSoon()
    }

    func resetControlPositions(_ ids: [String]) {
        var changed = false
        objectWillChange.send()
        for id in ids where controlFrames.removeValue(forKey: id) != nil {
            changed = true
        }
        if changed { saveSoon() }
    }

    enum AlignmentEdge { case left, center, right, top, middle, bottom }
    private let panelGap: CGFloat = 20

    func alignSelected(to edge: AlignmentEdge) {
        let ids = Array(selectedIDs).filter { displayedFrame(for: $0) != .zero }
        guard ids.count > 1 else { return }
        let snapshotFrames = Dictionary(uniqueKeysWithValues: ids.map { ($0, displayedFrame(for: $0)) })
        let anchor = keyObjectID.flatMap { snapshotFrames[$0] != nil ? $0 : nil } ?? ids.first!
        guard let anchorFrame = snapshotFrames[anchor] else { return }

        for id in ids {
            guard let frame = snapshotFrames[id] else { continue }
            if let sectionID = sectionID(for: id) {
                alignPanel(sectionID: sectionID, currentFrame: frame, to: edge, anchorFrame: anchorFrame)
                continue
            }
            setGlobalOrigin(
                for: id,
                globalOrigin: targetOrigin(currentFrame: frame, alignedTo: edge, anchorFrame: anchorFrame),
                size: frame.size
            )
        }
        saveSoon()
    }

    func distributeSelected(horizontal: Bool) {
        let ids = Array(selectedIDs)
            .filter { !isPanelSelectionID($0) }
            .filter { displayedFrame(for: $0) != .zero }
        guard ids.count > 2 else { return }
        let snapshotFrames = Dictionary(uniqueKeysWithValues: ids.map { ($0, displayedFrame(for: $0)) })

        if horizontal {
            let sorted = ids.sorted {
                guard let lhs = snapshotFrames[$0], let rhs = snapshotFrames[$1] else { return $0 < $1 }
                return lhs.midX < rhs.midX
            }
            guard let first = sorted.first, let last = sorted.last else { return }
            guard let firstFrame = snapshotFrames[first], let lastFrame = snapshotFrames[last] else { return }
            let start = firstFrame.midX
            let end = lastFrame.midX
            guard end > start else { return }
            let step = (end - start) / CGFloat(sorted.count - 1)
            for (index, id) in sorted.enumerated() {
                guard let frame = snapshotFrames[id] else { continue }
                let targetMid = start + CGFloat(index) * step
                let dx = targetMid - frame.midX
                setGlobalOrigin(
                    for: id,
                    globalOrigin: CGPoint(x: frame.origin.x + dx, y: frame.origin.y),
                    size: frame.size
                )
            }
        } else {
            let sorted = ids.sorted {
                guard let lhs = snapshotFrames[$0], let rhs = snapshotFrames[$1] else { return $0 < $1 }
                return lhs.midY < rhs.midY
            }
            guard let first = sorted.first, let last = sorted.last else { return }
            guard let firstFrame = snapshotFrames[first], let lastFrame = snapshotFrames[last] else { return }
            let start = firstFrame.midY
            let end = lastFrame.midY
            guard end > start else { return }
            let step = (end - start) / CGFloat(sorted.count - 1)
            for (index, id) in sorted.enumerated() {
                guard let frame = snapshotFrames[id] else { continue }
                let targetMid = start + CGFloat(index) * step
                let dy = targetMid - frame.midY
                setGlobalOrigin(
                    for: id,
                    globalOrigin: CGPoint(x: frame.origin.x, y: frame.origin.y + dy),
                    size: frame.size
                )
            }
        }
        saveSoon()
    }

    func matchSelectedSize(width: Bool, height: Bool) {
        guard width || height else { return }
        let ids = Array(selectedIDs).filter { displayedFrame(for: $0) != .zero }
        guard ids.count > 1 else { return }
        let snapshotFrames = Dictionary(uniqueKeysWithValues: ids.map { ($0, displayedFrame(for: $0)) })
        let anchor = keyObjectID.flatMap { snapshotFrames[$0] != nil ? $0 : nil } ?? ids.first!
        guard let anchorFrame = snapshotFrames[anchor] else { return }

        for id in ids where id != anchor {
            guard let frame = snapshotFrames[id] else { continue }
            let newSize = CGSize(
                width: width ? anchorFrame.width : frame.width,
                height: height ? anchorFrame.height : frame.height
            )
            setSelectionSize(newSize, for: id)
        }
        saveSoon()
    }

    func applyPanelGap(horizontal: Bool) {
        let ids = Array(selectedIDs)
            .filter(isPanelSelectionID)
            .filter { displayedFrame(for: $0) != .zero }
        guard ids.count == 2 else { return }

        let snapshotFrames = Dictionary(uniqueKeysWithValues: ids.map { ($0, displayedFrame(for: $0)) })
        let anchor = keyObjectID.flatMap { snapshotFrames[$0] != nil ? $0 : nil } ?? ids.first!
        guard let movingID = ids.first(where: { $0 != anchor }),
              let anchorFrame = snapshotFrames[anchor],
              let movingFrame = snapshotFrames[movingID],
              let movingSectionID = sectionID(for: movingID) else { return }

        let newOrigin: CGPoint
        if horizontal {
            if movingFrame.midX >= anchorFrame.midX {
                newOrigin = CGPoint(x: anchorFrame.maxX + panelGap, y: movingFrame.origin.y)
            } else {
                newOrigin = CGPoint(x: anchorFrame.minX - panelGap - movingFrame.width, y: movingFrame.origin.y)
            }
        } else {
            if movingFrame.midY >= anchorFrame.midY {
                newOrigin = CGPoint(x: movingFrame.origin.x, y: anchorFrame.maxY + panelGap)
            } else {
                newOrigin = CGPoint(x: movingFrame.origin.x, y: anchorFrame.minY - panelGap - movingFrame.height)
            }
        }

        objectWillChange.send()
        panelFrames[movingSectionID] = CGRect(origin: newOrigin, size: movingFrame.size)
        saveSoon()
    }

    func flushSaves() {
        saveSoon()
    }

    func exportToClipboard() {
        let file = WavePanelLayoutFile(
            sectionFrames: Dictionary(uniqueKeysWithValues: panelFrames.map { ($0.key, WavePanelLayoutFile.Rect($0.value)) }),
            knobSizes: knobSizes,
            controlFrames: Dictionary(uniqueKeysWithValues: controlFrames.map { ($0.key, WavePanelLayoutFile.Rect($0.value)) })
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(file),
              let text = String(data: data, encoding: .utf8) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        print(text)
    }

    private func targetOrigin(
        currentFrame: CGRect,
        alignedTo edge: AlignmentEdge,
        anchorFrame: CGRect
    ) -> CGPoint {
        let current = currentFrame.origin
        switch edge {
        case .left:
            return CGPoint(x: current.x + (anchorFrame.minX - currentFrame.minX), y: current.y)
        case .center:
            return CGPoint(x: current.x + (anchorFrame.midX - currentFrame.midX), y: current.y)
        case .right:
            return CGPoint(x: current.x + (anchorFrame.maxX - currentFrame.maxX), y: current.y)
        case .top:
            return CGPoint(x: current.x, y: current.y + (anchorFrame.minY - currentFrame.minY))
        case .middle:
            return CGPoint(x: current.x, y: current.y + (anchorFrame.midY - currentFrame.midY))
        case .bottom:
            return CGPoint(x: current.x, y: current.y + (anchorFrame.maxY - currentFrame.maxY))
        }
    }

    private func setupEventMonitor() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            guard !self.selectedIDs.isEmpty else { return event }

            let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1

            switch event.keyCode {
            case 123:
                self.nudgeSelection(x: -step, y: 0)
                return nil
            case 124:
                self.nudgeSelection(x: step, y: 0)
                return nil
            case 125:
                self.nudgeSelection(x: 0, y: step)
                return nil
            case 126:
                self.nudgeSelection(x: 0, y: -step)
                return nil
            default:
                return event
            }
        }
    }

    private func displayedFrame(for id: String) -> CGRect {
        if let sectionID = sectionID(for: id) {
            return panelFrames[sectionID] ?? .zero
        }
        let localFrame = controlFrames[id] ?? baseFrames[id] ?? .zero
        guard let sectionID = controlSectionIDs[id],
              let sectionFrame = panelFrames[sectionID] else {
            return localFrame
        }
        return CGRect(
            x: sectionFrame.minX + localFrame.minX,
            y: sectionFrame.minY + localFrame.minY,
            width: localFrame.width,
            height: localFrame.height
        )
    }

    private func setGlobalOrigin(for id: String, globalOrigin: CGPoint, size: CGSize) {
        guard let sectionID = controlSectionIDs[id],
              let sectionFrame = panelFrames[sectionID] else {
            objectWillChange.send()
            controlFrames[id] = CGRect(origin: globalOrigin, size: size)
            return
        }
        objectWillChange.send()
        controlFrames[id] = CGRect(
            origin: CGPoint(
                x: globalOrigin.x - sectionFrame.minX,
                y: globalOrigin.y - sectionFrame.minY
            ),
            size: size
        )
    }

    private func setSelectionSize(_ size: CGSize, for id: String) {
        let clampedSize = CGSize(width: max(1, size.width), height: max(1, size.height))
        if let sectionID = sectionID(for: id) {
            objectWillChange.send()
            let current = panelFrames[sectionID] ?? .zero
            panelFrames[sectionID] = CGRect(origin: current.origin, size: clampedSize)
            return
        }

        let current = controlFrames[id] ?? baseFrames[id] ?? .zero
        objectWillChange.send()
        controlFrames[id] = CGRect(origin: current.origin, size: clampedSize)
    }

    private func alignPanel(
        sectionID: String,
        currentFrame: CGRect,
        to edge: AlignmentEdge,
        anchorFrame: CGRect
    ) {
        let newOrigin = targetOrigin(currentFrame: currentFrame, alignedTo: edge, anchorFrame: anchorFrame)
        objectWillChange.send()
        panelFrames[sectionID] = CGRect(origin: newOrigin, size: currentFrame.size)
    }

    private func hitFrames(containing point: CGPoint) -> [FrameHit] {
        let controlHits: [FrameHit] = baseFrames.compactMap { id, _ in
            let displayedFrame = displayedFrame(for: id)
            let hitFrame = displayedFrame.insetBy(dx: -6, dy: -6)
            guard hitFrame.contains(point) else { return nil }
            return (id: id, frame: displayedFrame)
        }
        let panelHits: [FrameHit] = panelFrames.compactMap { sectionID, frame in
            let hitFrame = frame.insetBy(dx: -6, dy: -6)
            guard hitFrame.contains(point) else { return nil }
            return (id: panelSelectionID(for: sectionID), frame: frame)
        }
        let expandedFrames = controlHits + panelHits

        return expandedFrames.sorted { lhs, rhs in
            let lhsDistance = distanceSquared(from: point, to: center(of: lhs.frame))
            let rhsDistance = distanceSquared(from: point, to: center(of: rhs.frame))
            if lhsDistance != rhsDistance {
                return lhsDistance < rhsDistance
            }
            return area(of: lhs.frame) < area(of: rhs.frame)
        }
    }

    private func area(of frame: CGRect) -> CGFloat {
        frame.width * frame.height
    }

    private func distanceSquared(from point: CGPoint, to target: CGPoint) -> CGFloat {
        let dx = point.x - target.x
        let dy = point.y - target.y
        return dx * dx + dy * dy
    }

    private func center(of frame: CGRect) -> CGPoint {
        CGPoint(x: frame.midX, y: frame.midY)
    }

    private func load() {
        let defaults = UserDefaults.standard
        let candidateKeys = [Self.storageKey] + Self.legacyStorageKeys

        if let file = loadFromAppSupportFile() {
            apply(file)
            mirrorToDefaults(file, defaults: defaults)
            return
        }

        for key in candidateKeys {
            if let data = defaults.data(forKey: key),
               let file = try? JSONDecoder().decode(WavePanelLayoutFile.self, from: data) {
                apply(file)
                if key != Self.storageKey {
                    mirrorToDefaults(file, defaults: defaults)
                }
                saveToAppSupportFile(file)
                return
            }
        }

        #if DEBUG
        guard let data = try? Data(contentsOf: Self.sourceFileURL),
              let file = try? JSONDecoder().decode(WavePanelLayoutFile.self, from: data) else {
            panelFrames = [:]
            controlFrames = [:]
            return
        }
        apply(file)
        mirrorToDefaults(file, defaults: defaults)
        saveToAppSupportFile(file)
        #else
        panelFrames = [:]
        controlFrames = [:]
        #endif
    }

    private func saveSoon() {
        saveWorkItem?.cancel()
        saveNow()
    }

    private func saveNow() {
        let file = WavePanelLayoutFile(
            sectionFrames: Dictionary(uniqueKeysWithValues: panelFrames.map { ($0.key, WavePanelLayoutFile.Rect($0.value)) }),
            knobSizes: knobSizes,
            controlFrames: Dictionary(uniqueKeysWithValues: controlFrames.map { ($0.key, WavePanelLayoutFile.Rect($0.value)) })
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(file) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
        for key in Self.legacyStorageKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }
        saveToAppSupportFile(file)

        #if DEBUG
        try? data.write(to: Self.sourceFileURL, options: .atomic)
        #endif
    }

    private func apply(_ file: WavePanelLayoutFile) {
        legacySectionSizes = Dictionary(uniqueKeysWithValues: file.sectionSizes.map { ($0.key, $0.value.cgSize) })
        panelFrames = Dictionary(uniqueKeysWithValues: file.sectionFrames.map { ($0.key, $0.value.cgRect) })
        knobSizes = file.knobSizes
        controlFrames = Dictionary(uniqueKeysWithValues: file.controlFrames.map { ($0.key, $0.value.cgRect) })
    }

    private func mirrorToDefaults(_ file: WavePanelLayoutFile, defaults: UserDefaults) {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(file) else { return }
        defaults.set(data, forKey: Self.storageKey)
        for key in Self.legacyStorageKeys {
            defaults.removeObject(forKey: key)
        }
    }

    private func loadFromAppSupportFile() -> WavePanelLayoutFile? {
        guard let data = try? Data(contentsOf: Self.appSupportFileURL),
              let file = try? JSONDecoder().decode(WavePanelLayoutFile.self, from: data) else {
            return nil
        }
        return file
    }

    private func saveToAppSupportFile(_ file: WavePanelLayoutFile) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(file) else { return }
        let directory = Self.appSupportFileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: Self.appSupportFileURL, options: .atomic)
    }
}
