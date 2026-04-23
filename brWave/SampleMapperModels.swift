//
//  SampleMapperModels.swift
//  brWave
//

import AVFoundation
import Foundation

enum SampleFileFormat: String, CaseIterable, Identifiable {
    case wav
    case aiff
    case caf
    case yaf
    case sdi
    case sdii

    var id: String { rawValue }

    var label: String {
        rawValue.uppercased()
    }

    static let supportedExtensions: Set<String> = [
        "wav", "aiff", "aif", "caf", "yaf", "sdi", "sdii"
    ]

    static func from(url: URL) -> SampleFileFormat? {
        switch url.pathExtension.lowercased() {
        case "wav":
            return .wav
        case "aiff", "aif":
            return .aiff
        case "caf":
            return .caf
        case "yaf":
            return .yaf
        case "sdi":
            return .sdi
        case "sdii":
            return .sdii
        default:
            return nil
        }
    }
}

struct SampleNote: Hashable, Comparable, Identifiable {
    let midi: Int

    var id: Int { midi }

    var label: String {
        let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let octave = (midi / 12) - 1
        let note = noteNames[max(0, min(11, midi % 12))]
        return "\(note)\(octave)"
    }

    var shortLabel: String {
        label.replacingOccurrences(of: "#", with: "♯")
    }

    static func < (lhs: SampleNote, rhs: SampleNote) -> Bool {
        lhs.midi < rhs.midi
    }

    static let all: [SampleNote] = (0...127).map { SampleNote(midi: $0) }

    static let c0 = SampleNote(midi: 12)
    static let c1 = SampleNote(midi: 24)
    static let c2 = SampleNote(midi: 36)
    static let c3 = SampleNote(midi: 48)
    static let c4 = SampleNote(midi: 60)
    static let c5 = SampleNote(midi: 72)
    static let c6 = SampleNote(midi: 84)
}

struct SampleLoopPoints: Hashable {
    var startFrame: Int = 0
    var endFrame: Int = 0
}

struct SampleWaveform: Hashable {
    let totalFrames: Int
    let peaks: [Float]
}

struct SampleZone: Identifiable, Hashable {
    let id: UUID
    let url: URL
    let format: SampleFileFormat
    var rootNote: SampleNote
    var lowNote: SampleNote
    var highNote: SampleNote
    var detectedRootNote: SampleNote?
    var filenameRootNote: SampleNote?
    var fileEmbeddedRootNote: SampleNote?
    var analyzedRootNote: SampleNote?
    var loopPoints: SampleLoopPoints
    var totalFrames: Int?
    var sampleRate: Double?
    var channelCount: Int?
    var fileSize: Int64
    /// Hardware TR slot assignment (32–63). Nil = unassigned.
    var trSlot: Int?

    var displayName: String {
        url.lastPathComponent
    }

    var rootWasDetected: Bool {
        filenameRootNote != nil || fileEmbeddedRootNote != nil || analyzedRootNote != nil
    }

    var rootDetectionConflict: Bool {
        guard let filenameRootNote, let analyzedRootNote else { return false }
        return filenameRootNote != analyzedRootNote
    }
}

struct SampleFileMetadata {
    var totalFrames: Int?
    var sampleRate: Double?
    var channelCount: Int?
    var loopPoints: SampleLoopPoints?
    var embeddedRootNote: SampleNote?
}

struct SampleMapPackage: Codable {
    struct Entry: Codable {
        let slotIndex: Int
        let displayName: String
        let exportedFileName: String
        let originalRelativePath: String
        let format: String
        let rootMIDINote: Int
        let lowMIDINote: Int
        let highMIDINote: Int
        let detectedRootMIDINote: Int?
        let embeddedRootMIDINote: Int?
        let loopStartFrame: Int
        let loopEndFrame: Int
        let totalFrames: Int?
        let sampleRate: Double?
        let channelCount: Int?
        let fileSize: Int64
    }

    let version: Int
    let createdAtISO8601: String
    let sampleCount: Int
    let lowerReachSemitones: Int
    let upperReachSemitones: Int
    let entries: [Entry]
}

