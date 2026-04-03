//
//  BankEditorState.swift
//  brWave
//

import SwiftUI
import Combine

enum PatchListMode: Equatable {
    case allPatches
    case favorites
    case trash
    case library(UUID, bankIndex: Int?)
}

/// Identifies a specific bank within a named library — used for multi-bank BankMemoryView display.
struct BankSource: Hashable {
    let libraryID: UUID
    let libraryName: String
    let bankIndex: Int
}

final class BankEditorState: ObservableObject {
    @Published var lastTouchedPosition: Int? = nil
    /// UUID of the currently active PatchSet.
    @Published var selectedLibraryID: UUID? = nil
    /// Bank index within the selected library (0 or 1 for Wave's 2-bank layout; nil = show all).
    @Published var selectedBankIndex: Int? = nil
    /// Drives what PatchListView shows.
    @Published var patchListMode: PatchListMode = .allPatches
    /// Multi-selection set for bulk library operations.
    @Published var selectedLibraryIDs: Set<UUID> = []
    /// Multi-bank sources for BankMemoryView display.
    @Published var selectedBankSources: Set<BankSource> = []
    /// Shared clipboard — (relativeOffset, patch) pairs.
    @Published var clipboard: [(relativeOffset: Int, patch: Patch)] = []
}
