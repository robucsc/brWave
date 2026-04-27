//
//  BayesianVectorSampler.swift
//  brWave
//
//  Engine-agnostic Bayesian sampler with snap-triggered regime switching.
//  Operates entirely on normalized [Double] vectors (0–1 per dimension).
//  No synth-specific code — usable in any editor (Wave, OB-6, Matrix-6, etc.).
//
//  Integration pattern:
//    1. Seed with a prior vector (e.g. category centroid from GalaxyEngine)
//    2. Incorporate observation vectors (e.g. GalaxyEngine.vector(for: patch))
//    3. Read posteriorVector, materialize it to bytes/values in your domain
//
//  Snap accumulator (Schmitt-trigger model — prevents chattering):
//    A ← A × decayRate              (hysteresis between observations)
//    A ← A + weight × RMS(post−prior)  (observation adds evidence)
//    A > snapThreshold → SWITCH      (commit regime, reset A)
//
//  Parameters:
//    priorStrength   k₀  — confidence in current prior; higher = posterior stays close
//    snapThreshold       — accumulated divergence to snap (0–∞, tuned to your vector scale)
//    decayRate       γ   — accumulator drain between observations (0.5–0.99)

import Foundation
import Combine

// MARK: - VectorRegime

struct VectorRegime: Identifiable {
    let id:         UUID    = UUID()
    var center:     [Double]          // normalized prior vector
    var strength:   Double            // k₀ — prior weight in posterior
    var label:      String?           // optional user / auto label
    var generation: Int               // depth in regime history (0 = initial seed)

    var displayLabel: String {
        label ?? "Regime \(generation)"
    }
}

// MARK: - BayesianVectorSampler

final class BayesianVectorSampler: ObservableObject {

    // MARK: - Configuration

    /// k₀ — prior strength. Higher → posterior resists drifting from prior.
    var priorStrength: Double = 8.0 {
        didSet { recomputePosterior() }
    }

    /// Snap fires when the accumulator exceeds this value.
    var snapThreshold: Double = 1.5

    /// γ — accumulator decay between observations.
    /// 0.95 = sticky / 0.60 = loose
    var decayRate: Double = 0.90

    // MARK: - Observed state

    @Published private(set) var regimeHistory:   [VectorRegime]               = []
    @Published private(set) var currentRegime:   VectorRegime?
    @Published private(set) var posteriorVector: [Double]                      = []
    @Published private(set) var accumulator:     Double                        = 0.0

    private var observations: [(vector: [Double], weight: Double)] = []

    // MARK: - Setup

    func seed(prior: [Double], label: String? = nil) {
        let regime = VectorRegime(center: prior, strength: priorStrength,
                                  label: label ?? "Prior", generation: 0)
        regimeHistory   = [regime]
        currentRegime   = regime
        posteriorVector = prior
        observations    = []
        accumulator     = 0
    }

    // MARK: - Incorporate a vector as evidence

    @discardableResult
    func incorporate(_ vector: [Double], weight: Double = 1.0) -> Bool {
        guard !vector.isEmpty else { return false }

        accumulator *= decayRate

        observations.append((vector: vector, weight: weight))
        recomputePosterior()

        guard let regime = currentRegime else { return false }
        let divergence = rms(posteriorVector, regime.center)
        accumulator += weight * divergence

        if accumulator > snapThreshold {
            snapToNewRegime()
            return true
        }
        return false
    }

    // MARK: - Sorting helpers

    func sorted<T>(_ items: [T], vectorize: (T) -> [Double]) -> [T] {
        guard let regime = currentRegime else { return items }
        return items.sorted {
            rms(vectorize($0), regime.center) < rms(vectorize($1), regime.center)
        }
    }

    func distanceFromPrior(_ vector: [Double]) -> Double {
        guard let regime = currentRegime else { return 0 }
        return rms(vector, regime.center)
    }

    var totalDrift: Double {
        guard let first = regimeHistory.first else { return 0 }
        return rms(posteriorVector, first.center)
    }

    // MARK: - Manual snap

    func manualSnap(label: String? = nil) {
        snapToNewRegime(label: label)
    }

    // MARK: - Rollback

    @discardableResult
    func rollback() -> VectorRegime? {
        guard regimeHistory.count > 1 else { return nil }
        regimeHistory.removeLast()
        let previous = regimeHistory.last!
        currentRegime   = previous
        posteriorVector = previous.center
        observations    = []
        accumulator     = 0
        return previous
    }

    func reset() {
        guard let first = regimeHistory.first else { return }
        regimeHistory   = [first]
        currentRegime   = first
        posteriorVector = first.center
        observations    = []
        accumulator     = 0
    }

    // MARK: - Private

    private func snapToNewRegime(label: String? = nil) {
        guard !posteriorVector.isEmpty else { return }
        let gen = (currentRegime?.generation ?? 0) + 1
        let newRegime = VectorRegime(
            center:     posteriorVector,
            strength:   priorStrength,
            label:      label ?? autoLabel(generation: gen),
            generation: gen
        )
        regimeHistory.append(newRegime)
        currentRegime = newRegime
        observations  = []
        accumulator   = 0
    }

    private func recomputePosterior() {
        guard let regime = currentRegime, !regime.center.isEmpty else { return }
        let dim = regime.center.count
        var sum    = [Double](repeating: 0.0, count: dim)
        var totalW = regime.strength

        for i in 0..<dim { sum[i] = regime.strength * regime.center[i] }

        for obs in observations {
            let w = obs.weight
            totalW += w
            for i in 0..<min(dim, obs.vector.count) { sum[i] += w * obs.vector[i] }
        }

        if totalW > 0 { posteriorVector = sum.map { $0 / totalW } }
    }

    func rms(_ a: [Double], _ b: [Double]) -> Double {
        let n = min(a.count, b.count)
        guard n > 0 else { return 0 }
        let sumSq = (0..<n).reduce(0.0) { acc, i in acc + (a[i] - b[i]) * (a[i] - b[i]) }
        return sqrt(sumSq / Double(n))
    }

    private let autoLabels = ["Variant", "Sub-type", "Branch", "Mode", "Form", "Offshoot"]
    private func autoLabel(generation: Int) -> String {
        autoLabels[(generation - 1) % autoLabels.count] + " \(generation)"
    }
}
