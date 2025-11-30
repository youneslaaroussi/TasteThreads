import SwiftUI
import Charts
import Combine
import FirebaseAuth
import PhotosUI

struct TasteGraphView: View {
    @EnvironmentObject var dataService: AppDataService
    @EnvironmentObject var appState: AppState
    @State private var selectedCategory: String?
    @State private var tastePersona: TastePersona?
    @State private var isLoadingPersona = false
    @State private var showSignOutConfirmation = false
    @State private var showImagePicker = false
    @State private var selectedImage: UIImage?
    @State private var isUploadingImage = false
    
    // Warm theme colors
    private let warmAccent = Color(red: 0.76, green: 0.42, blue: 0.32)
    private let warmBackground = Color(red: 0.98, green: 0.96, blue: 0.93)
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                        // User Profile Card
                        UserProfileCard(
                            user: dataService.currentUser,
                            selectedImage: $selectedImage,
                            isUploadingImage: $isUploadingImage,
                            showImagePicker: $showImagePicker,
                            onSaveImage: saveProfileImage
                        )
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        
                        // AI Taste Persona
                        AITastePersonaCard(
                            persona: tastePersona,
                            isLoading: isLoadingPersona,
                            onRefresh: generatePersona
                        )
                        .padding(.horizontal, 16)
                        
                        // Header Stats
                        StatsOverviewSection(
                            aiSuggestionsCount: dataService.aiSuggestedLocations.count,
                            savedPlacesCount: dataService.savedLocations.count,
                            roomsCount: dataService.rooms.count,
                            messagesCount: totalMessagesCount
                        )
                        .padding(.horizontal, 16)
                        
                        // Cuisine Distribution
                        if !cuisineData.isEmpty {
                            CuisineDistributionSection(cuisineData: cuisineData)
                                .padding(.horizontal, 16)
                        }
                        
                        // Price Range Distribution
                        if !priceRangeData.isEmpty {
                            PriceRangeSection(priceData: priceRangeData)
                                .padding(.horizontal, 16)
                        }
                        
                        // Average Ratings
                        RatingsSection(
                            savedAverage: savedPlacesAverageRating,
                            aiAverage: aiSuggestionsAverageRating
                        )
                        .padding(.horizontal, 16)
                        
                        // AI Discoveries
                        if !dataService.aiSuggestedLocations.isEmpty {
                            AIDiscoveriesSection(locations: dataService.aiSuggestedLocations, appState: appState)
                                .padding(.horizontal, 16)
                        }
                        
                        // Saved Places
                        if !dataService.savedLocations.isEmpty {
                            SavedPlacesGridSection(locations: dataService.savedLocations, appState: appState)
                                .padding(.horizontal, 16)
                        }
                        
                        // Sign Out Button
                        Button(action: {
                            showSignOutConfirmation = true
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "rectangle.portrait.and.arrow.right")
                                    .font(.system(size: 16, weight: .medium))
                                Text("Sign Out")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            .foregroundColor(.black.opacity(0.6))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        
                        // Legal Links
                        VStack(spacing: 16) {
                            HStack(spacing: 24) {
                                Link("Privacy Policy", destination: URL(string: "https://raw.githubusercontent.com/youneslaaroussi/TasteThreads/main/PRIVACY.md")!)
                                    .font(.system(size: 14))
                                    .foregroundColor(warmAccent)
                                
                                Text("•")
                                    .foregroundColor(.black.opacity(0.3))
                                
                                Link("Terms of Service", destination: URL(string: "https://raw.githubusercontent.com/youneslaaroussi/TasteThreads/main/TERMS.md")!)
                                    .font(.system(size: 14))
                                    .foregroundColor(warmAccent)
                            }
                            
                            // Powered by Yelp
                            HStack(spacing: 6) {
                                Text("Powered by")
                                    .font(.system(size: 12))
                                    .foregroundColor(.black.opacity(0.4))
                                
                                Image(systemName: "star.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(Color(red: 0.76, green: 0.42, blue: 0.32))
                                
                                Text("Yelp")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(Color(red: 0.76, green: 0.42, blue: 0.32))
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 24)
                        .padding(.bottom, 40)
                    }
                    .padding(.bottom, 20)
                }
            .background(warmBackground)
            .navigationTitle("Profile")
            .refreshable {
                await refreshProfile()
            }
            .onAppear {
                if tastePersona == nil && !dataService.aiSuggestedLocations.isEmpty {
                    generatePersona()
                }
            }
            .confirmationDialog("Sign Out", isPresented: $showSignOutConfirmation, titleVisibility: .visible) {
                Button("Sign Out", role: .destructive) {
                    try? AuthenticationService.shared.signOut()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Are you sure you want to sign out?")
            }
        }
    }
    
