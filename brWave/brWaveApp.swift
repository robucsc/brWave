//
//  brWaveApp.swift
//  brWave
//
//  Created by rob on 3/30/26.
//

import SwiftUI
import CoreData

@main
struct brWaveApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
