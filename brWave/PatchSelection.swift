//
//  PatchSelection.swift
//  brWave
//
//  Owns the currently selected patch and a Bayesian prior for sonic navigation.
//
//  Prior switching (Thomas Bayes):
//  The prior represents "where you are" in sound space. It only updates when
//  you move far enough from it — small hops through nearby patches leave the
//  prior stable, so similarity recommendations stay anchored to your region.
//  A deliberate jump to a different sonic territory shifts the prior to the
//  new location and reorients everything around it.
//
//  Threshold ~0.15 in normalised vector space works well as a default —
//  roughly "moved to a different category of sound". Expose in Settings if
//  users want to tune exploration sensitivity.
//

import Foundation
import Combine
import CoreData

final class PatchSelection: ObservableObject {

    @Published var selectedPatch: Patch? {
        didSet { updatePriorIfNeeded(newPatch: selectedPatch) }
    }

    @Published var selectedIDs: Set<NSManagedObjectID> = []

    /// The Bayesian prior — the sonic anchor for similarity recommendations.
    /// Updated automatically when selectedPatch moves more than
    /// `priorUpdateThreshold` from the current prior in vector space.
    @Published private(set) var priorPatch: Patch?

    /// Distance threshold for prior update. Default 0.15 — roughly "moved to
    /// a meaningfully different sonic region". Lower = more sensitive.
    /// Higher = more stable (only big jumps shift the prior).
    var priorUpdateThreshold: Double {
        get { UserDefaults.standard.double(forKey: "bayesPriorThreshold").nonZeroOr(0.15) }
        set { UserDefaults.standard.set(newValue, forKey: "bayesPriorThreshold") }
    }

    func clearAll() {
        selectedPatch = nil
        selectedIDs   = []
        // Prior intentionally preserved — clearing selection doesn't mean
        // you've left your sonic neighbourhood.
    }

    /// Force-reset the prior to the current selection.
    /// Useful for "Set as Reference" in the inspector.
    func resetPrior() {
        priorPatch = selectedPatch
    }

    // MARK: - Prior update logic

    private func updatePriorIfNeeded(newPatch: Patch?) {
        guard let patch = newPatch else { return }

        guard let prior = priorPatch else {
            // No prior yet — first selection adopts unconditionally.
            priorPatch = patch
            return
        }

        guard prior.objectID != patch.objectID else { return }

        let dist = SimilarityEngine.euclideanDistance(
            v1: SimilarityEngine.patchToVector(patch.values),
            v2: SimilarityEngine.patchToVector(prior.values)
        )

        if dist >= priorUpdateThreshold {
            priorPatch = patch
        }
        // Below threshold: prior holds. You're still in the same
        // neighbourhood — recommendations stay anchored there.
    }
}

private extension Double {
    func nonZeroOr(_ fallback: Double) -> Double {
        self == 0 ? fallback : self
    }
}