    private func saveProfileImage() {
        guard let image = selectedImage else { return }
        
        let maxSize: CGFloat = 400
        let scale = min(maxSize / image.size.width, maxSize / image.size.height, 1.0)
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        image.draw(in: CGRect(origin: .zero, size: newSize))
        let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        guard let imageData = resizedImage?.jpegData(compressionQuality: 0.7) else { return }
        
        isUploadingImage = true
        dataService.updateUserProfile(profileImageData: imageData) { success in
            isUploadingImage = false
            if success {
                selectedImage = nil
            }
        }
    }
    
    private func refreshProfile() async {
        await withCheckedContinuation { continuation in
            dataService.fetchSavedLocations()
            dataService.fetchAIDiscoveries()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.generatePersona()
                continuation.resume()
            }
        }
    }
    
    private func generatePersona() {
        guard !dataService.savedLocations.isEmpty || !dataService.aiSuggestedLocations.isEmpty else {
            return
        }
        
        isLoadingPersona = true
        APIService.shared.generateTastePersona(
            savedPlaces: dataService.savedLocations,
            aiSuggestions: dataService.aiSuggestedLocations
        )
        .sink(receiveCompletion: { completion in
            isLoadingPersona = false
            if case .failure(let error) = completion {
                print("Error generating persona: \(error)")
            }
        }, receiveValue: { persona in
            withAnimation {
                tastePersona = persona
            }
        })
        .store(in: &cancellables)
    }
    
    @State private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Computed Properties
    
    private var totalMessagesCount: Int {
        dataService.rooms.reduce(0) { $0 + $1.messages.count }
    }
    
    private var cuisineData: [CuisineCount] {
        var counts: [String: Int] = [:]
        
        for location in dataService.savedLocations {
            if let categories = location.yelpDetails?.categories {
                for category in categories {
                    counts[category, default: 0] += 1
                }
            }
        }
        
        for location in dataService.aiSuggestedLocations {
            if let categories = location.yelpDetails?.categories {
                for category in categories {
                    counts[category, default: 0] += 1
                }
            }
        }
        
        return counts.map { CuisineCount(name: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
            .prefix(8)
            .map { $0 }
    }
    
    private var priceRangeData: [PriceRangeCount] {
        var counts: [String: Int] = [:]
        
        let allLocations = dataService.savedLocations + dataService.aiSuggestedLocations
        for location in allLocations {
            if let price = location.yelpDetails?.price, !price.isEmpty {
                counts[price, default: 0] += 1
            }
        }
        
        let order = ["$", "$$", "$$$", "$$$$"]
        return order.compactMap { price in
            if let count = counts[price] {
                return PriceRangeCount(range: price, count: count)
            }
            return nil
        }
    }
    
    private var savedPlacesAverageRating: Double {
        guard !dataService.savedLocations.isEmpty else { return 0.0 }
        let total = dataService.savedLocations.reduce(0.0) { $0 + $1.rating }
        return total / Double(dataService.savedLocations.count)
    }
    
    private var aiSuggestionsAverageRating: Double {
        guard !dataService.aiSuggestedLocations.isEmpty else { return 0.0 }
        let total = dataService.aiSuggestedLocations.reduce(0.0) { $0 + $1.rating }
        return total / Double(dataService.aiSuggestedLocations.count)
    }
}

// MARK: - User Profile Card
struct UserProfileCard: View {
    let user: User
    @Binding var selectedImage: UIImage?
    @Binding var isUploadingImage: Bool
    @Binding var showImagePicker: Bool
    let onSaveImage: () -> Void
    
    @State private var showEditSheet = false
    @EnvironmentObject var dataService: AppDataService
    
    private let warmAccent = Color(red: 0.76, green: 0.42, blue: 0.32)
    
    private var firebaseUser: FirebaseAuth.User? {
        Auth.auth().currentUser
    }
    
    private var userEmail: String {
        firebaseUser?.email ?? "Not signed in"
    }
    
    private var memberSince: String {
        if let creationDate = firebaseUser?.metadata.creationDate {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM yyyy"
            return formatter.string(from: creationDate)
        }
        return "Unknown"
    }
    
    var body: some View {
        VStack(spacing: 20) {
            AvatarView(user: user, size: 100)
            
            VStack(spacing: 6) {
                Text(user.name)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.black)
                
                if let bio = user.bio, !bio.isEmpty {
                    Text(bio)
                        .font(.system(size: 15))
                        .foregroundColor(.black.opacity(0.5))
                        .multilineTextAlignment(.center)
                }
            }
            
            // User Preferences
            if let preferences = user.preferences, !preferences.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(preferences, id: \.self) { preference in
                        Text(preference)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(warmAccent)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(warmAccent.opacity(0.1))
                            .clipShape(Capsule())
                    }
                }
            }
            
            HStack(spacing: 6) {
                Image(systemName: "envelope.fill")
                    .font(.system(size: 13))
                    .foregroundColor(.black.opacity(0.4))
                Text(userEmail)
                    .font(.system(size: 14))
                    .foregroundColor(.black.opacity(0.5))
            }
            
            Button(action: { showEditSheet = true }) {
                HStack(spacing: 8) {
                    Image(systemName: "pencil")
                        .font(.system(size: 14, weight: .medium))
                    Text("Edit Profile")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundColor(warmAccent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(warmAccent.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            
            Divider()
            
            HStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Member Since")
                        .font(.system(size: 12))
                        .foregroundColor(.black.opacity(0.4))
                    Text(memberSince)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.black)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("User ID")
                        .font(.system(size: 12))
                        .foregroundColor(.black.opacity(0.4))
                    Text(String(user.id.prefix(8)) + "...")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.black.opacity(0.5))
                }
            }
        }
        .padding(20)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
        .sheet(isPresented: $showEditSheet) {
            ProfileEditSheet(
                user: user,
                selectedImage: $selectedImage,
                isUploadingImage: $isUploadingImage,
                showImagePicker: $showImagePicker,
                onSaveImage: onSaveImage
            )
        }
    }
}

