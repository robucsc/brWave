//
//  LibraryPurgeDialog.swift
//  brWave
//
//  Confirmation sheet for destructive library operations.
//  Always writes a hidden SysEx backup to Application Support/brWave/Backups/
//  before executing, regardless of the user-facing backup toggle.
//

import SwiftUI
import CoreData
import UniformTypeIdentifiers

enum LibraryPurgeMode {
    case purgeAll
    case removeAllDuplicates

    var title: String {
        switch self {
        case .purgeAll:            return "Purge Library"
        case .removeAllDuplicates: return "Remove Duplicates"
        }
    }

    var description: String {
        switch self {
        case .purgeAll:
            return "This will permanently delete all patches from the library."
        case .removeAllDuplicates:
            return "This will permanently delete exact duplicate patches across the entire library, keeping the earliest copy of each."
        }
    }

    var backupToggleLabel: String {
        switch self {
        case .purgeAll:            return "Export a SysEx backup before purging"
        case .removeAllDuplicates: return "Export a SysEx backup before removing duplicates"
        }
    }

    var actionLabel: String {
        switch self {
        case .purgeAll:            return "Purge Library"
        case .removeAllDuplicates: return "Remove Duplicates"
        }
    }

    var backupFileSuffix: String {
        switch self {
        case .purgeAll:            return "purge_backup"
        case .removeAllDuplicates: return "dedup_backup"
        }
    }
}

struct LibraryPurgeDialog: View {
    @Environment(\.managedObjectContext) var context
    @Environment(\.dismiss) var dismiss

    var mode: LibraryPurgeMode = .purgeAll

    @State private var confirmed  = false
    @State private var makeBackup = true

    var body: some View {
        VStack(spacing: 20) {
            Text(mode.title)
                .font(.headline)

            Text(mode.description)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            VStack(alignment: .leading, spacing: 10) {
                Toggle(mode.backupToggleLabel, isOn: $makeBackup)
                Toggle("I understand this cannot be undone", isOn: $confirmed)
            }
            .padding()
            .background(Color.black.opacity(0.1))
            .cornerRadius(8)

            HStack(spacing: 16) {
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Button(mode.actionLabel, role: .destructive) { performAction() }
                    .disabled(!confirmed)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(30)
        .frame(width: 400)
    }

    @MainActor
    private func performAction() {
        let req: NSFetchRequest<Patch> = Patch.fetchRequest()
        guard let patches = try? context.fetch(req) else { dismiss(); return }

        let sorted = patches.sorted {
            Int($0.bank) * 100 + Int($0.program) < Int($1.bank) * 100 + Int($1.program)
        }

        Self.writeSafetyBackup(sorted, suffix: mode.backupFileSuffix)

        if makeBackup && !patches.isEmpty {
            let panel = NSSavePanel()
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd_HH-mm"
            panel.nameFieldStringValue = "brWave_\(mode.backupFileSuffix)_\(formatter.string(from: Date())).syx"
            panel.allowedContentTypes = [UTType(filenameExtension: "syx") ?? .data]
            panel.message = "Save SysEx backup"

            if panel.runModal() == .OK, let url = panel.url {
                try? Data(Self.buildSysExBytes(sorted)).write(to: url)
            }
        }

        switch mode {
        case .purgeAll:            executePurge()
        case .removeAllDuplicates: executeDedup(patches: patches)
        }
    }

    @MainActor
    private func executeDedup(patches: [Patch]) {
        let removed = SimilarityEngine.removeDuplicates(from: patches, in: context)
        try? context.save()
        print("brWave: removed \(removed) exact duplicate\(removed == 1 ? "" : "s") across entire library")
        dismiss()
    }

    /// Write a timestamped .syx file to Application Support/brWave/Backups/.
    /// These backups are never pruned — destructive operations are rare and
    /// every one of these files is worth keeping.
    private static func writeSafetyBackup(_ patches: [Patch], suffix: String) {
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
        let filename = "\(suffix)_\(formatter.string(from: Date())).syx"
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
