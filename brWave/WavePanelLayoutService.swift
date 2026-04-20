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

    struct Point: Codable {
        var x: CGFloat
        var y: CGFloat

        var cgPoint: CGPoint { CGPoint(x: x, y: y) }

        init(_ point: CGPoint) {
            self.x = point.x
            self.y = point.y
        }
    }

    var sectionSizes: [String: Size] = [:]
    var controlOrigins: [String: Point] = [:]
}

@MainActor
final class WavePanelLayoutService: ObservableObject {
    static let shared = WavePanelLayoutService()

    @Published var sectionSizes: [String: CGSize] = [:]
    @Published var controlOrigins: [String: CGPoint] = [:]
    @Published var selectedIDs: Set<String> = []
    @Published var keyObjectID: String? = nil
    @Published var activeDragDelta: CGSize = .zero

    private(set) var baseFrames: [String: CGRect] = [:]
    private var saveWorkItem: DispatchWorkItem?

    #if DEBUG
    private static let sourceFileURL: URL = URL(fileURLWithPath: #file)
        .deletingLastPathComponent()
        .appendingPathComponent("WavePanelLayout.json")
    #endif

    private init() {
        load()
    }

    func size(for id: String) -> CGSize? { sectionSizes[id] }
    func origin(for id: String) -> CGPoint? { controlOrigins[id] }

    func seedSectionSizeIfNeeded(_ id: String, size: CGSize) {
        guard size != .zero, sectionSizes[id] == nil else { return }
        sectionSizes[id] = size
        saveSoon()
    }

    func setSectionSize(_ id: String, size: CGSize) {
        sectionSizes[id] = size
        saveSoon()
    }

    func setSectionSizeLive(_ id: String, size: CGSize) {
        sectionSizes[id] = size
    }

    func resetSectionSize(_ id: String) {
        sectionSizes.removeValue(forKey: id)
        saveSoon()
    }

    func reportFrame(_ id: String, _ frame: CGRect) {
        let previous = baseFrames[id]
        baseFrames[id] = frame
        guard previous != frame else { return }
        objectWillChange.send()
    }

    func migrateLegacyOffsetsIfNeeded(_ legacyOffsets: [String: CGSize]) {
        var changed = false
        for (id, frame) in baseFrames {
            guard controlOrigins[id] == nil else { continue }
            let offset = legacyOffsets[id] ?? .zero
            guard offset != .zero else { continue }
            controlOrigins[id] = CGPoint(
                x: frame.minX + offset.width,
                y: frame.minY + offset.height
            )
            changed = true
        }
        if changed { saveSoon() }
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

    func toggleSelection(_ id: String) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
            if keyObjectID == id { keyObjectID = selectedIDs.first }
        } else {
            selectedIDs.insert(id)
            if keyObjectID == nil { keyObjectID = id }
        }
    }

    func selectAtPoint(_ point: CGPoint, shift: Bool = false) {
        let hits = baseFrames
            .filter { _, frame in frame.insetBy(dx: -6, dy: -6).contains(point) }
            .sorted { a, b in (a.value.width * a.value.height) < (b.value.width * b.value.height) }
        guard let best = hits.first else {
            if !shift { clearSelection() }
            return
        }
        if shift { toggleSelection(best.key) } else { select(best.key) }
    }

    func updateDrag(delta: CGSize) {
        activeDragDelta = delta
    }

    func commitDrag() {
        guard activeDragDelta != .zero else { return }
        for id in selectedIDs {
            guard let frame = baseFrames[id] else { continue }
            let current = controlOrigins[id] ?? frame.origin
            controlOrigins[id] = CGPoint(
                x: current.x + activeDragDelta.width,
                y: current.y + activeDragDelta.height
            )
        }
        activeDragDelta = .zero
        saveSoon()
    }

    func resetControlPosition(_ id: String) {
        controlOrigins.removeValue(forKey: id)
        saveSoon()
    }

    func resetControlPositions(_ ids: [String]) {
        var changed = false
        for id in ids where controlOrigins.removeValue(forKey: id) != nil {
            changed = true
        }
        if changed { saveSoon() }
    }

    enum AlignmentEdge { case left, center, right, top, middle, bottom }

