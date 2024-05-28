//
//  SFL3App.swift
//  SFL3
//
//  Created by yanguo sun on 2024/5/28.
//

import SwiftUI

@main
struct SFL3App: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
