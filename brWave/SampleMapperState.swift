//
//  SampleMapperState.swift
//  brWave
//

import AppKit
import AVFoundation
import Combine
import Foundation
import UniformTypeIdentifiers

@MainActor
final class SampleMapperState: ObservableObject {
    @Published var samples: [SampleZone] = []
    @Published var selectedSampleID: UUID?
    @Published var lowerReachSemitones: Int = 5
    @Published var upperReachSemitones: Int = 7
    @Published private(set) var waveformCache: [UUID: SampleWaveform] = [:]

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
        samples.removeAll()
        selectedSampleID = nil
        waveformCache.removeAll()
    }

    func autoMap() {
        samples = SampleAutoMapper.assignZones(
            samples,
            lowerReach: lowerReachSemitones,
            upperReach: upperReachSemitones
        )
    }

    func updateRoot(for sampleID: UUID, to note: SampleNote) {
        guard let idx = samples.firstIndex(where: { $0.id == sampleID }) else { return }
        samples[idx].rootNote = note
        autoMap()
    }

    func updateLow(for sampleID: UUID, to note: SampleNote) {
        guard let idx = samples.firstIndex(where: { $0.id == sampleID }) else { return }
        samples[idx].lowNote = note
    }

    func updateHigh(for sampleID: UUID, to note: SampleNote) {
        guard let idx = samples.firstIndex(where: { $0.id == sampleID }) else { return }
        samples[idx].highNote = note
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

    private func importURLs(_ urls: [URL]) {
        let built = urls.compactMap(buildSample(from:))
        guard !built.isEmpty else { return }

        samples = SampleAutoMapper.assignZones(
            built,
            lowerReach: lowerReachSemitones,
            upperReach: upperReachSemitones
        )
        if let firstID = samples.first?.id {
            selectSample(firstID)
        }
    }

    private func buildSample(from url: URL) -> SampleZone? {
        guard let format = SampleFileFormat.from(url: url) else { return nil }
        let detectedRoot = SamplePitchDetector.detectRootNote(from: url)
        let initialRoot = detectedRoot ?? .c3
        let fileAttributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = (fileAttributes?[.size] as? NSNumber)?.int64Value ?? 0

        let metadata = readAudioMetadata(from: url)
        let totalFrames = metadata.totalFrames

        return SampleZone(
            id: UUID(),
            url: url,
            format: format,
            rootNote: initialRoot,
            lowNote: initialRoot,
            highNote: initialRoot,
            detectedRootNote: detectedRoot,
            loopPoints: SampleLoopPoints(startFrame: 0, endFrame: totalFrames ?? 0),
            totalFrames: totalFrames,
            sampleRate: metadata.sampleRate,
            channelCount: metadata.channelCount,
            fileSize: fileSize
        )
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

    private func readAudioMetadata(from url: URL) -> (totalFrames: Int?, sampleRate: Double?, channelCount: Int?) {
        guard let audioFile = try? AVAudioFile(forReading: url) else {
            return (nil, nil, nil)
        }

        return (
            Int(audioFile.length),
            audioFile.processingFormat.sampleRate,
            Int(audioFile.processingFormat.channelCount)
        )
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

    private static func readWaveform(from url: URL) -> SampleWaveform? {
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
}