    func alignSelected(to edge: AlignmentEdge) {
        guard selectedIDs.count > 1 else { return }
        let anchor = keyObjectID ?? selectedIDs.first!
        guard baseFrames[anchor] != nil else { return }
        for id in selectedIDs {
            guard let frame = baseFrames[id] else { continue }
            controlOrigins[id] = targetOrigin(for: id, currentFrame: frame, alignedTo: edge, anchorID: anchor)
        }
        saveSoon()
    }

    func distributeSelected(horizontal: Bool) {
        guard selectedIDs.count > 2 else { return }
        let ids = Array(selectedIDs).filter { baseFrames[$0] != nil }
        guard ids.count > 2 else { return }

        if horizontal {
            let sorted = ids.sorted { (baseFrames[$0]?.midX ?? 0) < (baseFrames[$1]?.midX ?? 0) }
            guard let first = sorted.first, let last = sorted.last,
                  let firstFrame = baseFrames[first], let lastFrame = baseFrames[last] else { return }
            let start = firstFrame.midX
            let end = lastFrame.midX
            guard end > start else { return }
            let step = (end - start) / CGFloat(sorted.count - 1)
            for (index, id) in sorted.enumerated() {
                guard let frame = baseFrames[id] else { continue }
                let targetMid = start + CGFloat(index) * step
                let dx = targetMid - frame.midX
                let current = controlOrigins[id] ?? frame.origin
                controlOrigins[id] = CGPoint(x: current.x + dx, y: current.y)
            }
        } else {
            let sorted = ids.sorted { (baseFrames[$0]?.midY ?? 0) < (baseFrames[$1]?.midY ?? 0) }
            guard let first = sorted.first, let last = sorted.last,
                  let firstFrame = baseFrames[first], let lastFrame = baseFrames[last] else { return }
            let start = firstFrame.midY
            let end = lastFrame.midY
            guard end > start else { return }
            let step = (end - start) / CGFloat(sorted.count - 1)
            for (index, id) in sorted.enumerated() {
                guard let frame = baseFrames[id] else { continue }
                let targetMid = start + CGFloat(index) * step
                let dy = targetMid - frame.midY
                let current = controlOrigins[id] ?? frame.origin
                controlOrigins[id] = CGPoint(x: current.x, y: current.y + dy)
            }
        }
        saveSoon()
    }

    func flushSaves() {
        saveWorkItem?.cancel()
        saveNow()
    }

    func exportToClipboard() {
        let file = WavePanelLayoutFile(
            sectionSizes: Dictionary(uniqueKeysWithValues: sectionSizes.map { ($0.key, WavePanelLayoutFile.Size($0.value)) }),
            controlOrigins: Dictionary(uniqueKeysWithValues: controlOrigins.map { ($0.key, WavePanelLayoutFile.Point($0.value)) })
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
        for id: String,
        currentFrame: CGRect,
        alignedTo edge: AlignmentEdge,
        anchorID: String
    ) -> CGPoint {
        let current = controlOrigins[id] ?? currentFrame.origin
        guard let anchorFrame = baseFrames[anchorID] else { return current }
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

    private func load() {
        #if DEBUG
        guard let data = try? Data(contentsOf: Self.sourceFileURL),
              let file = try? JSONDecoder().decode(WavePanelLayoutFile.self, from: data) else {
            sectionSizes = [:]
            controlOrigins = [:]
            return
        }
        sectionSizes = Dictionary(uniqueKeysWithValues: file.sectionSizes.map { ($0.key, $0.value.cgSize) })
        controlOrigins = Dictionary(uniqueKeysWithValues: file.controlOrigins.map { ($0.key, $0.value.cgPoint) })
        #else
        sectionSizes = [:]
        controlOrigins = [:]
        #endif
    }

    private func saveSoon() {
        saveWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.saveNow() }
        }
        saveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: workItem)
    }

    private func saveNow() {
        #if DEBUG
        let file = WavePanelLayoutFile(
            sectionSizes: Dictionary(uniqueKeysWithValues: sectionSizes.map { ($0.key, WavePanelLayoutFile.Size($0.value)) }),
            controlOrigins: Dictionary(uniqueKeysWithValues: controlOrigins.map { ($0.key, WavePanelLayoutFile.Point($0.value)) })
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(file) else { return }
        try? data.write(to: Self.sourceFileURL, options: .atomic)
        #endif
    }
}