// MARK: - Profile Edit Sheet
struct ProfileEditSheet: View {
    let user: User
    @Binding var selectedImage: UIImage?
    @Binding var isUploadingImage: Bool
    @Binding var showImagePicker: Bool
    let onSaveImage: () -> Void
    
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var dataService: AppDataService
    
    @State private var editedName: String = ""
    @State private var editedBio: String = ""
    @State private var editedPreferences: Set<String> = []
    @State private var isSaving = false
    
    private let warmAccent = Color(red: 0.76, green: 0.42, blue: 0.32)
    private let warmBackground = Color(red: 0.98, green: 0.96, blue: 0.93)
    
    private var originalPreferences: Set<String> {
        Set(user.preferences ?? [])
    }
    
    private var hasChanges: Bool {
        editedName != user.name || 
        editedBio != (user.bio ?? "") || 
        editedPreferences != originalPreferences ||
        selectedImage != nil
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                warmBackground.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 28) {
                        Button(action: { showImagePicker = true }) {
                            ZStack(alignment: .bottomTrailing) {
                                if let selectedImage = selectedImage {
                                    Image(uiImage: selectedImage)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 120, height: 120)
                                        .clipShape(Circle())
                                } else {
                                    AvatarView(user: user, size: 120)
                                }
                                
                                Circle()
                                    .fill(warmAccent)
                                    .frame(width: 36, height: 36)
                                    .overlay(
                                        Image(systemName: "camera.fill")
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundColor(.white)
                                    )
                                    .offset(x: 4, y: 4)
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 20)
                        
                        VStack(spacing: 20) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Name")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.black.opacity(0.5))
                                
                                TextField("Your name", text: $editedName)
                                    .font(.system(size: 16))
                                    .padding(16)
                                    .background(Color.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
                            }
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Bio")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.black.opacity(0.5))
                                
                                TextField("Tell us about yourself...", text: $editedBio, axis: .vertical)
                                    .font(.system(size: 16))
                                    .lineLimit(3...6)
                                    .padding(16)
                                    .background(Color.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
                            }
                        }
                        .padding(.horizontal, 20)
                        
