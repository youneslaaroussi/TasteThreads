//
//  OnboardingManager.swift
//  TasteThreads
//
//  Manages onboarding state and stores user data locally before authentication
//

import SwiftUI
import Combine
import FirebaseAuth

class OnboardingManager: ObservableObject {
    static let shared = OnboardingManager()
    
    // MARK: - Published Properties
    @Published var hasCompletedOnboarding: Bool = false
    
    @Published var localUserName: String {
        didSet { UserDefaults.standard.set(localUserName, forKey: "localUserName") }
    }
    
    @Published var localBio: String {
        didSet { UserDefaults.standard.set(localBio, forKey: "localBio") }
    }
    
    @Published var localPreferences: [String] {
        didSet { UserDefaults.standard.set(localPreferences, forKey: "localPreferences") }
    }
    
    @Published var localProfileImageData: Data? {
        didSet {
            if let data = localProfileImageData {
                UserDefaults.standard.set(data, forKey: "localProfileImageData")
            } else {
                UserDefaults.standard.removeObject(forKey: "localProfileImageData")
            }
        }
    }
    
    // Current user ID for tracking onboarding per user
    private var currentUserId: String? {
        didSet {
            updateOnboardingStatus()
        }
    }
    
    // Dev mode: Always show onboarding
    #if DEBUG
    var forceShowOnboarding: Bool = false
    #else
    var forceShowOnboarding: Bool = false
    #endif
    
    var shouldShowOnboarding: Bool {
        forceShowOnboarding || !hasCompletedOnboarding
    }
    
    // MARK: - Init
    private init() {
        self.localUserName = UserDefaults.standard.string(forKey: "localUserName") ?? ""
        self.localBio = UserDefaults.standard.string(forKey: "localBio") ?? ""
        self.localPreferences = UserDefaults.standard.stringArray(forKey: "localPreferences") ?? []
        self.localProfileImageData = UserDefaults.standard.data(forKey: "localProfileImageData")
        
        // Check if there's a current user (will be set by auth service listener)
        // But also check here in case auth service hasn't fired yet
        if let userId = Auth.auth().currentUser?.uid {
            self.currentUserId = userId
            updateOnboardingStatus()
        } else {
            // No user logged in, onboarding should show
            hasCompletedOnboarding = false
        }
    }
    
    // MARK: - User Management
    
    func setCurrentUser(_ userId: String?) {
        self.currentUserId = userId
    }
    
    private func updateOnboardingStatus() {
        guard let userId = currentUserId else {
            hasCompletedOnboarding = false
            return
        }
        
        let key = "hasCompletedOnboarding_\(userId)"
        hasCompletedOnboarding = UserDefaults.standard.bool(forKey: key)
    }
    
    private func saveOnboardingStatus() {
        guard let userId = currentUserId else { return }
        let key = "hasCompletedOnboarding_\(userId)"
        UserDefaults.standard.set(hasCompletedOnboarding, forKey: key)
    }
    
    // MARK: - Methods
    
    func completeOnboarding() {
        hasCompletedOnboarding = true
        forceShowOnboarding = false
        saveOnboardingStatus()
    }
    
    func resetOnboarding() {
        // Clear onboarding status for current user
        if let userId = currentUserId {
            let key = "hasCompletedOnboarding_\(userId)"
            UserDefaults.standard.removeObject(forKey: key)
        }
        
        hasCompletedOnboarding = false
        localUserName = ""
        localBio = ""
        localPreferences = []
        localProfileImageData = nil
    }
    
    /// Sync local onboarding data to the server after authentication
    func syncToServer(dataService: AppDataService, completion: ((Bool) -> Void)? = nil) {
        guard !localUserName.isEmpty || !localBio.isEmpty || !localPreferences.isEmpty || localProfileImageData != nil else {
            completion?(true)
            return
        }
        
        dataService.updateUserProfile(
            name: localUserName.isEmpty ? nil : localUserName,
            bio: localBio.isEmpty ? nil : localBio,
            preferences: localPreferences.isEmpty ? nil : localPreferences,
            profileImageData: localProfileImageData
        ) { success in
            if success {
                // Clear local data after successful sync
                self.localUserName = ""
                self.localBio = ""
                self.localPreferences = []
                self.localProfileImageData = nil
            }
            completion?(success)
        }
    }
}

// MARK: - Available Preferences
extension OnboardingManager {
    static let availableCuisines = [
        "🍕 Italian", "🍣 Japanese", "🌮 Mexican", "🍜 Thai", "🥘 Indian",
        "🍔 American", "🥗 Mediterranean", "🍲 Chinese", "🥐 French", "🌶️ Korean"
    ]
    
    static let availableDietary = [
        "🥬 Vegetarian", "🌱 Vegan", "🚫🌾 Gluten-Free", "🥜 Nut-Free",
        "🐟 Pescatarian", "🥩 Keto", "🍖 Paleo", "🐄 Dairy-Free"
    ]
    
    static let availableVibes = [
        "🌳 Outdoor Seating", "🎵 Live Music", "🍷 Wine Bar", "🎉 Lively",
        "🤫 Quiet & Intimate", "👨‍👩‍👧‍👦 Family-Friendly", "💼 Business Casual",
        "🌃 Late Night", "☀️ Brunch Spot", "🍻 Sports Bar"
    ]
    
    static let availablePriceRanges = [
        "💵 Budget-Friendly", "💵💵 Moderate", "💵💵💵 Upscale", "💵💵💵💵 Fine Dining"
    ]
}

