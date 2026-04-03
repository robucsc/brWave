//
//  UndoService.swift
//  brWave
//
//  Persistent undo/redo for parameter changes.
//  History is saved to Application Support as JSON (up to 256 entries)
//  and survives app relaunches via CoreData objectID URIs.
//  Ported from OBsixer — adapted for WaveParamID / WaveGroup.
//

import Foundation
import SwiftUI
import CoreData

// MARK: - UndoService

@Observable
final class UndoService {
    private weak var undoManager: UndoManager?
    private weak var context: NSManagedObjectContext?

    var lastAction: ParameterChange?
    var recentActions: [ParameterChange] = []
    private(set) var historyIndex: Int = 0
    private(set) var canUndo: Bool = false
    private(set) var canRedo: Bool = false

    private let maxHistoryCount = 256
    private var coalesceParamID: WaveParamID?
    private var coalesceTimer: Timer?
    private var observation: NSObjectProtocol?
    private var undoObservations: [NSObjectProtocol] = []
    private var surgicalUndoParamID: WaveParamID?

    init(undoManager: UndoManager?, context: NSManagedObjectContext? = nil) {
        self.undoManager = undoManager
        self.context     = context
        loadHistory()
        setupObservers()
        refreshUndoRedoState()
    }

    func connect(undoManager: UndoManager?, context: NSManagedObjectContext) {
        self.undoManager = undoManager
        self.context     = context
        setupObservers()
        refreshUndoRedoState()
    }

    deinit {
        observation.map { NotificationCenter.default.removeObserver($0) }
        undoObservations.forEach { NotificationCenter.default.removeObserver($0) }
        coalesceTimer?.invalidate()
    }

    // MARK: - Observers

    private func setupObservers() {
        observation = NotificationCenter.default.addObserver(
            forName: .waveParameterChanged, object: nil, queue: .main
        ) { [weak self] note in self?.handleParameterChange(note) }

        let checkpoints: [Notification.Name] = [
            .NSUndoManagerCheckpoint,
            .NSUndoManagerWillUndoChange,
            .NSUndoManagerWillRedoChange
        ]
        for name in checkpoints {
            let obs = NotificationCenter.default.addObserver(
                forName: name, object: undoManager, queue: .main
            ) { [weak self] _ in self?.refreshUndoRedoState() }
            undoObservations.append(obs)
        }

        let didUndo = NotificationCenter.default.addObserver(
            forName: .NSUndoManagerDidUndoChange, object: undoManager, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            if historyIndex < recentActions.count - 1 {
                historyIndex += 1
                lastAction = recentActions[historyIndex]
            }
            refreshUndoRedoState()
        }
        undoObservations.append(didUndo)

        let didRedo = NotificationCenter.default.addObserver(
            forName: .NSUndoManagerDidRedoChange, object: undoManager, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            if historyIndex > 0 {
                historyIndex -= 1
                lastAction = recentActions[historyIndex]
            }
            refreshUndoRedoState()
        }
        undoObservations.append(didRedo)
    }

    private func refreshUndoRedoState() {
        canUndo = undoManager?.canUndo ?? false
        canRedo = undoManager?.canRedo ?? false
    }

