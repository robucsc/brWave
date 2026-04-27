//
//  PatchSorter.swift
//  brWave
//
//  Reorders PatchSlots within a scope by reassigning position values.
//  Operates on whatever is in scope (selection, bank, or set) — the caller
//  resolves the patch list; this file only handles sort order and slot assignment.
//

import Foundation
import CoreData

enum PatchSortCriterion {
    case name
    case userCategory
    case galaxyCategory
    case wavetable          // WTs first (slots 0–48, 64–86), then Transients (49–63, 87–127)
    case envelopeFast       // short attack + decay first → long last
    case envelopeSlow       // long attack + release first → short last
    case sonicJourney       // nearest-neighbour chain through vector space
}

// Musical order for category sorts — roughly functional → textural.
private let categoryOrder: [PatchCategory] = [
    .bass, .lead, .poly, .arp, .sequence,
    .keys, .piano, .organ,
    .pad, .strings, .brass,
    .fx, .percussion,
    .uncategorized
]

enum PatchSorter {

    /// Sort `patches` by `criterion` and reassign their PatchSlot positions
    /// starting from `startPosition`, incrementing by 1.
    ///
    /// - Returns: number of patches repositioned.
    @discardableResult
    @MainActor
    static func sort(_ patches: [Patch],
                     by criterion: PatchSortCriterion,
                     startPosition: Int = 0,
                     in context: NSManagedObjectContext) -> Int {

        guard patches.count > 1 else { return 0 }

        let sorted = ordered(patches, by: criterion)

        // Reassign slot positions in the new order.
        // Build a map of patch → its current slot so we can update in place.
        let req: NSFetchRequest<PatchSlot> = PatchSlot.fetchRequest()
        req.predicate = NSPredicate(format: "patch IN %@", patches)
        guard let slots = try? context.fetch(req) else { return 0 }

        // One slot per patch (patches can appear in multiple sets — only touch
        // slots whose current position is in the target range).
        let targetPositions = Set((startPosition..<(startPosition + patches.count)).map { $0 })
        let slotsByPatch = Dictionary(
            slots.filter { targetPositions.contains(Int($0.position)) }
                 .compactMap { slot -> (NSManagedObjectID, PatchSlot)? in
                     guard let p = slot.patch else { return nil }
                     return (p.objectID, slot)
                 },
            uniquingKeysWith: { first, _ in first }
        )

        for (index, patch) in sorted.enumerated() {
            if let slot = slotsByPatch[patch.objectID] {
                slot.position = Int16(startPosition + index)
            }
        }

        try? context.save()
        return sorted.count
    }

    // MARK: - Ordering

    static func ordered(_ patches: [Patch], by criterion: PatchSortCriterion) -> [Patch] {
        switch criterion {

        case .name:
            return patches.sorted {
                ($0.name ?? "").localizedCaseInsensitiveCompare($1.name ?? "") == .orderedAscending
            }

        case .userCategory:
            return patches.sorted { a, b in
                let ai = categoryOrder.firstIndex(of: a.patchCategory) ?? categoryOrder.count
                let bi = categoryOrder.firstIndex(of: b.patchCategory) ?? categoryOrder.count
                if ai != bi { return ai < bi }
                return (a.name ?? "").localizedCaseInsensitiveCompare(b.name ?? "") == .orderedAscending
            }

        case .galaxyCategory:
            return patches.sorted { a, b in
                let ac = PatchCategory(rawValue: a.galaxyCluster ?? "") ?? .uncategorized
                let bc = PatchCategory(rawValue: b.galaxyCluster ?? "") ?? .uncategorized
                let ai = categoryOrder.firstIndex(of: ac) ?? categoryOrder.count
                let bi = categoryOrder.firstIndex(of: bc) ?? categoryOrder.count
                if ai != bi { return ai < bi }
                return (a.name ?? "").localizedCaseInsensitiveCompare(b.name ?? "") == .orderedAscending
            }

        case .wavetable:
            // All WTs first (factory 0–31, then user 64–127), then transients (32–63).
            // Numerically transients sit between the two WT ranges, so we group explicitly.
            func wtGroup(_ v: Int) -> Int {
                switch v {
                case 0...31:   return 0   // factory WT
                case 64...127: return 1   // user WT
                case 32...63:  return 2   // user transient
                default:       return 3
                }
            }
            return patches.sorted { a, b in
                let av = a.value(for: .wavetb)
                let bv = b.value(for: .wavetb)
                let ag = wtGroup(av), bg = wtGroup(bv)
                if ag != bg { return ag < bg }
                return av < bv
            }

        case .envelopeFast:
            // Low A2+D2 = punchy/fast. Sort ascending = fast first.
            return patches.sorted {
                envelopeScore($0) < envelopeScore($1)
            }

        case .envelopeSlow:
            // High A2+R2 = slow/pad. Sort descending = slow first.
            return patches.sorted {
                envelopeScore($0) > envelopeScore($1)
            }

        case .sonicJourney:
            return sonicJourney(patches)
        }
    }

    // MARK: - Envelope score

    /// Combined loudness envelope character score.
    /// Low = fast/punchy (short attack + decay), High = slow/pad (long attack + release).
    private static func envelopeScore(_ patch: Patch) -> Int {
        let a = patch.value(for: .a2)  // attack
        let d = patch.value(for: .d2)  // decay
        let r = patch.value(for: .r2)  // release
        // Weight attack heavily — it's the primary "fast vs slow" perception driver.
        return a * 2 + d + r
    }

    // MARK: - Sonic journey (nearest-neighbour chain)

    /// Greedy nearest-neighbour walk through vector space.
    /// Starts from whichever patch has the lowest current position (first in bank),
    /// then repeatedly picks the closest unvisited neighbour.
    /// Result: a smooth sonic journey where adjacent slots sound related.
    private static func sonicJourney(_ patches: [Patch]) -> [Patch] {
        guard patches.count > 1 else { return patches }

        var vectors = [NSManagedObjectID: [Double]]()
        for p in patches { vectors[p.objectID] = SimilarityEngine.patchToVector(p.values) }

        var remaining = patches.sorted { Int($0.bank) * 100 + Int($0.program) < Int($1.bank) * 100 + Int($1.program) }
        var result: [Patch] = []
        result.append(remaining.removeFirst())

        while !remaining.isEmpty {
            let lastVec = vectors[result.last!.objectID] ?? []
            var bestIdx = 0
            var bestDist = Double.infinity
            for (i, candidate) in remaining.enumerated() {
                let d = SimilarityEngine.euclideanDistance(
                    v1: lastVec,
                    v2: vectors[candidate.objectID] ?? []
                )
                if d < bestDist { bestDist = d; bestIdx = i }
            }
            result.append(remaining.remove(at: bestIdx))
        }

        return result
    }
}
