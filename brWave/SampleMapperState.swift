//
//  SampleMapperState.swift
//  brWave
//

import AppKit
import AVFoundation
import Combine
import Foundation
import UniformTypeIdentifiers

private final class SamplePlaybackEngine {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let varispeed = AVAudioUnitVarispeed()

    init() {
        engine.attach(player)
        engine.attach(varispeed)
        engine.connect(player, to: varispeed, format: nil)
        engine.connect(varispeed, to: engine.mainMixerNode, format: nil)
        startIfNeeded()
    }

    func play(sample: SampleZone, midiNote: Int) {
        guard let file = try? AVAudioFile(forReading: sample.url) else { return }
        startIfNeeded()

        let semitoneDelta = Double(midiNote - sample.rootNote.midi)
        varispeed.rate = Float(pow(2.0, semitoneDelta / 12.0))

        let totalFrames = sample.totalFrames ?? Int(file.length)
        let startFrame = AVAudioFramePosition(0)
        let frameCount = AVAudioFrameCount(max(0, totalFrames))

        player.stop()
        player.scheduleSegment(file, startingFrame: startFrame, frameCount: frameCount, at: nil)
        player.play()
    }

    func stop() {
        player.stop()
    }

    private func startIfNeeded() {
        guard !engine.isRunning else { return }
        try? engine.start()
    }
}

@MainActor
final class SampleMapperState: ObservableObject {
    struct RootConflictChoice: Identifiable {
        enum Resolution {
            case filename
            case analyzed
        }

        let id = UUID()
        let sampleID: UUID
        let filename: String
        let filenameRoot: SampleNote
        let analyzedRoot: SampleNote
    }

    @Published var samples: [SampleZone] = []
    @Published var selectedSampleID: UUID?
    @Published var lowerReachSemitones: Int = 5
    @Published var upperReachSemitones: Int = 7
    @Published var waveformZoom: Double = 1.0
    @Published var waveformPan: Double = 0.0
    @Published private(set) var waveformCache: [UUID: SampleWaveform] = [:]
    @Published var rootConflictChoice: RootConflictChoice?
    @Published var statusMessage: String?

    var selectedSample: SampleZone? {
        get { samples.first(where: { $0.id == selectedSampleID }) }
        set {
            guard let newValue,
                  let idx = samples.firstIndex(where: { $0.id == newValue.id }) else { return }
            samples[idx] = newValue
        }
    }

    var selectedWaveform: SampleWaveform? {
        guard let selectedSampleID else { return nil }
        return waveformCache[selectedSampleID]
    }

    private let playbackEngine = SamplePlaybackEngine()

    func importFiles() {
        let panel = NSOpenPanel()
        panel.title = "Import Samples"
        panel.message = "Select sample files for automatic keymapping."
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [
            UTType(filenameExtension: "wav") ?? .audio,
            UTType(filenameExtension: "aiff") ?? .audio,
            UTType(filenameExtension: "aif") ?? .audio,
            UTType(filenameExtension: "caf") ?? .audio,
            UTType(filenameExtension: "yaf") ?? .data,
            UTType(filenameExtension: "sdi") ?? .data,
            UTType(filenameExtension: "sdii") ?? .data
        ]

        guard panel.runModal() == .OK else { return }
        importURLs(panel.urls)
    }

    func importDirectory() {
        let panel = NSOpenPanel()
        panel.title = "Import Sample Folder"
        panel.message = "Choose a folder and brWave will scan it for supported sample formats."
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        importURLs(recursiveSampleURLs(in: url))
    }

    func clear() {
        playbackEngine.stop()
        samples.removeAll()
        selectedSampleID = nil
        waveformCache.removeAll()
        statusMessage = nil
    }

    func autoMap() {
        samples = SampleAutoMapper.assignZones(
            samples,
            lowerReach: lowerReachSemitones,
            upperReach: upperReachSemitones
        )
    }

    /// Number of samples currently assigned a TR slot.
    var slotsUsed: Int { samples.filter { $0.trSlot != nil }.count }

