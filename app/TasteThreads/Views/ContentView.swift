//
//  ContentView.swift
//  TasteThreads
//
//  Created by Younes Laaroussi on 2025-11-25.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var authService = AuthenticationService.shared
    @EnvironmentObject var dataService: AppDataService
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        Group {
            if authService.isAuthenticated {
                TabView(selection: $appState.selectedTab) {
                    // Tab 1: Map Dashboard (primary)
                    DashboardView(appState: appState)
                        .tabItem {
                            Label("Map", systemImage: "map.fill")
                        }
                        .tag(Tab.map)
                    
                    // Tab 2: Chat
                    ChatView()
                        .tabItem {
                            Label("Chat", systemImage: "message.fill")
                        }
                        .tag(Tab.chat)
                    
                    // Tab 3: Profile (Taste Graph)
                    TasteGraphView()
                        .tabItem {
                            Label("Profile", systemImage: "person.circle.fill")
                        }
                        .tag(Tab.profile)
                }
                .accentColor(.red)
            } else {
                LoginView()
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppDataService.shared)
        .environmentObject(AppState())
}
