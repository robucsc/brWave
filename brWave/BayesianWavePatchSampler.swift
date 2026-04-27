//
//  BayesianWavePatchSampler.swift
//  brWave
//
//  Wave adapter around the generic BayesianVectorSampler.
//  Handles vectorize (Patch → [Double]) via GalaxyEngine
//  and materialize ([Double] → Data) via SimilarityEngine.
//

import Foundation
import Combine

// MARK: - BayesianWavePatchSampler

@MainActor
final class BayesianWavePatchSampler: ObservableObject {

    let sampler = BayesianVectorSampler()

    var regimeHistory:   [VectorRegime] { sampler.regimeHistory }
    var currentRegime:   VectorRegime?  { sampler.currentRegime }
    var posteriorVector: [Double]       { sampler.posteriorVector }
    var accumulator:     Double         { sampler.accumulator }

    var priorStrength: Double { get { sampler.priorStrength } set { sampler.priorStrength = newValue } }
    var snapThreshold: Double { get { sampler.snapThreshold } set { sampler.snapThreshold = newValue } }
    var decayRate:     Double { get { sampler.decayRate }     set { sampler.decayRate     = newValue } }

    // MARK: - Seed from category centroid

    func seed(for category: PatchCategory) {
        guard let anchor = GalaxyEngine.shared.anchors
            .first(where: { $0.category == category }) else { return }
        sampler.seed(prior: anchor.vector,
                     label: "\(category.rawValue.capitalized) Centroid")
    }

    // MARK: - Seed from a specific patch

    func seed(from patch: Patch, label: String? = nil) {
        let vector = GalaxyEngine.shared.vector(for: patch)
        guard !vector.isEmpty else { return }
        sampler.seed(prior: vector, label: label ?? patch.name ?? "Selected Patch")
    }

    // MARK: - Incorporate a patch as evidence

    @discardableResult
    func incorporate(_ patch: Patch, weight: Double = 1.0) -> Bool {
        sampler.incorporate(GalaxyEngine.shared.vector(for: patch), weight: weight)
    }

    // MARK: - Sort patches by proximity to current prior

    func sortedByProximityToPrior(_ patches: [Patch]) -> [Patch] {
        sampler.sorted(patches) { GalaxyEngine.shared.vector(for: $0) }
    }

    // MARK: - Generate patchValues Data from posterior

    /// Returns a JSON dict Data blob (patch.values format) materialized from the
    /// current posterior vector. Apply this to patch.values, then call
    /// patch.rebuildRawSysex() to keep rawSysexPayload in sync for hardware send.
    func generate() -> Data? {
        let v = sampler.posteriorVector
        guard !v.isEmpty else {
            return currentRegime.flatMap { SimilarityEngine.vectorToPatchValues($0.center) }
        }
        return SimilarityEngine.vectorToPatchValues(v)
    }

    // MARK: - Delegation

    func manualSnap(label: String? = nil) { sampler.manualSnap(label: label) }
    @discardableResult func rollback() -> VectorRegime? { sampler.rollback() }
    func reset() { sampler.reset() }
}