    /// True when at or over the 32-slot hardware limit.
    var atSlotLimit: Bool { samples.count >= Self.maxTransientSlots }

    func updateTRSlot(for sampleID: UUID, to slot: Int?) {
        guard let idx = samples.firstIndex(where: { $0.id == sampleID }) else { return }
        samples[idx].trSlot = slot
    }

    func updateRoot(for sampleID: UUID, to note: SampleNote) {
        guard let idx = samples.firstIndex(where: { $0.id == sampleID }) else { return }
        samples[idx].rootNote = note
        if samples[idx].lowNote > note {
            samples[idx].lowNote = note
        }
        if samples[idx].highNote < note {
            samples[idx].highNote = note
        }
    }

    func updateLow(for sampleID: UUID, to note: SampleNote) {
        guard let idx = samples.firstIndex(where: { $0.id == sampleID }) else { return }
        let clamped = min(note, samples[idx].highNote)
        samples[idx].lowNote = clamped
        if samples[idx].rootNote < clamped {
            samples[idx].rootNote = clamped
        }
    }

    func updateHigh(for sampleID: UUID, to note: SampleNote) {
        guard let idx = samples.firstIndex(where: { $0.id == sampleID }) else { return }
        let clamped = max(note, samples[idx].lowNote)
        samples[idx].highNote = clamped
        if samples[idx].rootNote > clamped {
            samples[idx].rootNote = clamped
        }
    }

    func updateLoopStart(for sampleID: UUID, to frame: Int) {
        guard let idx = samples.firstIndex(where: { $0.id == sampleID }) else { return }
        let maxFrame = max(0, samples[idx].loopPoints.endFrame)
        samples[idx].loopPoints.startFrame = min(max(0, frame), maxFrame)
    }

    func updateLoopEnd(for sampleID: UUID, to frame: Int) {
        guard let idx = samples.firstIndex(where: { $0.id == sampleID }) else { return }
        let maxFrame = max(samples[idx].loopPoints.startFrame, samples[idx].totalFrames ?? frame)
        samples[idx].loopPoints.endFrame = min(max(samples[idx].loopPoints.startFrame, frame), maxFrame)
    }

    func selectSample(_ sampleID: UUID) {
        selectedSampleID = sampleID
        loadWaveformIfNeeded(for: sampleID)
    }

    func previewMappedSample(for midiNote: Int) {
        guard let sample = mappedSample(for: midiNote) else { return }
        selectedSampleID = sample.id
        loadWaveformIfNeeded(for: sample.id)
        playbackEngine.play(sample: sample, midiNote: midiNote)
    }

    func stopPreviewPlayback() {
        playbackEngine.stop()
    }

    func exportMappingPackage() {
        guard !samples.isEmpty else {
            statusMessage = "Import some transients before exporting a map folder."
            return
        }

        let panel = NSSavePanel()
        panel.title = "Export Transient Map"
        panel.message = "Create a folder containing the JSON map and the imported transients."
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "TransientMap.brwavemap"
        panel.allowedContentTypes = [UTType(filenameExtension: "brwavemap") ?? .folder]

        guard panel.runModal() == .OK, let packageURL = panel.url else { return }

        do {
            try writeMappingPackage(to: packageURL)
            statusMessage = "Exported map package to \(packageURL.lastPathComponent)."
        } catch {
            statusMessage = "Export failed: \(error.localizedDescription)"
        }
    }

    static let maxTransientSlots = 32
    static let firstTransientSlot = 32   // TR slots 32–63

    private func importURLs(_ urls: [URL]) {
        var built = urls.compactMap(buildSample(from:))
        guard !built.isEmpty else { return }

        // Enforce hardware 32-slot maximum
        if built.count > Self.maxTransientSlots {
            statusMessage = "⚠️ Only 32 transient slots available — \(built.count - Self.maxTransientSlots) file(s) dropped."
            built = Array(built.prefix(Self.maxTransientSlots))
        }

        // Auto-assign TR slots 32–63 in order
        for i in built.indices {
            built[i].trSlot = Self.firstTransientSlot + i
        }

        samples = SampleAutoMapper.assignZones(
            built,
            lowerReach: lowerReachSemitones,
            upperReach: upperReachSemitones
        )

        // Re-apply slot assignments after auto-map (assignZones reorders but preserves IDs)
        let slotMap = Dictionary(uniqueKeysWithValues: built.map { ($0.id, $0.trSlot) })
        for i in samples.indices {
            samples[i].trSlot = slotMap[samples[i].id] ?? nil
        }

        if let firstID = samples.first?.id {
            selectSample(firstID)
        }

        queueRootConflictPromptIfNeeded()
    }

