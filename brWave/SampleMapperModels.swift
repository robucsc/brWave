//
//  SampleMapperModels.swift
//  brWave
//

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
    var loopPoints: SampleLoopPoints
    var totalFrames: Int?
    var sampleRate: Double?
    var channelCount: Int?
    var fileSize: Int64

    var displayName: String {
        url.lastPathComponent
    }

    var rootWasDetected: Bool {
        detectedRootNote != nil
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

    static func detectRootNote(from url: URL) -> SampleNote? {
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
        var previousHigh: Int?

        for (position, item) in sorted.enumerated() {
            let root = item.1.rootNote.midi
            let nextRoot = position < sorted.count - 1 ? sorted[position + 1].1.rootNote.midi : nil

            let baseLow = max(0, root - lowerReach)
            let low = min(root, max(baseLow, previousHigh ?? 0))

            let unclampedHigh = min(127, root + upperReach)
            let high = nextRoot.map { min(unclampedHigh, max(root, $0 - 1)) } ?? unclampedHigh

            updated[item.0].lowNote = SampleNote(midi: low)
            updated[item.0].highNote = SampleNote(midi: max(low, high))
            previousHigh = max(low, high)
        }

        return updated
    }
}
