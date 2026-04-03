//
//  brWaveApp.swift
//  brWave
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

@main
struct brWaveApp: App {
    let persistenceController = PersistenceController.shared

    @StateObject private var bankEditorState = BankEditorState()
    @StateObject private var patchSelection  = PatchSelection()

    // UndoService needs the window's UndoManager — bridged via UndoManagerBridge
    @State private var undoService = UndoService(undoManager: nil)

    @MainActor
    private func importPatches(into context: NSManagedObjectContext) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            UTType(filenameExtension: "syx") ?? .data,
            UTType(filenameExtension: "fxb") ?? .data
        ]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories    = false
        panel.message = "Select Behringer Wave SysEx (.syx) or Waldorf FXB (.fxb) files to import"

        guard panel.runModal() == .OK else { return }

        let syxURLs = panel.urls.filter { $0.pathExtension.lowercased() == "syx" }
        let fxbURLs = panel.urls.filter { $0.pathExtension.lowercased() == "fxb" }

        if !syxURLs.isEmpty { WaveSysExImporter.importSyx(urls: syxURLs, into: context) }
        if !fxbURLs.isEmpty { WaldorfImporter.importFXB(urls: fxbURLs, into: context) }
    }

    @MainActor
    private func exportAllSysEx(context: NSManagedObjectContext) {
        let req: NSFetchRequest<Patch> = Patch.fetchRequest()
        req.predicate = NSPredicate(format: "isTrashed == NO OR isTrashed == nil")
        guard let patches = try? context.fetch(req), !patches.isEmpty else { return }

        let panel = NSSavePanel()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm"
        panel.nameFieldStringValue = "brWave_Export_\(formatter.string(from: Date())).syx"
        panel.allowedContentTypes = [UTType(filenameExtension: "syx") ?? .data]
        guard panel.runModal() == .OK, let url = panel.url else { return }

        var bytes: [UInt8] = []
        for patch in patches.sorted(by: {
            let a = Int($0.bank) * 100 + Int($0.program)
            let b = Int($1.bank) * 100 + Int($1.program)
            return a < b
        }) {
            guard !patch.rawBytes.isEmpty else { continue }
            let bank = max(Int(patch.bank), 0)
            let prog = max(Int(patch.program), 0)
            bytes.append(contentsOf: WaveSysExParser.dumpToPreset(bank: bank, program: prog, payload: patch.rawBytes))
        }

        try? Data(bytes).write(to: url)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    DispatchQueue.main.async {
                        MIDIController.shared.wire(to: patchSelection)
                    }
                }
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environmentObject(bankEditorState)
                .environmentObject(patchSelection)
                .environment(undoService)
                .background(UndoManagerBridge(undoService: undoService,
                                              context: persistenceController.container.viewContext))
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Toggle Inspector") {
                    NotificationCenter.default.post(name: InspectorBus.toggle, object: nil)
                }
                .keyboardShortcut("i", modifiers: .command)
            }

            CommandGroup(after: .undoRedo) {
                Divider()
                Button("Clear Action History") { undoService.clearHistory() }
            }

            CommandGroup(replacing: .pasteboard) {
                Button("Copy") {
                    NotificationCenter.default.post(name: Notification.Name("PerformCopy"), object: nil)
                }
                .keyboardShortcut("c", modifiers: .command)
                Button("Paste") {
                    NotificationCenter.default.post(name: Notification.Name("PerformPaste"), object: nil)
                }
                .keyboardShortcut("v", modifiers: .command)
                Button("Clear") {
                    NotificationCenter.default.post(name: Notification.Name("PerformClear"), object: nil)
                }
                .keyboardShortcut(.delete, modifiers: [])
                Divider()
                Button("Duplicate") {
                    NotificationCenter.default.post(name: Notification.Name("PerformDuplicate"), object: nil)
                }
                .keyboardShortcut("d", modifiers: .command)
            }

            CommandGroup(replacing: .importExport) { }

            CommandMenu("Library") {
                Button("Import…") {
                    importPatches(into: persistenceController.container.viewContext)
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])

                Button("Apply Names from Clipboard…") {
                    NotificationCenter.default.post(name: .applyNamesFromClipboard, object: nil)
                }

                Divider()

                Button("Empty Trash…") {
                    let ctx = persistenceController.container.viewContext
                    let req: NSFetchRequest<Patch> = Patch.fetchRequest()
                    req.predicate = NSPredicate(format: "isTrashed == YES")
                    if let trashed = try? ctx.fetch(req) {
                        trashed.forEach { ctx.delete($0) }
                        try? ctx.save()
                    }
                }

                Divider()

                Button("New Library from Selection…") {
                    let ctx = persistenceController.container.viewContext
                    guard let patch = patchSelection.selectedPatch else { return }
                    let formatter = DateFormatter()
                    formatter.dateFormat = "yyyy-MM-dd HH:mm"
                    let lib = PatchSet.create(named: "Selection \(formatter.string(from: Date()))", in: ctx)
                    let pos = Int(patch.bank) * 100 + Int(patch.program)
                    PatchSlot.make(position: max(pos, 0), patch: patch, in: lib, ctx: ctx)
                    try? ctx.save()
                }
                .disabled(patchSelection.selectedPatch == nil)

                Divider()

                Button("Rebuild Galaxy…") {
                    GalaxyEngine.shared.updateAll(in: persistenceController.container.viewContext)
                }
                .keyboardShortcut("r", modifiers: [.command, .option])

                Divider()

                Button("Export SysEx…") {
                    exportAllSysEx(context: persistenceController.container.viewContext)
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])

                Divider()

                Button("Purge Library…") {
                    NotificationCenter.default.post(name: .purgeLibrary, object: nil)
                }
            }
        }
    }
}