    private func buildSample(from url: URL) -> SampleZone? {
        guard let format = SampleFileFormat.from(url: url) else { return nil }
        let filenameRoot = SamplePitchDetector.detectFilenameRootNote(from: url)
        let analyzedRoot = SamplePitchDetector.detectAnalyzedRootNote(from: url)
        let metadata = readAudioMetadata(from: url, format: format)
        let detectedRoot = metadata.embeddedRootNote ?? filenameRoot ?? analyzedRoot
        let initialRoot = detectedRoot ?? .c3
        let fileAttributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = (fileAttributes?[.size] as? NSNumber)?.int64Value ?? 0

        let totalFrames = metadata.totalFrames

        return SampleZone(
            id: UUID(),
            url: url,
            format: format,
            rootNote: initialRoot,
            lowNote: initialRoot,
            highNote: initialRoot,
            detectedRootNote: detectedRoot,
            filenameRootNote: filenameRoot,
            fileEmbeddedRootNote: metadata.embeddedRootNote,
            analyzedRootNote: analyzedRoot,
            loopPoints: metadata.loopPoints ?? SampleLoopPoints(startFrame: 0, endFrame: totalFrames ?? 0),
            totalFrames: totalFrames,
            sampleRate: metadata.sampleRate,
            channelCount: metadata.channelCount,
            fileSize: fileSize
        )
    }

    func resolveRootConflict(using resolution: RootConflictChoice.Resolution) {
        guard let choice = rootConflictChoice,
              let index = samples.firstIndex(where: { $0.id == choice.sampleID }) else {
            rootConflictChoice = nil
            return
        }

        let chosenRoot: SampleNote
        switch resolution {
        case .filename:
            chosenRoot = choice.filenameRoot
        case .analyzed:
            chosenRoot = choice.analyzedRoot
        }
        samples[index].rootNote = chosenRoot
        samples[index].detectedRootNote = chosenRoot
        samples[index].filenameRootNote = chosenRoot
        samples[index].analyzedRootNote = chosenRoot
        samples = SampleAutoMapper.assignZones(
            samples,
            lowerReach: lowerReachSemitones,
            upperReach: upperReachSemitones
        )
        rootConflictChoice = nil
        queueRootConflictPromptIfNeeded()
    }

    private func recursiveSampleURLs(in directory: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var results: [URL] = []
        for case let url as URL in enumerator {
            guard SampleFileFormat.supportedExtensions.contains(url.pathExtension.lowercased()) else { continue }
            results.append(url)
        }

        return results.sorted {
            $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending
        }
    }

    private func readAudioMetadata(from url: URL, format: SampleFileFormat) -> SampleFileMetadata {
        SampleFileMetadataReader.read(from: url, format: format)
    }

