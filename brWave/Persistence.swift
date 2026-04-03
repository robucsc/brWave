//
//  Persistence.swift
//  brWave
//

import CoreData

struct PersistenceController {
    static let shared: PersistenceController = {
        let env = ProcessInfo.processInfo.environment
        if env["XCODE_RUNNING_FOR_PREVIEWS"] == "1" || env["XCODE_RUNNING_FOR_PLAYGROUNDS"] == "1" {
            return PersistenceController.preview
        }
        return PersistenceController()
    }()

    static let preview: PersistenceController = {
        let result = PersistenceController(inMemory: true)
        let viewContext = result.container.viewContext
        do {
            try viewContext.save()
        } catch {
            let nsError = error as NSError
            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        }
        return result
    }()

    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        let localContainer = NSPersistentContainer(name: "brWave")
        container = localContainer

        let storeURL = localContainer.persistentStoreDescriptions.first?.url

        if inMemory {
            localContainer.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        } else {
            let description = localContainer.persistentStoreDescriptions.first
            description?.shouldMigrateStoreAutomatically = true
            description?.shouldInferMappingModelAutomatically = true
        }

        if !inMemory, let url = storeURL, !FileManager.default.fileExists(atPath: url.path) {
            Self.restoreFromBackupIfNeeded(storeURL: url)
        }

        localContainer.loadPersistentStores { _, error in
            if let error = error as NSError? {
                print("CoreData load error: \(error), \(error.userInfo)")
                if !inMemory, let url = storeURL {
                    Self.restoreFromBackupIfNeeded(storeURL: url)
                    localContainer.loadPersistentStores { _, retryError in
                        if let retryError = retryError as NSError? {
                            fatalError("Unresolved error during retry \(retryError), \(retryError.userInfo)")
                        }
                    }
                } else {
                    fatalError("Unresolved error \(error), \(error.userInfo)")
                }
            } else {
                if !inMemory, let url = storeURL {
                    Self.createBackup(storeURL: url)
                }
            }
        }

        localContainer.viewContext.automaticallyMergesChangesFromParent = true
        localContainer.viewContext.undoManager = UndoManager()
        localContainer.viewContext.undoManager?.levelsOfUndo = 50
    }

    // MARK: - Backup & Restore

    private static func createBackup(storeURL: URL) {
        let backupURL = storeURL.appendingPathExtension("backup")
        let walURL    = storeURL.deletingPathExtension().appendingPathExtension("sqlite-wal")
        let shmURL    = storeURL.deletingPathExtension().appendingPathExtension("sqlite-shm")
        let walBackup = backupURL.deletingPathExtension().appendingPathExtension("sqlite-wal.backup")
        let shmBackup = backupURL.deletingPathExtension().appendingPathExtension("sqlite-shm.backup")

        do {
            if FileManager.default.fileExists(atPath: backupURL.path) {
                try FileManager.default.removeItem(at: backupURL)
            }
            try FileManager.default.copyItem(at: storeURL, to: backupURL)
            if FileManager.default.fileExists(atPath: walURL.path) {
                if FileManager.default.fileExists(atPath: walBackup.path) { try FileManager.default.removeItem(at: walBackup) }
                try FileManager.default.copyItem(at: walURL, to: walBackup)
            }
            if FileManager.default.fileExists(atPath: shmURL.path) {
                if FileManager.default.fileExists(atPath: shmBackup.path) { try FileManager.default.removeItem(at: shmBackup) }
                try FileManager.default.copyItem(at: shmURL, to: shmBackup)
            }
        } catch {
            print("CoreData backup failed: \(error)")
        }
    }

    private static func restoreFromBackupIfNeeded(storeURL: URL) {
        let backupURL = storeURL.appendingPathExtension("backup")
        let walBackup = backupURL.deletingPathExtension().appendingPathExtension("sqlite-wal.backup")
        let shmBackup = backupURL.deletingPathExtension().appendingPathExtension("sqlite-shm.backup")
        let walURL    = storeURL.deletingPathExtension().appendingPathExtension("sqlite-wal")
        let shmURL    = storeURL.deletingPathExtension().appendingPathExtension("sqlite-shm")

        guard FileManager.default.fileExists(atPath: backupURL.path) else { return }

        do {
            if FileManager.default.fileExists(atPath: storeURL.path) {
                try FileManager.default.removeItem(at: storeURL)
            }
            try FileManager.default.copyItem(at: backupURL, to: storeURL)
            if FileManager.default.fileExists(atPath: walBackup.path) {
                if FileManager.default.fileExists(atPath: walURL.path) { try FileManager.default.removeItem(at: walURL) }
                try FileManager.default.copyItem(at: walBackup, to: walURL)
            }
            if FileManager.default.fileExists(atPath: shmBackup.path) {
                if FileManager.default.fileExists(atPath: shmURL.path) { try FileManager.default.removeItem(at: shmURL) }
                try FileManager.default.copyItem(at: shmBackup, to: shmURL)
            }
            print("CoreData restored from backup.")
        } catch {
            print("CoreData restore failed: \(error)")
        }
    }
}
