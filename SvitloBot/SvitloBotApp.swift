//
//  SvitloBotApp.swift
//  SvitloBot
//
//  Created by Alexander Tartmin on 31.08.2024.
//

import SwiftUI

@main
struct SvitloBotApp: App {
    let persistenceController = PersistenceController.shared
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .onAppear {
                    UIApplication.shared.isIdleTimerDisabled = true
                }
                .onDisappear {
                    UIApplication.shared.isIdleTimerDisabled = false
                }
        }
    }
}
