//
//  LibraryPurgeDialog.swift
//  brWave
//
//  Confirmation sheet for Library → Purge Library.
//
//  Before any purge a hidden SysEx backup is always written to
//  ~/Library/Application Support/brWave/Backups/ so patches can
//  be recovered even if the user skips the optional user-facing export.
//

import SwiftUI
import CoreData
import UniformTypeIdentifiers

struct LibraryPurgeDialog: View {
    @Environment(\.managedObjectContext) var context
    @Environment(\.dismiss) var dismiss

    @State private var confirmPurge = false
    @State private var makeBackup   = true

    var body: some View {
        VStack(spacing: 20) {
            Text("Purge Library")
                .font(.headline)

            Text("This will permanently delete all patches from the library.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            VStack(alignment: .leading, spacing: 10) {
                Toggle("Export a SysEx backup before purging", isOn: $makeBackup)
                Toggle("I understand this cannot be undone", isOn: $confirmPurge)
            }
            .padding()
            .background(Color.black.opacity(0.1))
            .cornerRadius(8)

            HStack(spacing: 16) {
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Button("Purge Library", role: .destructive) { performPurge() }
                    .disabled(!confirmPurge)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(30)
        .frame(width: 400)
    }

    @MainActor
    private func performPurge() {
        let req: NSFetchRequest<Patch> = Patch.fetchRequest()
        guard let patches = try? context.fetch(req) else { dismiss(); return }

        let sorted = patches.sorted {
            Int($0.bank) * 100 + Int($0.program) < Int($1.bank) * 100 + Int($1.program)
        }

        // Always write a hidden safety backup regardless of user choice.
        Self.writeSafetyBackup(sorted)

        if makeBackup && !patches.isEmpty {
            let panel = NSSavePanel()
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd_HH-mm"
            panel.nameFieldStringValue = "brWave_Backup_\(formatter.string(from: Date())).syx"
            panel.allowedContentTypes = [UTType(filenameExtension: "syx") ?? .data]
            panel.message = "Save SysEx backup"

            // If user cancels the export panel we still proceed — the hidden
            // safety backup already covers them.
            if panel.runModal() == .OK, let url = panel.url {
                let bytes = Self.buildSysExBytes(sorted)
                try? Data(bytes).write(to: url)
            }
        }

        executePurge()
    }

    /// Write a timestamped .syx file to Application Support/brWave/Backups/.
    /// Purge backups are never pruned — purging is a rare deliberate action and
    /// every one of these files is worth keeping.
    private static func writeSafetyBackup(_ patches: [Patch]) {
        guard !patches.isEmpty else { return }

        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask).first else { return }

        let backupDir = appSupport
            .appendingPathComponent("brWave", isDirectory: true)
            .appendingPathComponent("Backups", isDirectory: true)

        try? FileManager.default.createDirectory(at: backupDir,
                                                 withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let filename = "purge_backup_\(formatter.string(from: Date())).syx"
        let dest = backupDir.appendingPathComponent(filename)

        let bytes = buildSysExBytes(patches)
        try? Data(bytes).write(to: dest)

        print("brWave: purge backup written to \(dest.path)")
    }

    private static func buildSysExBytes(_ patches: [Patch]) -> [UInt8] {
        var bytes: [UInt8] = []
        for patch in patches {
            guard !patch.rawBytes.isEmpty else { continue }
            bytes.append(contentsOf: WaveSysExParser.dumpToPreset(
                bank: max(Int(patch.bank), 0),
                program: max(Int(patch.program), 0),
                payload: patch.rawBytes))
        }
        return bytes
    }

    private func executePurge() {
        let fetchRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest(entityName: "Patch")
        let batchDelete = NSBatchDeleteRequest(fetchRequest: fetchRequest)
        batchDelete.resultType = .resultTypeObjectIDs

        if let result = try? context.execute(batchDelete) as? NSBatchDeleteResult,
           let ids = result.result as? [NSManagedObjectID] {
            NSManagedObjectContext.mergeChanges(
                fromRemoteContextSave: [NSDeletedObjectsKey: ids],
                into: [context]
            )
        } else {
            context.reset()
        }
        dismiss()
    }
}
