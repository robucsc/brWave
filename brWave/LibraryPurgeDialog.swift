//
//  LibraryPurgeDialog.swift
//  brWave
//
//  Confirmation sheet for Library → Purge Library.
//  Optionally exports a SysEx backup, then batch-deletes all patches.
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

    private func performPurge() {
        if makeBackup {
            backupThenPurge()
        } else {
            executePurge()
        }
    }

    @MainActor
    private func backupThenPurge() {
        let req: NSFetchRequest<Patch> = Patch.fetchRequest()
        guard let patches = try? context.fetch(req), !patches.isEmpty else { executePurge(); return }

        let panel = NSSavePanel()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm"
        panel.nameFieldStringValue = "brWave_Backup_\(formatter.string(from: Date())).syx"
        panel.allowedContentTypes = [UTType(filenameExtension: "syx") ?? .data]

        guard panel.runModal() == .OK, let url = panel.url else {
            // User cancelled backup — abort purge
            dismiss()
            return
        }

        var bytes: [UInt8] = []
        for patch in patches.sorted(by: { Int($0.bank) * 100 + Int($0.program) < Int($1.bank) * 100 + Int($1.program) }) {
            guard !patch.rawBytes.isEmpty else { continue }
            bytes.append(contentsOf: WaveSysExParser.dumpToPreset(
                bank: max(Int(patch.bank), 0),
                program: max(Int(patch.program), 0),
                payload: patch.rawBytes
            ))
        }

        if (try? Data(bytes).write(to: url)) != nil {
            executePurge()
        } else {
            dismiss()
        }
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
