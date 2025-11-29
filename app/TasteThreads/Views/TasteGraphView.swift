import SwiftUI
import Charts
import Combine
import FirebaseAuth

struct TasteGraphView: View {
    @EnvironmentObject var dataService: AppDataService
    @EnvironmentObject var appState: AppState
    @State private var selectedCategory: String?
    @State private var tastePersona: TastePersona?
    @State private var isLoadingPersona = false
    @State private var showSignOutConfirmation = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // User Profile Card (at top)
                    UserProfileCard(user: dataService.currentUser)
                        .padding(.horizontal)
                        .padding(.top)
                    
                    // AI Taste Persona
                    AITastePersonaCard(
                        persona: tastePersona,
                        isLoading: isLoadingPersona,
                        onRefresh: generatePersona
                    )
                    .padding(.horizontal)
                    
                    // Header Stats
                    StatsOverviewSection(
                        aiSuggestionsCount: dataService.aiSuggestedLocations.count,
                        savedPlacesCount: dataService.savedLocations.count,
                        roomsCount: dataService.rooms.count,
                        messagesCount: totalMessagesCount
                    )
                    .padding(.horizontal)
                    .padding(.top)
                    
                    // Cuisine Distribution
                    if !cuisineData.isEmpty {
                        CuisineDistributionSection(cuisineData: cuisineData)
                            .padding(.horizontal)
                    }
                    
                    // Price Range Distribution
                    if !priceRangeData.isEmpty {
                        PriceRangeSection(priceData: priceRangeData)
                            .padding(.horizontal)
                    }
                    
                    // Average Ratings
                    RatingsSection(
                        savedAverage: savedPlacesAverageRating,
                        aiAverage: aiSuggestionsAverageRating
                    )
                    .padding(.horizontal)
                    
                    // AI Discoveries
                    if !dataService.aiSuggestedLocations.isEmpty {
                        AIDiscoveriesSection(locations: dataService.aiSuggestedLocations, appState: appState)
                            .padding(.horizontal)
                    }
                    
                    // Saved Places
                    if !dataService.savedLocations.isEmpty {
                        SavedPlacesGridSection(locations: dataService.savedLocations, appState: appState)
                            .padding(.horizontal)
                    }
                    
                    // Sign Out Button
                    Button(action: {
                        showSignOutConfirmation = true
                    }) {
                        HStack {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .font(.system(size: 20, weight: .medium))
                            Text("Sign Out")
                                .font(.system(size: 18, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color(red: 0.95, green: 0.3, blue: 0.3))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                }
                .padding(.bottom, 100)
            }
            .navigationTitle("Profile")
            .background(Color(uiColor: .systemGroupedBackground))
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
    
    private func refreshProfile() async {
        // Refresh data from server
        await withCheckedContinuation { continuation in
            dataService.fetchSavedLocations()
            dataService.fetchAIDiscoveries()
            
            // Small delay to allow data to load
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                // Regenerate persona with fresh data
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
            print("Generated persona: \(persona.title) - \(persona.bio)")
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
        
        // Count from saved locations
        for location in dataService.savedLocations {
            if let categories = location.yelpDetails?.categories {
                for category in categories {
                    counts[category, default: 0] += 1
                }
            }
        }
        
        // Count from AI suggestions
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
        
        // All locations
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
        VStack(spacing: 0) {
            // Header with gradient
            ZStack(alignment: .bottomLeading) {
                LinearGradient(
                    colors: [Color(red: 0.4, green: 0.3, blue: 0.9), Color(red: 0.2, green: 0.6, blue: 0.8)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(height: 80)
                
                // Avatar
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 72, height: 72)
                        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
                    
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.4, green: 0.3, blue: 0.9), Color(red: 0.2, green: 0.6, blue: 0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 64, height: 64)
                    
                    Text(String(user.name.prefix(1)).uppercased())
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
                .offset(x: 20, y: 36)
            }
            
            // Content
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(user.name)
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    HStack(spacing: 6) {
                        Image(systemName: "envelope.fill")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text(userEmail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 50)
                
                Divider()
                
                // Member info
                HStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Member Since")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(memberSince)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("User ID")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(String(user.id.prefix(8)) + "...")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)
    }
}

// MARK: - AI Taste Persona Card
struct AITastePersonaCard: View {
    let persona: TastePersona?
    let isLoading: Bool
    let onRefresh: () -> Void
    
    // Refined color palette - deep indigo to teal
    private let accentGradient = LinearGradient(
        colors: [Color(red: 0.4, green: 0.3, blue: 0.9), Color(red: 0.2, green: 0.6, blue: 0.8)],
        startPoint: .leading,
        endPoint: .trailing
    )
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "sparkles")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(accentGradient)
                Text("AI Taste Persona")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
                
                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Color(red: 0.4, green: 0.3, blue: 0.9))
                }
                .disabled(isLoading)
            }
            