enum SampleFileMetadataReader {
    static func read(from url: URL, format: SampleFileFormat) -> SampleFileMetadata {
        let baseMetadata = readBaseAudioMetadata(from: url)
        let embedded: (loopPoints: SampleLoopPoints?, root: SampleNote?)

        switch format {
        case .wav:
            embedded = readWAVMetadata(from: url)
        case .aiff:
            embedded = readAIFFMetadata(from: url)
        case .caf, .yaf, .sdi, .sdii:
            embedded = (nil, nil)
        }

        return SampleFileMetadata(
            totalFrames: baseMetadata.totalFrames,
            sampleRate: baseMetadata.sampleRate,
            channelCount: baseMetadata.channelCount,
            loopPoints: embedded.loopPoints,
            embeddedRootNote: embedded.root
        )
    }

    private static func readBaseAudioMetadata(from url: URL) -> (totalFrames: Int?, sampleRate: Double?, channelCount: Int?) {
        guard let audioFile = try? AVAudioFile(forReading: url) else {
            return (nil, nil, nil)
        }

        return (
            Int(audioFile.length),
            audioFile.processingFormat.sampleRate,
            Int(audioFile.processingFormat.channelCount)
        )
    }

    private static func readWAVMetadata(from url: URL) -> (loopPoints: SampleLoopPoints?, root: SampleNote?) {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              data.count >= 12,
              data.ascii(at: 0, length: 4) == "RIFF",
              data.ascii(at: 8, length: 4) == "WAVE" else {
            return (nil, nil)
        }

        var offset = 12
        var loopPoints: SampleLoopPoints?
        var root: SampleNote?

        while offset + 8 <= data.count {
            let chunkID = data.ascii(at: offset, length: 4)
            let chunkSize = Int(data.uint32LE(at: offset + 4))
            let chunkStart = offset + 8
            let chunkEnd = min(data.count, chunkStart + chunkSize)
            guard chunkEnd >= chunkStart else { break }

            switch chunkID {
            case "smpl":
                if chunkEnd - chunkStart >= 36 {
                    let midiUnity = Int(data.uint32LE(at: chunkStart + 12))
                    if (0...127).contains(midiUnity) {
                        root = SampleNote(midi: midiUnity)
                    }

                    let loopCount = Int(data.uint32LE(at: chunkStart + 28))
                    if loopCount > 0, chunkEnd - chunkStart >= 60 {
                        let firstLoop = chunkStart + 36
                        let start = Int(data.uint32LE(at: firstLoop + 8))
                        let end = Int(data.uint32LE(at: firstLoop + 12))
                        loopPoints = SampleLoopPoints(
                            startFrame: max(0, start),
                            endFrame: max(start, end)
                        )
                    }
                }
            case "inst":
                if root == nil, chunkEnd - chunkStart >= 1 {
                    let baseNote = Int(data[chunkStart])
                    if (0...127).contains(baseNote) {
                        root = SampleNote(midi: baseNote)
                    }
                }
            default:
                break
            }

            offset = chunkStart + chunkSize + (chunkSize % 2)
        }

        return (loopPoints, root)
    }

