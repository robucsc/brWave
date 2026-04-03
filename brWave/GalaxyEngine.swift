//
//  GalaxyEngine.swift
//  brWave
//
//  Positions patches in 2D space based on similarity to category anchors.
//  Ported from OBsixer — adapted for brWave (PatchCategory, WaveParameters).
//

import Foundation
import CoreData
import SwiftUI

// MARK: - GalaxyEngine

class GalaxyEngine {

    struct Anchor {
        let category: PatchCategory
        let position: CGPoint
        let vector:   [Double]
    }

    static let shared = GalaxyEngine()

    public private(set) var anchors: [Anchor] = []
    public private(set) var anchorsFromRealData = false

    private let displayRadius: Double = 0.8

    private struct PatchLayout {
        let gravityX, gravityY: Double
        let displayX, displayY: Double
    }
    private var layoutCache: [NSManagedObjectID: PatchLayout] = [:]

    init() {}

    // MARK: - Layout bootstrap

    func bootstrapLayout(for patch: Patch) {
        guard let data = patch.values, let g = computeGravity(for: data) else { return }
        let isUnpositioned = patch.galaxyX == 0 && patch.galaxyY == 0
        if isUnpositioned { patch.galaxyX = g.x; patch.galaxyY = g.y }
        layoutCache[patch.objectID] = PatchLayout(
            gravityX: g.x, gravityY: g.y,
            displayX: patch.galaxyX, displayY: patch.galaxyY
        )
    }

    func bootstrapLayoutIfNeeded(for patch: Patch) {
        guard layoutCache[patch.objectID] == nil,
              let data = patch.values,
              let g = computeGravity(for: data) else { return }
        let isUnpositioned = patch.galaxyX == 0 && patch.galaxyY == 0
        layoutCache[patch.objectID] = PatchLayout(
            gravityX: g.x, gravityY: g.y,
            displayX: isUnpositioned ? g.x : patch.galaxyX,
            displayY: isUnpositioned ? g.y : patch.galaxyY
        )
    }

    // MARK: - Live update

    func scheduleGalaxyUpdate(for patch: Patch) {
        if Thread.isMainThread { updatePosition(for: patch) }
        else { DispatchQueue.main.async { [weak self] in self?.updatePosition(for: patch) } }
    }

    func updatePosition(for patch: Patch) {
        guard let data = patch.values, let g = computeGravity(for: data) else { return }
        patch.galaxyCluster = g.cluster
        if let base = layoutCache[patch.objectID] {
            patch.galaxyX = base.displayX + (g.x - base.gravityX)
            patch.galaxyY = base.displayY + (g.y - base.gravityY)
        } else {
            patch.galaxyX = g.x
            patch.galaxyY = g.y
        }
    }

    // MARK: - Batch update

    func updateAll(in context: NSManagedObjectContext) {
        setupAnchorsFromRealPatches(in: context)
        guard !anchors.isEmpty else { return }

        let req: NSFetchRequest<Patch> = Patch.fetchRequest()
        guard let patches = try? context.fetch(req) else { return }

        for patch in patches {
            guard let data = patch.values, let g = computeGravity(for: data) else { continue }
            let (jx, jy) = stableJitter(for: patch)
            let displayX = g.x + jx
            let displayY = g.y + jy
            patch.galaxyX       = displayX
            patch.galaxyY       = displayY
            patch.galaxyCluster = g.cluster
            layoutCache[patch.objectID] = PatchLayout(
                gravityX: g.x, gravityY: g.y,
                displayX: displayX, displayY: displayY
            )
        }
        try? context.save()
        print("GalaxyEngine: updated \(patches.count) patches across \(anchors.count) anchors.")
    }

    // MARK: - Anchor construction from real patches

    private func setupAnchorsFromRealPatches(in context: NSManagedObjectContext) {
        let req: NSFetchRequest<Patch> = Patch.fetchRequest()
        guard let patches = try? context.fetch(req), !patches.isEmpty else { return }

        var grouped: [PatchCategory: [[Double]]] = [:]
        for patch in patches {
            let cat = PatchCategory.classify(patchName: patch.name ?? "")
            grouped[cat, default: []].append(SimilarityEngine.patchToVector(patch.values))
        }
        guard !grouped.isEmpty else { return }

        var pairs: [(category: PatchCategory, vector: [Double])] = []
        for (cat, vectors) in grouped where !vectors.isEmpty {
            let dim      = vectors[0].count
            var centroid = [Double](repeating: 0, count: dim)
            for vec in vectors {
                for i in 0..<min(dim, vec.count) { centroid[i] += vec[i] }
            }
            let n = Double(vectors.count)
            pairs.append((cat, centroid.map { $0 / n }))
        }

        buildAnchors(from: pairs)
        anchorsFromRealData = true
        print("GalaxyEngine: anchors rebuilt from \(patches.count) patches (\(pairs.count) categories).")
    }

