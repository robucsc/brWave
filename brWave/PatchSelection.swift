//
//  PatchSelection.swift
//  brWave
//

import Foundation
import Combine
import CoreData

final class PatchSelection: ObservableObject {
    @Published var selectedPatch: Patch?
    @Published var selectedIDs: Set<NSManagedObjectID> = []

    func clearAll() {
        selectedPatch = nil
        selectedIDs   = []
    }
}