    private static func readAIFFMetadata(from url: URL) -> (loopPoints: SampleLoopPoints?, root: SampleNote?) {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              data.count >= 12,
              data.ascii(at: 0, length: 4) == "FORM" else {
            return (nil, nil)
        }

        let formType = data.ascii(at: 8, length: 4)
        guard formType == "AIFF" || formType == "AIFC" else {
            return (nil, nil)
        }

        var offset = 12
        var markerPositions: [UInt16: Int] = [:]
        var loopPoints: SampleLoopPoints?
        var root: SampleNote?

        while offset + 8 <= data.count {
            let chunkID = data.ascii(at: offset, length: 4)
            let chunkSize = Int(data.uint32BE(at: offset + 4))
            let chunkStart = offset + 8
            let chunkEnd = min(data.count, chunkStart + chunkSize)
            guard chunkEnd >= chunkStart else { break }

            switch chunkID {
            case "MARK":
                if chunkEnd - chunkStart >= 2 {
                    let markerCount = Int(data.uint16BE(at: chunkStart))
                    var markerOffset = chunkStart + 2

                    for _ in 0..<markerCount {
                        guard markerOffset + 7 <= chunkEnd else { break }
                        let markerID = data.uint16BE(at: markerOffset)
                        let position = Int(data.uint32BE(at: markerOffset + 2))
                        let nameLength = Int(data[markerOffset + 6])
                        markerPositions[markerID] = position

                        markerOffset += 7 + nameLength
                        if (1 + nameLength) % 2 != 0 {
                            markerOffset += 1
                        }
                    }
                }
            case "INST":
                if chunkEnd - chunkStart >= 20 {
                    let baseNote = Int(data[chunkStart])
                    if (0...127).contains(baseNote) {
                        root = SampleNote(midi: baseNote)
                    }

                    let sustainPlayMode = data.uint16BE(at: chunkStart + 8)
                    if sustainPlayMode != 0 {
                        let beginMarker = data.uint16BE(at: chunkStart + 10)
                        let endMarker = data.uint16BE(at: chunkStart + 12)
                        if let begin = markerPositions[beginMarker],
                           let end = markerPositions[endMarker] {
                            loopPoints = SampleLoopPoints(
                                startFrame: max(0, begin),
                                endFrame: max(begin, end)
                            )
                        }
                    }
                }
            default:
                break
            }

            offset = chunkStart + chunkSize + (chunkSize % 2)
        }

        return (loopPoints, root)
    }
}

private extension Data {
    func ascii(at offset: Int, length: Int) -> String {
        guard offset >= 0, length >= 0, offset + length <= count else { return "" }
        return String(decoding: self[offset..<(offset + length)], as: UTF8.self)
    }

    func uint16BE(at offset: Int) -> UInt16 {
        guard offset >= 0, offset + 2 <= count else { return 0 }
        return (UInt16(self[offset]) << 8) | UInt16(self[offset + 1])
    }

    func uint32BE(at offset: Int) -> UInt32 {
        guard offset >= 0, offset + 4 <= count else { return 0 }
        return (UInt32(self[offset]) << 24)
            | (UInt32(self[offset + 1]) << 16)
            | (UInt32(self[offset + 2]) << 8)
            | UInt32(self[offset + 3])
    }

    func uint32LE(at offset: Int) -> UInt32 {
        guard offset >= 0, offset + 4 <= count else { return 0 }
        return UInt32(self[offset])
            | (UInt32(self[offset + 1]) << 8)
            | (UInt32(self[offset + 2]) << 16)
            | (UInt32(self[offset + 3]) << 24)
    }
}

enum SamplePitchDetector {
    private static let noteMap: [String: Int] = [
        "C": 0, "C#": 1, "DB": 1,
        "D": 2, "D#": 3, "EB": 3,
        "E": 4,
        "F": 5, "F#": 6, "GB": 6,
        "G": 7, "G#": 8, "AB": 8,
        "A": 9, "A#": 10, "BB": 10,
        "B": 11
    ]

    static func detectFilenameRootNote(from url: URL) -> SampleNote? {
        let base = url.deletingPathExtension().lastPathComponent.uppercased()
        let patterns = [
            #"(?<![A-Z0-9])(C#|DB|D#|EB|F#|GB|G#|AB|A#|BB|C|D|E|F|G|A|B)(-?\d)(?![A-Z0-9])"#,
            #"(?<![A-Z0-9])(C_SHARP|D_FLAT|D_SHARP|E_FLAT|F_SHARP|G_FLAT|G_SHARP|A_FLAT|A_SHARP|B_FLAT)(-?\d)(?![A-Z0-9])"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let nsBase = base as NSString
            let range = NSRange(location: 0, length: nsBase.length)
            guard let match = regex.firstMatch(in: base, range: range), match.numberOfRanges >= 3 else { continue }

            var noteToken = nsBase.substring(with: match.range(at: 1))
            noteToken = noteToken
                .replacingOccurrences(of: "_SHARP", with: "#")
                .replacingOccurrences(of: "_FLAT", with: "B")

            let octaveString = nsBase.substring(with: match.range(at: 2))
            guard let semitone = noteMap[noteToken],
                  let octave = Int(octaveString) else { continue }

            let midi = ((octave + 1) * 12) + semitone
            guard (0...127).contains(midi) else { continue }
            return SampleNote(midi: midi)
        }

        return nil
    }

