//
//  SampleMapperModels.swift
//  brWave
//

import AVFoundation
import Foundation

enum SampleFileFormat: String, CaseIterable, Identifiable {
    case wav
    case aiff
    case yaf
    case sdi
    case sdii

    var id: String { rawValue }

    var label: String {
        rawValue.uppercased()
    }

    static let supportedExtensions: Set<String> = [
        "wav", "aiff", "aif", "yaf", "sdi", "sdii"
    ]

    static func from(url: URL) -> SampleFileFormat? {
        switch url.pathExtension.lowercased() {
        case "wav":
            return .wav
        case "aiff", "aif":
            return .aiff
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
    var analyzedRootNote: SampleNote?
    var loopPoints: SampleLoopPoints
    var totalFrames: Int?
    var sampleRate: Double?
    var channelCount: Int?
    var fileSize: Int64

    var displayName: String {
        url.lastPathComponent
    }

    var rootWasDetected: Bool {
        filenameRootNote != nil || analyzedRootNote != nil
    }

    var rootDetectionConflict: Bool {
        guard let filenameRootNote, let analyzedRootNote else { return false }
        return filenameRootNote != analyzedRootNote
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