    private func loadWaveformIfNeeded(for sampleID: UUID) {
        guard waveformCache[sampleID] == nil,
              let sample = samples.first(where: { $0.id == sampleID }) else { return }

        let url = sample.url
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let waveform = Self.readWaveform(from: url) else { return }
            DispatchQueue.main.async {
                self?.waveformCache[sampleID] = waveform
            }
        }
    }

    nonisolated private static func readWaveform(from url: URL) -> SampleWaveform? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let processingFormat = file.processingFormat
        let frameCount = AVAudioFrameCount(file.length)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: processingFormat, frameCapacity: frameCount) else {
            return nil
        }

        do {
            try file.read(into: buffer)
        } catch {
            return nil
        }

        let peakCount = 512
        let totalFrames = Int(file.length)

        guard let channelData = buffer.floatChannelData?.pointee else { return nil }

        var peaks: [Float] = []
        peaks.reserveCapacity(peakCount)

        let stride = max(1, totalFrames / peakCount)
        for bucket in 0..<peakCount {
            let start = bucket * stride
            let end = min(totalFrames, start + stride)
            guard start < end else {
                peaks.append(0)
                continue
            }

            var peak: Float = 0
            for frame in start..<end {
                peak = max(peak, abs(channelData[frame]))
            }
            peaks.append(peak)
        }

        return SampleWaveform(totalFrames: totalFrames, peaks: peaks)
    }

    private func queueRootConflictPromptIfNeeded() {
        guard rootConflictChoice == nil else { return }
        guard samples.allSatisfy({ $0.fileEmbeddedRootNote == nil }) else { return }
        guard let conflicted = samples.first(where: \.rootDetectionConflict),
              let filenameRoot = conflicted.filenameRootNote,
              let analyzedRoot = conflicted.analyzedRootNote else { return }

        rootConflictChoice = RootConflictChoice(
            sampleID: conflicted.id,
            filename: conflicted.displayName,
            filenameRoot: filenameRoot,
            analyzedRoot: analyzedRoot
        )
    }

    private func mappedSample(for midiNote: Int) -> SampleZone? {
        if let selectedSample, (selectedSample.lowNote.midi...selectedSample.highNote.midi).contains(midiNote) {
            return selectedSample
        }

        let candidates = samples.filter { ($0.lowNote.midi...$0.highNote.midi).contains(midiNote) }
        if let best = candidates.min(by: {
            abs($0.rootNote.midi - midiNote) < abs($1.rootNote.midi - midiNote)
        }) {
            return best
        }

        return selectedSample ?? samples.first
    }

    private func writeMappingPackage(to packageURL: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: packageURL, withIntermediateDirectories: true)

        let transientsURL = packageURL.appendingPathComponent("Transients", isDirectory: true)
        try fileManager.createDirectory(at: transientsURL, withIntermediateDirectories: true)

        var entries: [SampleMapPackage.Entry] = []
        entries.reserveCapacity(samples.count)

        for (index, sample) in samples.enumerated() {
            let exportName = exportedTransientFilename(for: sample, index: index)
            let destinationURL = transientsURL.appendingPathComponent(exportName)

            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.copyItem(at: sample.url, to: destinationURL)

            entries.append(
                SampleMapPackage.Entry(
                    slotIndex: index,
                    displayName: sample.displayName,
                    exportedFileName: exportName,
                    originalRelativePath: sample.url.lastPathComponent,
                    format: sample.format.rawValue,
                    rootMIDINote: sample.rootNote.midi,
                    lowMIDINote: sample.lowNote.midi,
                    highMIDINote: sample.highNote.midi,
                    detectedRootMIDINote: sample.detectedRootNote?.midi,
                    embeddedRootMIDINote: sample.fileEmbeddedRootNote?.midi,
                    loopStartFrame: sample.loopPoints.startFrame,
                    loopEndFrame: sample.loopPoints.endFrame,
                    totalFrames: sample.totalFrames,
                    sampleRate: sample.sampleRate,
                    channelCount: sample.channelCount,
                    fileSize: sample.fileSize
                )
            )
        }

        let package = SampleMapPackage(
            version: 1,
            createdAtISO8601: ISO8601DateFormatter().string(from: Date()),
            sampleCount: samples.count,
            lowerReachSemitones: lowerReachSemitones,
            upperReachSemitones: upperReachSemitones,
            entries: entries
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let mapData = try encoder.encode(package)
        try mapData.write(to: packageURL.appendingPathComponent("map.json"), options: .atomic)
    }

    private func exportedTransientFilename(for sample: SampleZone, index: Int) -> String {
        let base = sample.url.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let ext = sample.url.pathExtension.isEmpty ? sample.format.rawValue : sample.url.pathExtension
        return String(format: "%02d_%@.%@", index + 1, base, ext)
    }
}
