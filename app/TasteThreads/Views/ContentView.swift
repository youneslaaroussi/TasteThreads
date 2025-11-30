//
//  ContentView.swift
//  TasteThreads
//
//  Created by Younes Laaroussi on 2025-11-25.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var authService = AuthenticationService.shared
    @StateObject private var onboardingManager = OnboardingManager.shared
    @EnvironmentObject var dataService: AppDataService
    @EnvironmentObject var appState: AppState
    
    @State private var showOnboarding = false
    @State private var showLoginSheet = false
    
    var body: some View {
        Group {
            if showOnboarding {
                OnboardingView {
                    withAnimation(.spring(response: 0.5)) {
                        showOnboarding = false
                    }
                }
                .transition(.opacity)
            } else {
                mainContent
            }
        }
        .onAppear {
            // Check if we should show onboarding
            checkOnboardingStatus()
        }
        .onChange(of: authService.isAuthenticated) { _, isAuthenticated in
            if isAuthenticated {
                // Sync onboarding data to server after authentication
                onboardingManager.syncToServer(dataService: dataService)
            }
            // Check onboarding status when auth state changes (e.g., after sign out)
            checkOnboardingStatus()
        }
        .onChange(of: onboardingManager.shouldShowOnboarding) { _, shouldShow in
            // Update onboarding display when status changes
            showOnboarding = shouldShow
        }
        .sheet(isPresented: $showLoginSheet) {
            LoginView()
        }
    }
    
    private func checkOnboardingStatus() {
        showOnboarding = onboardingManager.shouldShowOnboarding
    }
    
    @ViewBuilder
    private var mainContent: some View {
        TabView(selection: $appState.selectedTab) {
            // Tab 1: Map Dashboard (primary) - Always accessible
            DashboardView(appState: appState)
                .tabItem {
                    Label("Map", systemImage: "map.fill")
                }
                .tag(Tab.map)
            
            // Tab 2: Chat - Requires auth
            chatTab
                .tabItem {
                    Label("Chat", systemImage: "message.fill")
                }
                .tag(Tab.chat)
            
            // Tab 3: Profile (Taste Graph) - Requires auth
            profileTab
                .tabItem {
                    Label("Profile", systemImage: "person.circle.fill")
                }
                .tag(Tab.profile)
        }
        .tint(Color(red: 0.76, green: 0.42, blue: 0.32))
    }
    
    @ViewBuilder
    private var chatTab: some View {
        if authService.isAuthenticated {
            ChatView()
        } else {
            ChatSignInPromptView {
                showLoginSheet = true
            }
        }
    }
    
    @ViewBuilder
    private var profileTab: some View {
        if authService.isAuthenticated {
            TasteGraphView()
        } else {
            ProfileSignInPromptView {
                showLoginSheet = true
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppDataService.shared)
        .environmentObject(AppState())
}