            if isLoading {
                HStack {
                    Spacer()
                    VStack(spacing: 12) {
                        ProgressView()
                            .tint(Color(red: 0.4, green: 0.3, blue: 0.9))
                        Text("Analyzing your taste...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 20)
                    Spacer()
                }
            } else if let persona = persona {
                VStack(alignment: .leading, spacing: 12) {
                    Text(persona.title)
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(accentGradient)
                    
                    Text(persona.bio)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "fork.knife.circle")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("Start exploring to discover your taste profile!")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(
                            LinearGradient(
                                colors: [Color(red: 0.4, green: 0.3, blue: 0.9).opacity(0.3), Color(red: 0.2, green: 0.6, blue: 0.8).opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
        .shadow(color: Color(red: 0.4, green: 0.3, blue: 0.9).opacity(0.1), radius: 10, x: 0, y: 5)
    }
}

// MARK: - Stats Overview Section
struct StatsOverviewSection: View {
    let aiSuggestionsCount: Int
    let savedPlacesCount: Int
    let roomsCount: Int
    let messagesCount: Int
    
    private let aiColor = Color(red: 0.4, green: 0.3, blue: 0.9)
    private let savedColor = Color(red: 0.95, green: 0.3, blue: 0.3)
    private let roomsColor = Color(red: 0.2, green: 0.5, blue: 0.9)
    private let messagesColor = Color(red: 0.2, green: 0.7, blue: 0.5)
    
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                StatCard(title: "AI Discoveries", value: "\(aiSuggestionsCount)", icon: "sparkles", color: aiColor)
                StatCard(title: "Saved", value: "\(savedPlacesCount)", icon: "heart.fill", color: savedColor)
            }
            HStack(spacing: 12) {
                StatCard(title: "Rooms", value: "\(roomsCount)", icon: "bubble.left.and.bubble.right.fill", color: roomsColor)
                StatCard(title: "Messages", value: "\(messagesCount)", icon: "message.fill", color: messagesColor)
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
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(color)
                Spacer()
            }
            Text(value)
                .font(.system(size: 36, weight: .bold))
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 5)
    }
}

// MARK: - Cuisine Distribution Section
struct CuisineDistributionSection: View {
    let cuisineData: [CuisineCount]
    
    private let chartColor = Color(red: 0.4, green: 0.3, blue: 0.9)
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Top Cuisines")
                .font(.headline)
                .foregroundStyle(.secondary)
            
            if #available(iOS 16.0, *) {
                Chart(cuisineData) { item in
                    BarMark(
                        x: .value("Count", item.count),
                        y: .value("Cuisine", item.name)
                    )
                    .foregroundStyle(chartColor.gradient)
                }
                .frame(height: CGFloat(cuisineData.count * 40))
                .padding()
                .background(Color(uiColor: .systemBackground))
                .cornerRadius(16)
                .shadow(color: .black.opacity(0.05), radius: 5)
            } else {
                // Fallback for iOS 15
                VStack(spacing: 8) {
                    ForEach(cuisineData) { item in
                        HStack {
                            Text(item.name)
                                .font(.subheadline)
                            Spacer()
                            Text("\(item.count)")
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .foregroundStyle(chartColor)
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical)
                .background(Color(uiColor: .systemBackground))
                .cornerRadius(16)
                .shadow(color: .black.opacity(0.05), radius: 5)
            }
        }
    }
}

// MARK: - Price Range Section
struct PriceRangeSection: View {
    let priceData: [PriceRangeCount]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Price Range Preference")
                .font(.headline)
                .foregroundStyle(.secondary)
            
            HStack(alignment: .bottom, spacing: 12) {
                ForEach(priceData) { item in
                    VStack(spacing: 8) {
                        Spacer()
                        Rectangle()
                            .fill(Color.green.gradient)
                            .frame(width: 40, height: CGFloat(item.count * 10))
                            .cornerRadius(8)
                        Text("\(item.count)")
                            .font(.system(size: 24, weight: .bold))
                        Text(item.range)
                            .font(.title2)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 150)
            .padding()
            .background(Color(uiColor: .systemBackground))
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.05), radius: 5)
        }
    }
}

