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

    // MARK: - Vector

    /// Converts patch values to a normalised parameter vector.
    static func patchToVector(_ data: Data?) -> [Double] {
        let dict: [String: Int]
        if let data, let decoded = try? JSONDecoder().decode([String: Int].self, from: data) {
            dict = decoded
        } else {
            dict = [:]
        }
        return WaveParameters.all.map { desc in
            let val = dict[desc.id.rawValue] ?? desc.range.lowerBound
            let lo  = Double(desc.range.lowerBound)
            let hi  = Double(desc.range.upperBound)
            return hi > lo ? (Double(val) - lo) / (hi - lo) : 0.0
        }
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
}