                        // Preferences Section
                        VStack(alignment: .leading, spacing: 20) {
                            Text("Preferences")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.black.opacity(0.5))
                                .padding(.horizontal, 20)
                            
                            EditPreferenceSection(
                                title: "Cuisines",
                                options: OnboardingManager.availableCuisines,
                                selected: $editedPreferences,
                                accent: warmAccent
                            )
                            
                            EditPreferenceSection(
                                title: "Dietary",
                                options: OnboardingManager.availableDietary,
                                selected: $editedPreferences,
                                accent: warmAccent
                            )
                            
                            EditPreferenceSection(
                                title: "Vibe",
                                options: OnboardingManager.availableVibes,
                                selected: $editedPreferences,
                                accent: warmAccent
                            )
                            
                            EditPreferenceSection(
                                title: "Budget",
                                options: OnboardingManager.availablePriceRanges,
                                selected: $editedPreferences,
                                accent: warmAccent
                            )
                        }
                        .padding(.bottom, 40)
                    }
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        selectedImage = nil
                        dismiss()
                    }
                    .foregroundColor(warmAccent)
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: saveChanges) {
                        if isSaving || isUploadingImage {
                            ProgressView()
                                .tint(warmAccent)
                        } else {
                            Text("Save")
                                .font(.system(size: 16, weight: .semibold))
                        }
                    }
                    .foregroundColor(hasChanges ? warmAccent : .black.opacity(0.3))
                    .disabled(!hasChanges || isSaving || isUploadingImage)
                }
            }
        }
        .onAppear {
            editedName = user.name
            editedBio = user.bio ?? ""
            editedPreferences = Set(user.preferences ?? [])
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(selectedImage: $selectedImage)
        }
    }
    
    private func saveChanges() {
        isSaving = true
        
        if selectedImage != nil {
            onSaveImage()
        }
        
        dataService.updateUserProfile(
            name: editedName,
            bio: editedBio,
            preferences: Array(editedPreferences)
        ) { success in
            isSaving = false
            if success {
                selectedImage = nil
                dismiss()
            }
        }
    }
}

// MARK: - Edit Preference Section
struct EditPreferenceSection: View {
    let title: String
    let options: [String]
    @Binding var selected: Set<String>
    let accent: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.black.opacity(0.4))
                .textCase(.uppercase)
                .tracking(0.5)
                .padding(.horizontal, 20)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(options, id: \.self) { option in
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                if selected.contains(option) {
                                    selected.remove(option)
                                } else {
                                    selected.insert(option)
                                }
                            }
                        } label: {
                            Text(option)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(selected.contains(option) ? .white : .black.opacity(0.7))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(selected.contains(option) ? accent : Color.white)
                                .clipShape(Capsule())
                                .shadow(color: .black.opacity(0.04), radius: 3, y: 2)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }
}

// MARK: - Image Picker
struct ImagePicker: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
    @Environment(\.dismiss) var dismiss
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.allowsEditing = true
        picker.sourceType = .photoLibrary
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker
        
        init(_ parent: ImagePicker) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let editedImage = info[.editedImage] as? UIImage {
                parent.selectedImage = editedImage
            } else if let originalImage = info[.originalImage] as? UIImage {
                parent.selectedImage = originalImage
            }
            parent.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

// MARK: - AI Taste Persona Card
struct AITastePersonaCard: View {
    let persona: TastePersona?
    let isLoading: Bool
    let onRefresh: () -> Void
    
    private let warmAccent = Color(red: 0.76, green: 0.42, blue: 0.32)
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "sparkles")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(warmAccent)
                Text("Your Taste Profile")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.black.opacity(0.5))
                Spacer()
                
                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(warmAccent)
                }
                .disabled(isLoading)
            }
            
            if isLoading {
                HStack {
                    Spacer()
                    VStack(spacing: 12) {
                        ProgressView()
                            .tint(warmAccent)
                        Text("Analyzing your taste...")
                            .font(.system(size: 13))
                            .foregroundColor(.black.opacity(0.4))
                    }
                    .padding(.vertical, 24)
                    Spacer()
                }
            } else if let persona = persona {
                VStack(alignment: .leading, spacing: 10) {
                    Text(persona.title)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(warmAccent)
                    
                    Text(persona.bio)
                        .font(.system(size: 15))
                        .foregroundColor(.black.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                        .lineSpacing(4)
                }
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "fork.knife.circle")
                        .font(.system(size: 36))
                        .foregroundColor(warmAccent.opacity(0.4))
                    Text("Start exploring to discover your taste profile!")
                        .font(.system(size: 14))
                        .foregroundColor(.black.opacity(0.5))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            }
        }
        .padding(20)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
    }
}

