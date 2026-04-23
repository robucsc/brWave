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
    private func exportSelection(context: NSManagedObjectContext) -> (patches: [Patch], suggestedName: String)? {
        switch bankEditorState.patchListMode {
        case .library(let libraryID, let bankIndex):
            let req: NSFetchRequest<PatchSet> = PatchSet.fetchRequest()
            req.predicate = NSPredicate(format: "uuid == %@", libraryID as CVarArg)
            req.fetchLimit = 1

            guard let library = try? context.fetch(req).first else { return nil }

            let slots = library.slotsArray
                .filter { slot in
                    guard let patch = slot.patch else { return false }
                    guard patch.isTrashed != true else { return false }
                    if let bankIndex {
                        let minPos = bankIndex * 100
                        let maxPos = minPos + 99
                        return Int(slot.position) >= minPos && Int(slot.position) <= maxPos
                    }
                    return true
                }
                .sorted { Int($0.position) < Int($1.position) }

            let patches = slots.compactMap(\.patch)
            guard !patches.isEmpty else { return nil }

            let baseName = library.name ?? "Library"
            let suggestedName = bankIndex.map { "\(baseName)_Bank\($0)" } ?? baseName
            return (patches, suggestedName)

        case .favorites:
            let req: NSFetchRequest<Patch> = Patch.fetchRequest()
            req.predicate = NSPredicate(format: "isFavorite == YES AND (isTrashed == NO OR isTrashed == nil)")
            guard let patches = try? context.fetch(req), !patches.isEmpty else { return nil }
            let sorted = patches.sorted {
                let a = Int($0.bank) * 100 + Int($0.program)
                let b = Int($1.bank) * 100 + Int($1.program)
                return a < b
            }
            return (sorted, "Favorites")

        case .allPatches:
            let req: NSFetchRequest<Patch> = Patch.fetchRequest()
            req.predicate = NSPredicate(format: "isTrashed == NO OR isTrashed == nil")
            guard let patches = try? context.fetch(req), !patches.isEmpty else { return nil }
            let sorted = patches.sorted {
                let a = Int($0.bank) * 100 + Int($0.program)
                let b = Int($1.bank) * 100 + Int($1.program)
                return a < b
            }
            return (sorted, "All_Patches")

        case .trash:
            return nil
        }
    }

    @MainActor
    private func importPatches(into context: NSManagedObjectContext) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            UTType(filenameExtension: "syx") ?? .data,
            UTType(filenameExtension: "mid") ?? .data,
            UTType(filenameExtension: "midi") ?? .data,
            UTType(filenameExtension: "fxb") ?? .data,
            UTType(filenameExtension: "fxp") ?? .data
        ]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories    = false
        panel.message = "Select Behringer Wave SysEx (.syx), Standard MIDI files with SysEx (.mid/.midi), PPG Wave V8x bank (.syx), Waldorf MicroWave SysEx (.syx), Waldorf FXB bank (.fxb), or Waldorf FXP preset (.fxp) files to import"

        guard panel.runModal() == .OK else { return }

        let syxURLs = panel.urls.filter { $0.pathExtension.lowercased() == "syx" }
        let midiURLs = panel.urls.filter { ["mid", "midi"].contains($0.pathExtension.lowercased()) }
        let fxbURLs = panel.urls.filter { $0.pathExtension.lowercased() == "fxb" }
        let fxpURLs = panel.urls.filter { $0.pathExtension.lowercased() == "fxp" }

        if !syxURLs.isEmpty {
            // Route each .syx file by manufacturer header:
            //   F0 29 01 0D … = PPG Wave V8x hardware bank → V8Importer
            //   F0 3E 00 00 … = Waldorf MicroWave SysEx    → MicrowaveImporter
            //   anything else  = Behringer native SysEx    → WaveSysExImporter
            var behringerSyx: [URL] = []
            var v8Syx: [URL] = []
            var microwaveSyx: [URL] = []
            for url in syxURLs {
                if let data = try? Data(contentsOf: url),
                   data.count >= 4,
                   data[0] == 0xF0, data[1] == 0x29,
                   data[2] == 0x01, data[3] == 0x0D {
                    v8Syx.append(url)
                } else if let data = try? Data(contentsOf: url),
                          data.count >= 5,
                          data[0] == 0xF0, data[1] == 0x3E,
                          data[2] == 0x00, data[3] == 0x00 {
                    microwaveSyx.append(url)
                } else {
                    behringerSyx.append(url)
                }
            }
            if !behringerSyx.isEmpty { WaveSysExImporter.importSyx(urls: behringerSyx, into: context) }
            if !v8Syx.isEmpty        { V8Importer.importV8(urls: v8Syx, into: context) }
            if !microwaveSyx.isEmpty { MicrowaveImporter.importSyx(urls: microwaveSyx, into: context) }
        }
        if !midiURLs.isEmpty {
            for url in midiURLs {
                guard let data = try? Data(contentsOf: url) else { continue }
                let messages = MIDISysExExtractor.extract(from: data)
                guard !messages.isEmpty else { continue }

                var behringerMessages: [[UInt8]] = []
                var v8Messages: [[UInt8]] = []
                var microwaveMessages: [[UInt8]] = []

                for message in messages {
                    if message.count >= 4,
                       message[0] == 0xF0, message[1] == 0x29,
                       message[2] == 0x01, message[3] == 0x0D {
                        v8Messages.append(message)
                    } else if message.count >= 5,
                              message[0] == 0xF0, message[1] == 0x3E,
                              message[2] == 0x00, message[3] == 0x00 {
                        microwaveMessages.append(message)
                    } else {
                        behringerMessages.append(message)
                    }
                }

                let sourceCount = [!behringerMessages.isEmpty, !v8Messages.isEmpty, !microwaveMessages.isEmpty]
                    .filter { $0 }
                    .count
                let baseLibraryName = url.deletingPathExtension().lastPathComponent

                if !behringerMessages.isEmpty {
                    let libraryName = sourceCount > 1 ? "\(baseLibraryName) Wave" : baseLibraryName
                    let bytes = behringerMessages.flatMap { $0 }
                    WaveSysExImporter.importBytes(bytes, libraryName: libraryName, into: context)
                }
                if !v8Messages.isEmpty {
                    let libraryName = sourceCount > 1 ? "\(baseLibraryName) V8" : baseLibraryName
                    V8Importer.importMessages(v8Messages,
                                              libraryName: libraryName,
                                              sourceFileName: url.lastPathComponent,
                                              into: context)
                }
                if !microwaveMessages.isEmpty {
                    let libraryName = sourceCount > 1 ? "\(baseLibraryName) MicroWave" : baseLibraryName
                    MicrowaveImporter.importMessages(microwaveMessages,
                                                     libraryName: libraryName,
                                                     sourceFileName: url.lastPathComponent,
                                                     into: context)
                }
            }
        }
        if !fxbURLs.isEmpty { WaldorfImporter.importFXB(urls: fxbURLs, into: context) }
        if !fxpURLs.isEmpty { WaldorfImporter.importFXP(urls: fxpURLs, into: context) }
    }

    @MainActor
    private func exportAllFXB(context: NSManagedObjectContext) {
        guard let export = exportSelection(context: context) else { return }

        guard let data = WaldorfExporter.exportFXB(patches: export.patches) else { return }

        let panel = NSSavePanel()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm"
        panel.nameFieldStringValue = "\(export.suggestedName)_\(formatter.string(from: Date())).fxb"
        panel.allowedContentTypes = [UTType(filenameExtension: "fxb") ?? .data]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? data.write(to: url)
    }

    @MainActor
    private func exportAllSysEx(context: NSManagedObjectContext) {
        guard let export = exportSelection(context: context) else { return }

        let panel = NSSavePanel()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm"
        panel.nameFieldStringValue = "\(export.suggestedName)_\(formatter.string(from: Date())).syx"
        panel.allowedContentTypes = [UTType(filenameExtension: "syx") ?? .data]
        guard panel.runModal() == .OK, let url = panel.url else { return }

        var bytes: [UInt8] = []
        for patch in export.patches.sorted(by: {
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

                Button("Fetch Synth (All 200 Slots)…") {
                    MIDIController.shared.fetchEntireSynth()
                }

                Button("Send Selection to Synth…") {
                    if let export = exportSelection(context: persistenceController.container.viewContext) {
                        MIDIController.shared.sendBankToSynth(patches: export.patches)
                    }
                }

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

                Button("Export as FXB…") {
                    exportAllFXB(context: persistenceController.container.viewContext)
                }

                Divider()

                Button("Purge Library…") {
                    NotificationCenter.default.post(name: .purgeLibrary, object: nil)
                }
            }
        }
    }
}