    static func detectAnalyzedRootNote(from url: URL) -> SampleNote? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let sampleRate = file.processingFormat.sampleRate
        let totalFrames = Int(file.length)
        guard totalFrames > 2048 else { return nil }

        let windowFrameCount = min(totalFrames, 8192)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(windowFrameCount)) else {
            return nil
        }

        do {
            try file.read(into: buffer, frameCount: AVAudioFrameCount(windowFrameCount))
        } catch {
            return nil
        }

        guard let channelData = buffer.floatChannelData?.pointee else { return nil }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 2048 else { return nil }

        let samples = Array(UnsafeBufferPointer(start: channelData, count: frameLength))
        let centered = removeDC(from: samples)

        let minFrequency = 32.0
        let maxFrequency = 2093.0
        let minLag = max(8, Int(sampleRate / maxFrequency))
        let maxLag = min(frameLength / 2, Int(sampleRate / minFrequency))
        guard minLag < maxLag else { return nil }

        var bestLag = 0
        var bestScore = 0.0 as Float

        for lag in minLag...maxLag {
            var correlation: Float = 0
            var energyA: Float = 0
            var energyB: Float = 0

            let count = frameLength - lag
            if count <= 0 { continue }

            for index in 0..<count {
                let a = centered[index]
                let b = centered[index + lag]
                correlation += a * b
                energyA += a * a
                energyB += b * b
            }

            let normalizer = sqrt(max(energyA * energyB, 0.0001))
            let score = correlation / normalizer
            if score > bestScore {
                bestScore = score
                bestLag = lag
            }
        }

        guard bestLag > 0, bestScore > 0.55 else { return nil }

        let frequency = sampleRate / Double(bestLag)
        let midi = Int(round(69 + (12 * log2(frequency / 440.0))))
        guard (0...127).contains(midi) else { return nil }
        return SampleNote(midi: midi)
    }

    private static func removeDC(from samples: [Float]) -> [Float] {
        guard !samples.isEmpty else { return samples }
        let mean = samples.reduce(0, +) / Float(samples.count)
        return samples.map { $0 - mean }
    }
}

enum SampleAutoMapper {
    static func assignZones(
        _ samples: [SampleZone],
        lowerReach: Int = 5,
        upperReach: Int = 7
    ) -> [SampleZone] {
        guard !samples.isEmpty else { return [] }

        let indexed = samples.enumerated().map { ($0.offset, $0.element) }
        let sorted = indexed.sorted {
            if $0.1.rootNote == $1.1.rootNote {
                return $0.1.displayName.localizedCaseInsensitiveCompare($1.1.displayName) == .orderedAscending
            }
            return $0.1.rootNote < $1.1.rootNote
        }

        var updated = samples

        for (position, item) in sorted.enumerated() {
            let root = item.1.rootNote.midi
            let previousRoot = position > 0 ? sorted[position - 1].1.rootNote.midi : nil
            let nextRoot = position < sorted.count - 1 ? sorted[position + 1].1.rootNote.midi : nil

            let naturalLow = max(0, root - lowerReach)
            let naturalHigh = min(127, root + upperReach)

            let lowBoundary = previousRoot.map { Int(floor(Double($0 + root) / 2.0)) + 1 } ?? 0
            let highBoundary = nextRoot.map { Int(floor(Double(root + $0) / 2.0)) } ?? 127

            let low = max(naturalLow, lowBoundary)
            let high = min(naturalHigh, highBoundary)

            updated[item.0].lowNote = SampleNote(midi: low)
            updated[item.0].highNote = SampleNote(midi: max(low, high))
        }

        return updated
    }
}
