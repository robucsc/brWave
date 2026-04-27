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
        let skipInits = UserDefaults.standard.bool(forKey: "importSkipInitPatches")
        let dedup     = UserDefaults.standard.bool(forKey: "importDeduplicateOnImport")
        var newPatches: [Patch] = []

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

                if skipInits && SimilarityEngine.isInitPatch(patch) {
                    context.delete(patch)
                    continue
                }

                if let bank = parsedPatch.bank, let prog = parsedPatch.program,
                   bank >= 0, prog >= 0 {
                    let position = bank * 100 + prog
                    PatchSlot.make(position: position, patch: patch, in: patchSet, ctx: context)
                }

                newPatches.append(patch)
            }
        }

        guard !newPatches.isEmpty else { return }
        if dedup { SimilarityEngine.removeDuplicates(from: newPatches, in: context) }
        try? context.save()
    }

    /// Import raw Behringer SysEx bytes that may contain one or more concatenated messages.
    @MainActor
    static func importBytes(_ bytes: [UInt8], libraryName: String, into context: NSManagedObjectContext) {
        let skipInits = UserDefaults.standard.bool(forKey: "importSkipInitPatches")
        let dedup     = UserDefaults.standard.bool(forKey: "importDeduplicateOnImport")
        let parsed    = WaveSysExParser.parseSYXData(bytes)
        guard !parsed.isEmpty else { return }

        let patchSet = PatchSet.findOrCreate(named: libraryName, in: context)
        patchSet.modifiedAt = Date()
        var newPatches: [Patch] = []

        for parsedPatch in parsed {
            let patch = Patch(context: context)
            patch.uuid        = UUID()
            patch.dateCreated = Date()
            patch.importParsed(parsedPatch)

            if skipInits && SimilarityEngine.isInitPatch(patch) {
                context.delete(patch)
                continue
            }

            if let bank = parsedPatch.bank, let prog = parsedPatch.program,
               bank >= 0, prog >= 0 {
                let position = bank * 100 + prog
                PatchSlot.make(position: position, patch: patch, in: patchSet, ctx: context)
            }

            newPatches.append(patch)
        }

        if dedup { SimilarityEngine.removeDuplicates(from: newPatches, in: context) }
        try? context.save()
        FactoryPatchNames.buildVectorRegistry(from: context)
    }
}