// MARK: - Stats Overview Section
struct StatsOverviewSection: View {
    let aiSuggestionsCount: Int
    let savedPlacesCount: Int
    let roomsCount: Int
    let messagesCount: Int
    
    private let warmAccent = Color(red: 0.76, green: 0.42, blue: 0.32)
    
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                StatCard(title: "Discoveries", value: "\(aiSuggestionsCount)", icon: "sparkles", color: warmAccent)
                StatCard(title: "Saved", value: "\(savedPlacesCount)", icon: "heart.fill", color: warmAccent)
            }
            HStack(spacing: 12) {
                StatCard(title: "Rooms", value: "\(roomsCount)", icon: "bubble.left.and.bubble.right.fill", color: warmAccent)
                StatCard(title: "Messages", value: "\(messagesCount)", icon: "message.fill", color: warmAccent)
            }
        }
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .medium))
                .foregroundColor(color)
            
            Text(value)
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(.black)
            
            Text(title)
                .font(.system(size: 13))
                .foregroundColor(.black.opacity(0.5))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
    }
}

// MARK: - Cuisine Distribution Section
struct CuisineDistributionSection: View {
    let cuisineData: [CuisineCount]
    
    private let warmAccent = Color(red: 0.76, green: 0.42, blue: 0.32)
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("TOP CUISINES")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.black.opacity(0.4))
            
            if #available(iOS 16.0, *) {
                Chart(cuisineData) { item in
                    BarMark(
                        x: .value("Count", item.count),
                        y: .value("Cuisine", item.name)
                    )
                    .foregroundStyle(warmAccent.gradient)
                    .cornerRadius(4)
                }
                .frame(height: CGFloat(cuisineData.count * 36))
                .padding(16)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
            } else {
                VStack(spacing: 10) {
                    ForEach(cuisineData) { item in
                        HStack {
                            Text(item.name)
                                .font(.system(size: 14))
                                .foregroundColor(.black)
                            Spacer()
                            Text("\(item.count)")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(warmAccent)
                        }
                    }
                }
                .padding(16)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
            }
        }
    }
}

// MARK: - Price Range Section
struct PriceRangeSection: View {
    let priceData: [PriceRangeCount]
    
    private let warmAccent = Color(red: 0.76, green: 0.42, blue: 0.32)
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("PRICE PREFERENCE")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.black.opacity(0.4))
            
            HStack(alignment: .bottom, spacing: 16) {
                ForEach(priceData) { item in
                    VStack(spacing: 8) {
                        Spacer()
                        RoundedRectangle(cornerRadius: 6)
                            .fill(warmAccent)
                            .frame(width: 36, height: CGFloat(item.count * 12 + 20))
                        Text("\(item.count)")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.black)
                        Text(item.range)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.black.opacity(0.5))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 140)
            .padding(16)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
        }
    }
}

// MARK: - Ratings Section
struct RatingsSection: View {
    let savedAverage: Double
    let aiAverage: Double
    
    private let warmAccent = Color(red: 0.76, green: 0.42, blue: 0.32)
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("AVERAGE RATINGS")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.black.opacity(0.4))
            
            HStack(spacing: 12) {
                RatingCard(title: "Saved Places", rating: savedAverage, color: warmAccent)
                RatingCard(title: "AI Picks", rating: aiAverage, color: warmAccent)
            }
        }
    }
}

struct RatingCard: View {
    let title: String
    let rating: Double
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.system(size: 12))
                .foregroundColor(.black.opacity(0.5))
            HStack(spacing: 6) {
                Image(systemName: "star.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.orange)
                Text(String(format: "%.1f", rating))
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.black)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
    }
}

// MARK: - AI Discoveries Section
struct AIDiscoveriesSection: View {
    let locations: [Location]
    let appState: AppState
    
