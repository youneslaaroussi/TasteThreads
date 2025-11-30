//
//  TasteThreadsApp.swift
//  TasteThreads
//
//  Created by Younes Laaroussi on 2025-11-25.
//

import SwiftUI
import FirebaseCore

@main
struct TasteThreadsApp: App {
    @StateObject private var dataService = AppDataService.shared
    @StateObject private var appState = AppState()
    
    init() {
        FirebaseApp.configure()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(dataService)
                .environmentObject(appState)
                .preferredColorScheme(.light)
        }
    }
}