    // MARK: - MDS layout

    private func buildAnchors(from pairs: [(category: PatchCategory, vector: [Double])]) {
        guard !pairs.isEmpty else { return }
        let sorted = pairs.sorted { $0.category.rawValue < $1.category.rawValue }
        let n      = sorted.count

        var raw    = Array(repeating: Array(repeating: 0.0, count: n), count: n)
        var maxRaw = 0.0
        for i in 0..<n {
            for j in (i+1)..<n {
                let d = SimilarityEngine.euclideanDistance(v1: sorted[i].vector, v2: sorted[j].vector)
                raw[i][j] = d; raw[j][i] = d
                maxRaw = max(maxRaw, d)
            }
        }
        let normScale = maxRaw > 0 ? maxRaw : 1.0

        let step = (2.0 * .pi) / Double(n)
        var temp: [Anchor] = sorted.enumerated().map { (idx, pair) in
            Anchor(category: pair.category,
                   position: CGPoint(x: cos(Double(idx) * step), y: sin(Double(idx) * step)),
                   vector: pair.vector)
        }

        for _ in 0..<1000 {
            var disp = Array(repeating: CGPoint.zero, count: n)
            for i in 0..<n {
                for j in 0..<n where i != j {
                    let dx = Double(temp[i].position.x - temp[j].position.x)
                    let dy = Double(temp[i].position.y - temp[j].position.y)
                    let cd = sqrt(dx*dx + dy*dy) + 0.0001
                    let id = (raw[i][j] / normScale) * displayRadius
                    let s  = (cd - id) * 0.01
                    disp[i] = CGPoint(x: disp[i].x - (dx/cd)*s, y: disp[i].y - (dy/cd)*s)
                }
            }
            for i in 0..<n {
                temp[i] = Anchor(category: temp[i].category,
                                 position: CGPoint(x: temp[i].position.x + disp[i].x,
                                                   y: temp[i].position.y + disp[i].y),
                                 vector: temp[i].vector)
            }
        }

        let cx = temp.map { Double($0.position.x) }.reduce(0,+) / Double(n)
        let cy = temp.map { Double($0.position.y) }.reduce(0,+) / Double(n)
        var maxD = 0.0
        for a in temp { maxD = max(maxD, sqrt(pow(Double(a.position.x)-cx,2)+pow(Double(a.position.y)-cy,2))) }
        let sc = maxD > 0 ? displayRadius / maxD : 1.0

        anchors = temp.map {
            Anchor(category: $0.category,
                   position: CGPoint(x: (Double($0.position.x)-cx)*sc, y: (Double($0.position.y)-cy)*sc),
                   vector: $0.vector)
        }
    }

    // MARK: - Gravity

    private func computeGravity(for data: Data) -> (x: Double, y: Double, cluster: String)? {
        guard !anchors.isEmpty else { return nil }
        let vec = SimilarityEngine.patchToVector(data)
        let ranked = anchors
            .map { ($0, SimilarityEngine.euclideanDistance(v1: vec, v2: $0.vector)) }
            .sorted { $0.1 < $1.1 }
        guard let closest = ranked.first else { return nil }
        let local = ranked.prefix(3)
        var totalW = 0.0, wx = 0.0, wy = 0.0
        for (anchor, dist) in local {
            let w = 1.0 / pow(dist + 0.01, 2.0)
            wx += Double(anchor.position.x) * w
            wy += Double(anchor.position.y) * w
            totalW += w
        }
        guard totalW > 0 else { return nil }
        return (wx/totalW, wy/totalW, closest.0.category.rawValue)
    }

    private func stableJitter(for patch: Patch) -> (Double, Double) {
        let h      = abs((patch.uuid ?? UUID()).hashValue)
        let angle  = Double(h % 10_000) / 10_000.0 * 2.0 * .pi
        let radius = Double((h >> 14) % 100) / 100.0 * 0.06
        return (cos(angle) * radius, sin(angle) * radius)
    }
}