    private let warmAccent = Color(red: 0.76, green: 0.42, blue: 0.32)
    private let warmBackground = Color(red: 0.98, green: 0.96, blue: 0.93)
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(warmAccent)
                Text("DISCOVERIES")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.black.opacity(0.4))
            }
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(locations) { location in
                    Button(action: {
                        appState.navigateToMap(location: location)
                    }) {
                        VStack(alignment: .leading, spacing: 0) {
                            if let imageUrl = location.imageURL {
                                AsyncImage(url: imageUrl) { image in
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                } placeholder: {
                                    Rectangle()
                                        .fill(warmBackground)
                                        .overlay(ProgressView().tint(warmAccent.opacity(0.5)))
                                }
                                .frame(height: 110)
                                .clipped()
                            } else {
                                Rectangle()
                                    .fill(warmBackground)
                                    .frame(height: 110)
                                    .overlay(
                                        Image(systemName: "fork.knife")
                                            .font(.title2)
                                            .foregroundColor(warmAccent.opacity(0.4))
                                    )
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(location.name)
                                    .font(.system(size: 14, weight: .semibold))
                                    .lineLimit(1)
                                    .foregroundColor(.black)
                                
                                HStack(spacing: 4) {
                                    Image(systemName: "star.fill")
                                        .font(.system(size: 10))
                                        .foregroundColor(.orange)
                                    Text(String(format: "%.1f", location.rating))
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.black)
                                }
                                
                                if let aiRemark = location.aiRemark, !aiRemark.isEmpty {
                                    Text(aiRemark)
                                        .font(.system(size: 11))
                                        .foregroundColor(.black.opacity(0.5))
                                        .lineLimit(2)
                                }
                            }
                            .padding(10)
                        }
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
                    }
                }
            }
        }
    }
}

// MARK: - Saved Places Grid Section
struct SavedPlacesGridSection: View {
    let locations: [Location]
    let appState: AppState
    
    private let warmAccent = Color(red: 0.76, green: 0.42, blue: 0.32)
    private let warmBackground = Color(red: 0.98, green: 0.96, blue: 0.93)
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(warmAccent)
                Text("SAVED PLACES")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.black.opacity(0.4))
            }
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(locations) { location in
                    Button(action: {
                        appState.navigateToMap(location: location)
                    }) {
                        VStack(alignment: .leading, spacing: 0) {
                            ZStack(alignment: .topTrailing) {
                                if let imageUrl = location.imageURL {
                                    AsyncImage(url: imageUrl) { image in
                                        image
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                    } placeholder: {
                                        Rectangle()
                                            .fill(warmBackground)
                                            .overlay(ProgressView().tint(warmAccent.opacity(0.5)))
                                    }
                                    .frame(height: 110)
                                    .clipped()
                                } else {
                                    Rectangle()
                                        .fill(warmBackground)
                                        .frame(height: 110)
                                        .overlay(
                                            Image(systemName: "fork.knife")
                                                .font(.title2)
                                                .foregroundColor(warmAccent.opacity(0.4))
                                        )
                                }
                                
                                Image(systemName: "heart.fill")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(5)
                                    .background(warmAccent)
                                    .clipShape(Circle())
                                    .padding(8)
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(location.name)
                                    .font(.system(size: 14, weight: .semibold))
                                    .lineLimit(1)
                                    .foregroundColor(.black)
                                
                                HStack(spacing: 4) {
                                    Image(systemName: "star.fill")
                                        .font(.system(size: 10))
                                        .foregroundColor(.orange)
                                    Text(String(format: "%.1f", location.rating))
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.black)
                                    
                                    if let price = location.yelpDetails?.price {
                                        Text("·")
                                            .foregroundColor(.black.opacity(0.3))
                                        Text(price)
                                            .font(.system(size: 12))
                                            .foregroundColor(.black.opacity(0.5))
                                    }
                                }
                            }
                            .padding(10)
                        }
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
                    }
                }
            }
        }
    }
}

// MARK: - Data Models
struct CuisineCount: Identifiable {
    let id = UUID()
    let name: String
    let count: Int
}

struct PriceRangeCount: Identifiable {
    let id = UUID()
    let range: String
    let count: Int
}

#Preview {
    TasteGraphView()
        .environmentObject(AppDataService.shared)
        .environmentObject(AppState())
}
