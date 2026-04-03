//
//  UndoManagerBridge.swift
//  brWave
//
//  Hidden background view that wires the window's UndoManager into UndoService
//  once the view hierarchy is live (the UndoManager isn't available at app init time).
//

import SwiftUI
import CoreData

struct UndoManagerBridge: View {
    let undoService: UndoService
    let context: NSManagedObjectContext

    @Environment(\.undoManager) private var undoManager

    var body: some View {
        Color.clear
            .onAppear {
                DispatchQueue.main.async {
                    undoService.connect(undoManager: undoManager, context: context)
                    context.undoManager = undoManager
                }
            }
    }
}
