//
//  SimilarityEngine.swift
//  brWave
//
//  Calculates distance between Wave patches to find sonic neighbours.
//  Ported from OBsixer — adapted for WaveParameters.
//  Parameters are range-normalised before distance computation.
//

import Foundation
import CoreData

struct SimilarityEngine {

    struct Match: Identifiable {
        let patch: Patch
        let score: Double          // 0.0 = identical, higher = more different
        var id: NSManagedObjectID { patch.objectID }
    }

    /// When false (default), the WAVETB index is excluded from the similarity vector.
    /// Enable in Settings once wavetable timbral fingerprinting is implemented.
    /// Keeping this false makes the engine portable to editors with no wavetable concept.
    static var useWavetableInVector: Bool {
        UserDefaults.standard.bool(forKey: "similarityUseWavetable")
    }

    // MARK: - Public API

    static func findSimilar(to patch: Patch, in context: NSManagedObjectContext,
                             limit: Int = 10) -> [Match] {
        findSimilar(to: patch.values, in: context, limit: limit, excluding: patch)
    }

    static func findSimilar(to data: Data?, in context: NSManagedObjectContext,
                             limit: Int = 10, excluding: Patch? = nil) -> [Match] {
        let req: NSFetchRequest<Patch> = Patch.fetchRequest()
        if let excluded = excluding {
            req.predicate = NSPredicate(format: "self != %@", excluded)
        }
        guard let candidates = try? context.fetch(req) else { return [] }

        let targetVec = patchToVector(data)
        var matches: [Match] = candidates.map {
            Match(patch: $0, score: euclideanDistance(v1: targetVec, v2: patchToVector($0.values)))
        }
        matches.sort { $0.score < $1.score }
        return Array(matches.prefix(limit))
    }

    // MARK: - Generation helpers

    /// Interpolates between two patch value blobs at ratio t (0.0 = all A, 1.0 = all B).
    /// Returns a new patchValues Data blob clamped to valid parameter ranges.
    static func interpolate(a: Data?, b: Data?, t: Double) -> Data? {
        let vA = patchToVector(a)
        let vB = patchToVector(b)
        guard vA.count == vB.count, !vA.isEmpty else { return nil }
        let blended = zip(vA, vB).map { aVal, bVal in aVal + (bVal - aVal) * t }
        return vectorToPatchValues(blended)
    }

    /// Adds Gaussian noise to a patch vector. sigma: 0.0–1.0 (fraction of normalised range).
    static func mutate(_ data: Data?, sigma: Double) -> Data? {
        var vec = patchToVector(data)
        for i in 0..<vec.count {
            vec[i] = min(1.0, max(0.0, vec[i] + gaussianNoise(sigma: sigma)))
        }
        return vectorToPatchValues(vec)
    }

    // MARK: - Vector

    /// Converts patch values to a normalised parameter vector.
    /// WAVETB dimension is zeroed unless `useWavetableInVector` is enabled in Settings.
    static func patchToVector(_ data: Data?) -> [Double] {
        let dict: [String: Int]
        if let data, let decoded = try? JSONDecoder().decode([String: Int].self, from: data) {
            dict = decoded
        } else {
            dict = [:]
        }
        return WaveParameters.all.map { desc in
            if desc.id == .wavetb && !useWavetableInVector { return 0.0 }
            let val = dict[desc.id.rawValue] ?? desc.range.lowerBound
            let lo  = Double(desc.range.lowerBound)
            let hi  = Double(desc.range.upperBound)
            return hi > lo ? (Double(val) - lo) / (hi - lo) : 0.0
        }
    }

    /// Converts a normalised vector back to a patchValues Data blob.
    static func vectorToPatchValues(_ vec: [Double]) -> Data? {
        let params = WaveParameters.all
        guard vec.count == params.count else { return nil }
        var dict: [String: Int] = [:]
        for (i, desc) in params.enumerated() {
            let lo  = Double(desc.range.lowerBound)
            let hi  = Double(desc.range.upperBound)
            let raw = hi > lo ? lo + vec[i] * (hi - lo) : lo
            dict[desc.id.rawValue] = Int(raw.rounded()) // clamped to Int conversion
        }
        return try? JSONEncoder().encode(dict)
    }

    // MARK: - Init patch detection

    /// Returns true if the patch has never been meaningfully programmed.
    /// An init patch has all parameters at their default (lower-bound) values,
    /// producing an all-zero normalised vector. These pollute Galaxy anchor
    /// calculations and should be excluded from layout and skipped on import.
    ///
    /// Threshold 0.04 allows for a couple of params being off default while
    /// still catching "Init Program" placeholders reliably.
    static func isInitVector(_ vec: [Double], threshold: Double = 0.04) -> Bool {
        guard !vec.isEmpty else { return true }
        // All-zero = every param at lower bound = never touched
        let magnitude = sqrt(vec.reduce(0) { $0 + $1 * $1 })
        return magnitude < threshold
    }

    static func isInitPatch(_ patch: Patch) -> Bool {
        isInitVector(patchToVector(patch.values))
    }

    // MARK: - Deduplication

    /// Remove exact-duplicate patches from a list.
    /// "Exact" means Euclidean distance = 0.0 in parameter space — identical sound.
    /// Within each duplicate group the patch with the earliest dateCreated is kept;
    /// the rest are deleted from the context.
    ///
    /// - Returns: number of patches deleted.
    @discardableResult
    static func removeDuplicates(from patches: [Patch],
                                 in context: NSManagedObjectContext) -> Int {
        var seen:    [[Double]: Patch] = [:]   // vector → keeper
        var removed = 0

        for patch in patches {
            let vec = patchToVector(patch.values)
            // Round to 6 decimal places so floating-point noise doesn't split identical patches
            let key = vec.map { (($0 * 1_000_000).rounded() / 1_000_000) }
            if let existing = seen[key] {
                // Keep whichever was created first
                let keepExisting = (existing.dateCreated ?? .distantFuture) <= (patch.dateCreated ?? .distantFuture)
                if keepExisting {
                    context.delete(patch)
                } else {
                    context.delete(existing)
                    seen[key] = patch
                }
                removed += 1
            } else {
                seen[key] = patch
            }
        }
        return removed
    }

    // MARK: - Distance

    static func euclideanDistance(v1: [Double], v2: [Double]) -> Double {
        let len = min(v1.count, v2.count)
        var sum = 0.0
        for i in 0..<len {
            let d = v1[i] - v2[i]
            sum += d * d
        }
        return sqrt(sum)
    }

    // MARK: - Private

    private static func gaussianNoise(sigma: Double) -> Double {
        // Box-Muller transform for Gaussian noise
        let u1 = Double.random(in: Double.ulpOfOne...1.0)
        let u2 = Double.random(in: 0.0...1.0)
        return sigma * sqrt(-2.0 * log(u1)) * cos(2.0 * .pi * u2)
    }
}