    private func handleParameterChange(_ note: Notification) {
        guard let patch  = note.object as? Patch,
              let id     = note.userInfo?["id"]    as? WaveParamID,
              let oldVal = note.userInfo?["old"]   as? Int,
              let newVal = note.userInfo?["new"]   as? Int else { return }
        guard oldVal != newVal else { return }

        if surgicalUndoParamID == id {
            surgicalUndoParamID = nil
            return
        }

        if coalesceParamID == id, !recentActions.isEmpty {
            recentActions[0].newValue = newVal
            lastAction = recentActions[0]
            saveHistory()
        } else {
            let desc = WaveParameters.byID[id]
            registerChange(
                patchName:     patch.name ?? "Untitled",
                parameterName: desc?.displayName ?? id.rawValue,
                oldValue:      oldVal,
                newValue:      newVal,
                parameterID:   id,
                patch:         patch
            )
            coalesceParamID = id
        }

        coalesceTimer?.invalidate()
        coalesceTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            self?.coalesceParamID = nil
        }
    }

    // MARK: - Registration

    func registerChange(patchName: String, parameterName: String,
                        oldValue: Int, newValue: Int,
                        parameterID: WaveParamID, patch: Patch? = nil) {
        let change = ParameterChange(
            patchName: patchName, parameterName: parameterName,
            oldValue: oldValue, newValue: newValue,
            parameterID: parameterID, timestamp: Date(), patch: patch
        )
        historyIndex = 0
        lastAction   = change
        recentActions.insert(change, at: 0)
        if recentActions.count > maxHistoryCount { recentActions.removeLast() }
        saveHistory()
        refreshUndoRedoState()
    }

    // MARK: - Undo / Redo

    func undo() { undoManager?.undo() }
    func redo() { undoManager?.redo() }

    func selectiveToggle(actionID: UUID) {
        guard let idx = recentActions.firstIndex(where: { $0.id == actionID }) else { return }
        let action = recentActions[idx]
        guard let patch = action.patch else { return }

        let target = action.isReversed ? action.newValue : action.oldValue
        surgicalUndoParamID = action.parameterID
        patch.setValue(target, for: action.parameterID, group: .a)
        surgicalUndoParamID = nil

        recentActions[idx].isReversed.toggle()
        if !recentActions.isEmpty {
            lastAction = recentActions[min(historyIndex, recentActions.count - 1)]
        }
        saveHistory()
        refreshUndoRedoState()
    }

    func clearHistory() {
        recentActions.removeAll()
        lastAction   = nil
        historyIndex = 0
        try? FileManager.default.removeItem(at: historyFileURL)
    }

    // MARK: - Persistence

    private var historyFileURL: URL {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("brWave", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("action_history.json")
    }

    private func saveHistory() {
        guard let data = try? JSONEncoder().encode(recentActions) else { return }
        try? data.write(to: historyFileURL, options: .atomic)
    }

    private func loadHistory() {
        guard let data   = try? Data(contentsOf: historyFileURL),
              var loaded = try? JSONDecoder().decode([ParameterChange].self, from: data) else { return }

        if let ctx = context, let coordinator = ctx.persistentStoreCoordinator {
            for i in loaded.indices {
                guard let uriString = loaded[i].patchObjectID,
                      let uri       = URL(string: uriString),
                      let objectID  = coordinator.managedObjectID(forURIRepresentation: uri),
                      let patch     = try? ctx.existingObject(with: objectID) as? Patch
                else { continue }
                loaded[i].patch = patch
            }
        }

        recentActions = loaded
        lastAction    = recentActions.first
    }
}

// MARK: - ParameterChange

struct ParameterChange: Identifiable, Codable {
    let id:            UUID
    let patchName:     String
    let parameterName: String
    let oldValue:      Int
    var newValue:      Int
    let parameterID:   WaveParamID
    let timestamp:     Date
    var isReversed:    Bool
    var patchObjectID: String?

    var patch: Patch?   // runtime-only, resolved from patchObjectID after load

    enum CodingKeys: String, CodingKey {
        case id, patchName, parameterName, oldValue, newValue
        case parameterID, timestamp, isReversed, patchObjectID
    }

    init(id: UUID = UUID(), patchName: String, parameterName: String,
         oldValue: Int, newValue: Int, parameterID: WaveParamID,
         timestamp: Date, patch: Patch? = nil, isReversed: Bool = false) {
        self.id            = id
        self.patchName     = patchName
        self.parameterName = parameterName
        self.oldValue      = oldValue
        self.newValue      = newValue
        self.parameterID   = parameterID
        self.timestamp     = timestamp
        self.patch         = patch
        self.isReversed    = isReversed
        self.patchObjectID = patch?.objectID.uriRepresentation().absoluteString
    }

    var delta: Int { newValue - oldValue }
}
