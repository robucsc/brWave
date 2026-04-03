//
//  WaveSysExImporter.swift
//  brWave
//
//  Imports Behringer Wave .syx files into CoreData.
//  Each file becomes a named PatchSet (library) with PatchSlots at
//  bank/program positions (position = bank * 100 + program).
//

import Foundation
import AppKit
import CoreData
import UniformTypeIdentifiers

enum WaveSysExImporter {

    /// Parse selected .syx URLs and save imported patches.
    /// Each file becomes a PatchSet (library) with slots at their bank/program positions.
    @MainActor
    static func importSyx(urls: [URL], into context: NSManagedObjectContext) {
        var totalImported = 0

        for url in urls {
            let parsed = WaveSysExParser.parseSYXFile(at: url)
            guard !parsed.isEmpty else { continue }

            let libraryName = url.deletingPathExtension().lastPathComponent
            let patchSet = PatchSet.findOrCreate(named: libraryName, in: context)
            patchSet.modifiedAt = Date()

            for parsedPatch in parsed {
                let patch = Patch(context: context)
                patch.uuid        = UUID()
                patch.dateCreated = Date()
                patch.importParsed(parsedPatch)

                if let bank = parsedPatch.bank, let prog = parsedPatch.program,
                   bank >= 0, prog >= 0 {
                    let position = bank * 100 + prog
                    PatchSlot.make(position: position, patch: patch, in: patchSet, ctx: context)
                }

                totalImported += 1
            }
        }

        if totalImported > 0 {
            try? context.save()
        }
    }
}