// MARK: - Ratings Section
struct RatingsSection: View {
    let savedAverage: Double
    let aiAverage: Double
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Average Ratings")
                .font(.headline)
                .foregroundStyle(.secondary)
            
            HStack(spacing: 12) {
                RatingCard(title: "Saved Places", rating: savedAverage, color: Color(red: 0.95, green: 0.3, blue: 0.3))
                RatingCard(title: "AI Picks", rating: aiAverage, color: Color(red: 0.4, green: 0.3, blue: 0.9))
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
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Image(systemName: "star.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(color)
                Text(String(format: "%.1f", rating))
                    .font(.system(size: 32, weight: .bold))
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(uiColor: .systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 5)
    }
}

// MARK: - AI Discoveries Section
struct AIDiscoveriesSection: View {
    let locations: [Location]
    let appState: AppState
    
    private let aiAccent = Color(red: 0.4, green: 0.3, blue: 0.9)
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "sparkles")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(aiAccent)
                Text("AI Discoveries")
                    .font(.headline)
                    .foregroundStyle(.secondary)
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
                                            .fill(Color(uiColor: .systemGray5))
                                            .overlay(
                                                ProgressView()
                                                    .tint(.secondary)
                                            )
                                }
                                .frame(height: 120)
                                .clipped()
                            } else {
                                Rectangle()
                                        .fill(
                                            LinearGradient(
                                                colors: [Color(uiColor: .systemGray5), Color(uiColor: .systemGray6)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                    .frame(height: 120)
                                        .overlay(
                                            Image(systemName: "fork.knife")
                                                .font(.title2)
                                                .foregroundStyle(.secondary)
                                        )
                                }
                                
                                // AI badge
                                HStack(spacing: 2) {
                                    Image(systemName: "sparkles")
                                        .font(.system(size: 8, weight: .bold))
                                    Text("AI")
                                        .font(.system(size: 9, weight: .heavy))
                                }
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(aiAccent)
                                .clipShape(Capsule())
                                .padding(8)
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(location.name)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .lineLimit(1)
                                    .foregroundStyle(.primary)
                                
                                HStack(spacing: 4) {
                                    Image(systemName: "star.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.orange)
                                    Text(String(format: "%.1f", location.rating))
                                        .font(.caption2)
                                        .fontWeight(.medium)
                                        .foregroundStyle(.primary)
                                }
                                
                                if let aiRemark = location.aiRemark, !aiRemark.isEmpty {
                                    Text(aiRemark)
                                        .font(.caption2)
                                        .foregroundStyle(aiAccent)
                                        .lineLimit(2)
                                        .padding(.top, 2)
                                }
                            }
                            .padding(10)
                        }
                        .background(Color(uiColor: .systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 2)
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
    
    private let savedAccent = Color(red: 0.95, green: 0.3, blue: 0.3)
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "heart.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(savedAccent)
                Text("Saved Places")
                    .font(.headline)
                    .foregroundStyle(.secondary)
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
                                            .fill(Color(uiColor: .systemGray5))
                                            .overlay(
                                                ProgressView()
                                                    .tint(.secondary)
                                            )
                                }
                                .frame(height: 120)
                                .clipped()
                            } else {
                                Rectangle()
                                        .fill(
                                            LinearGradient(
                                                colors: [Color(uiColor: .systemGray5), Color(uiColor: .systemGray6)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                    .frame(height: 120)
                                        .overlay(
                                            Image(systemName: "fork.knife")
                                                .font(.title2)
                                                .foregroundStyle(.secondary)
                                        )
                                }
                                
                                // Saved heart badge
                                Image(systemName: "heart.fill")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(6)
                                    .background(savedAccent)
                                    .clipShape(Circle())
                                    .padding(8)
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(location.name)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .lineLimit(1)
                                    .foregroundStyle(.primary)
                                
                                HStack(spacing: 4) {
                                    Image(systemName: "star.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.orange)
                                    Text(String(format: "%.1f", location.rating))
                                        .font(.caption2)
                                        .fontWeight(.medium)
                                        .foregroundStyle(.primary)
                                    
                                    if let price = location.yelpDetails?.price {
                                        Text("·")
                                            .foregroundStyle(.secondary)
                                        Text(price)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .padding(10)
                        }
                        .background(Color(uiColor: .systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 2)
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
