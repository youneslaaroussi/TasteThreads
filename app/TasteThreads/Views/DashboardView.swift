import SwiftUI
import MapKit

struct DashboardView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var dataService: AppDataService
    @StateObject private var viewModel: DashboardViewModel
    @StateObject private var locationManager = LocationManager()
    @State private var searchText = ""
    @State private var isSearching = false
    @State private var hasInitiallyFocusedOnLocation = false
    @State private var hasSearched = false // Track if a search has actually been initiated
    @FocusState private var isFocused: Bool
    
    init(appState: AppState) {
        _viewModel = StateObject(wrappedValue: DashboardViewModel(appState: appState))
    }
    
    var body: some View {
        ZStack {
            // 1. Full Screen Map with both itinerary items and search results
            Map(coordinateRegion: $viewModel.region, 
                showsUserLocation: true,
                annotationItems: combinedAnnotations) { item in
                MapAnnotation(coordinate: CLLocationCoordinate2D(latitude: item.latitude, longitude: item.longitude)) {
                    Button(action: {
                        if let itineraryItem = item.itineraryItem {
                            viewModel.selectItem(itineraryItem)
                        } else if let business = item.business {
                            viewModel.selectBusiness(business)
                        } else if let savedLocation = item.savedLocation {
                            // Create a preview item for saved location
                            let previewItem = ItineraryItem(
                                id: UUID().uuidString,
                                type: .main,
                                location: savedLocation,
                                time: nil,
                                notes: nil,
                                votes: 0,
                                isAISuggestion: false
                            )
                            viewModel.selectItem(previewItem)
                        }
                    }) {
                        FancyMapMarker(
                            type: markerType(for: item),
                            icon: markerIcon(for: item),
                            isAI: false,
                            name: item.business?.name ?? item.itineraryItem?.location.name ?? item.savedLocation?.name
                        )
                    }
                }
            }
            .edgesIgnoringSafeArea(.all)
            .onAppear {
                locationManager.requestPermission()
                // If we already have location permission, center on it
                if let location = locationManager.location, !hasInitiallyFocusedOnLocation {
                    centerOnLocation(location)
                }
            }
            .onChange(of: locationManager.location) { newLocation in
                // Auto-focus on user's location when it first becomes available
                if let location = newLocation, !hasInitiallyFocusedOnLocation {
                    centerOnLocation(location)
                }
            }
            .onChange(of: locationManager.authorizationStatus) { status in
                // When permission is granted, start location updates
                if status == .authorizedWhenInUse || status == .authorizedAlways {
                    locationManager.startUpdating()
                }
            }
            
            // 2. Search Bar & Results Overlay
            VStack(spacing: 0) {
                // Search Bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.secondary)
                    
                    TextField("Search for restaurants, cuisines...", text: $searchText)
                        .font(.subheadline)
                        .focused($isFocused)
                        .onTapGesture {
                            withAnimation {
                                isSearching = true
                            }
                        }
                        .onSubmit {
                            viewModel.searchBusinesses(query: searchText)
                        }
                    
                    if isSearching {
                        Button("Cancel") {
                            withAnimation {
                                isSearching = false
                                searchText = ""
                                isFocused = false
                                hasSearched = false
                                viewModel.searchResults = []
                            }
                        }
                        .font(.subheadline)
                        .foregroundStyle(.blue)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .padding()
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
                .padding(.horizontal)
                .padding(.top, 8)
                
                // Results Overlay - Show search results instead of itinerary
                if isSearching && !searchText.isEmpty && hasSearched {
                    SearchResultsList(
                        searchText: searchText,
                        results: viewModel.searchResults,
                        isLoading: viewModel.isSearching,
                        onSelect: { business in
                            viewModel.selectBusiness(business)
                            withAnimation {
                                isSearching = false
                                isFocused = false
                                hasSearched = false
                            }
                        }
                    )
                    .transition(.opacity)
                    .padding(.top, 8)
                }
                
                Spacer()
            }
            
            // My Location Button (hidden when keyboard is open)
            if !isFocused {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button(action: {
                            if let location = locationManager.location {
                                withAnimation {
                                    viewModel.region = MKCoordinateRegion(
                                        center: location.coordinate,
                                        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                                    )
                                }
                            } else {
                                locationManager.requestPermission()
                            }
                        }) {
                            Image(systemName: "location.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(.blue)
                                .frame(width: 44, height: 44)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                                .shadow(color: .black.opacity(0.1), radius: 5)
                        }
                        .padding(.trailing)
                        .padding(.bottom, 100)
                    }
                }
                .transition(.opacity)
            }
            

            
        }
        .sheet(item: $viewModel.selectedItem) { item in
            LocationDetailView(item: item)
                .presentationDetents([.medium, .large])
        }
        .onChange(of: isFocused) { focused in
            if focused {
                withAnimation {
                    isSearching = true
                }
            }
        }
        .onChange(of: searchText) { oldValue, newValue in
            if !newValue.isEmpty {
                // Debounce search - don't set hasSearched until search actually starts
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if searchText == newValue {
                        hasSearched = true
                        viewModel.searchBusinesses(query: newValue)
                    }
                }
            } else {
                viewModel.searchResults = []
                hasSearched = false
            }
        }
    }
    
    // Helper function to center map on user location
    private func centerOnLocation(_ location: CLLocation) {
        withAnimation(.easeInOut(duration: 0.5)) {
            viewModel.region = MKCoordinateRegion(
                center: location.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
            )
        }
        hasInitiallyFocusedOnLocation = true
    }
    
    // Helper functions for map markers
    private func markerType(for item: MapAnnotationItem) -> FancyMapMarker.MarkerType {
        if item.savedLocation != nil {
            return .saved
        } else if item.business != nil {
            return .search
        } else if item.itineraryItem?.isAISuggestion == true {
            return .aiSuggestion
        } else {
            return .itinerary
        }
    }
    
    private func markerIcon(for item: MapAnnotationItem) -> String {
        if item.savedLocation != nil {
            return "heart.fill"
        } else if let itineraryItem = item.itineraryItem {
            switch itineraryItem.type {
            case .appetizer: return "leaf.fill"
            case .main: return "fork.knife"
            case .dessert: return "birthday.cake.fill"
            case .drinks: return "wineglass.fill"
            case .activity: return "figure.walk"
            }
        }
        return "fork.knife"
    }
    
    // Combine itinerary items and search results into a single array for map annotations
    private var combinedAnnotations: [MapAnnotationItem] {
        var items: [MapAnnotationItem] = []
        var addedLocationIds = Set<String>()
        
        // First, add saved locations (they get priority to show with heart icon)
        for savedLocation in dataService.savedLocations {
            let locationId = savedLocation.yelpId ?? "\(savedLocation.latitude)_\(savedLocation.longitude)"
            addedLocationIds.insert(locationId)
            items.append(MapAnnotationItem(
                latitude: savedLocation.latitude,
                longitude: savedLocation.longitude,
                itineraryItem: nil,
                business: nil,
                savedLocation: savedLocation
            ))
        }
        
        // Add itinerary items (only if not already shown as saved location)
        for item in viewModel.itineraryItems {
            let locationId = item.location.yelpId ?? "\(item.location.latitude)_\(item.location.longitude)"
            if !addedLocationIds.contains(locationId) {
                addedLocationIds.insert(locationId)
                items.append(MapAnnotationItem(
                    latitude: item.location.latitude,
                    longitude: item.location.longitude,
                    itineraryItem: item,
                    business: nil
                ))
            }
        }
        
        // Add AI-suggested businesses (not yet in itinerary or saved)
        for aiItem in viewModel.aiSuggestedItems {
            let locationId = aiItem.location.yelpId ?? "\(aiItem.location.latitude)_\(aiItem.location.longitude)"
            if !addedLocationIds.contains(locationId) {
                addedLocationIds.insert(locationId)
                items.append(MapAnnotationItem(
                    latitude: aiItem.location.latitude,
                    longitude: aiItem.location.longitude,
                    itineraryItem: aiItem,
                    business: nil
                ))
            }
        }
        
        // Add preview item (from chat navigation) if not already shown
        if let previewItem = viewModel.previewItem {
            let locationId = previewItem.location.yelpId ?? "\(previewItem.location.latitude)_\(previewItem.location.longitude)"
            if !addedLocationIds.contains(locationId) {
                addedLocationIds.insert(locationId)
                items.append(MapAnnotationItem(
                    latitude: previewItem.location.latitude,
                    longitude: previewItem.location.longitude,
                    itineraryItem: previewItem,
                    business: nil
                ))
            }
        }
        
        // Add search results
        for business in viewModel.searchResults {
            let locationId = business.id
            if !addedLocationIds.contains(locationId),
               let coords = business.coordinates {
                addedLocationIds.insert(locationId)
                items.append(MapAnnotationItem(
                    latitude: coords.latitude,
                    longitude: coords.longitude,
                    itineraryItem: nil,
                    business: business
                ))
            }
        }
        
        return items
    }
}

// Helper struct for map annotations
struct MapAnnotationItem: Identifiable {
    let id: String
    let latitude: Double
    let longitude: Double
    let itineraryItem: ItineraryItem?
    let business: YelpBusiness?
    let savedLocation: Location?
    
    init(latitude: Double, longitude: Double, itineraryItem: ItineraryItem?, business: YelpBusiness?, savedLocation: Location? = nil) {
        self.latitude = latitude
        self.longitude = longitude
        self.itineraryItem = itineraryItem
        self.business = business
        self.savedLocation = savedLocation
        
        // Create stable ID based on actual item/business/saved location ID
        if let item = itineraryItem {
            self.id = "itinerary_\(item.id)"
        } else if let biz = business {
            self.id = "business_\(biz.id)"
        } else if let saved = savedLocation {
            self.id = "saved_\(saved.yelpId ?? saved.id)"
        } else {
            self.id = UUID().uuidString
        }
    }
}

// Search result pin
struct SearchResultPin: View {
    let business: YelpBusiness
    
    private let warmAccent = Color(red: 0.76, green: 0.42, blue: 0.32)
    
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(warmAccent)
                    .shadow(radius: 5)
            }
        }
    }
}

// Search results list
struct SearchResultsList: View {
    let searchText: String
    let results: [YelpBusiness]
    let isLoading: Bool
    let onSelect: (YelpBusiness) -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                // Skeleton loader
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(0..<5) { _ in
                            SearchResultSkeleton()
                        }
                    }
                    .padding()
                }
                .frame(maxHeight: 400)
            } else if results.isEmpty {
                Text("No results for \"\(searchText)\"")
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(results) { business in
                            Button(action: { onSelect(business) }) {
                                HStack(spacing: 14) {
                                    // Image
                                    AsyncImage(url: URL(string: business.image_url ?? "")) { image in
                                        image
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                    } placeholder: {
                                        ZStack {
                                            Color(uiColor: .systemGray5)
                                            Image(systemName: "fork.knife")
                                                .font(.title3)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .frame(width: 70, height: 70)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color.gray.opacity(0.1), lineWidth: 1)
                                    )
                                    
                                    // Content
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(business.name)
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                        
                                        // Rating and reviews
                                        HStack(spacing: 4) {
                                            HStack(spacing: 2) {
                                                Image(systemName: "star.fill")
                                                    .font(.system(size: 12))
                                                    .foregroundStyle(.orange)
                                                Text(String(format: "%.1f", business.rating))
                                                    .font(.system(size: 13, weight: .medium))
                                                    .foregroundStyle(.primary)
                                            }
                                            
                                            Text("·")
                                                .foregroundStyle(.secondary)
                                                .font(.system(size: 13))
                                            
                                            Text("\(business.review_count) reviews")
                                                .font(.system(size: 13))
                                                .foregroundStyle(.secondary)
                                        }
                                        
                                        // Categories
                                        if let categories = business.categories, !categories.isEmpty {
                                            Text(categories.prefix(2).map { $0.title }.joined(separator: " · "))
                                                .font(.system(size: 12))
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                        
                                        // Price
                                        if let price = business.price, !price.isEmpty {
                                            Text(price)
                                                .font(.system(size: 12, weight: .medium))
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    
                                    Spacer()
                                    
                                    // Chevron
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(.secondary)
                                }
                                .padding(14)
                                .background(Color(uiColor: .systemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
                .frame(maxHeight: 400)
            }
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 10)
        .padding(.horizontal)
    }
}

// Skeleton loader for search results
struct SearchResultSkeleton: View {
    @State private var isAnimating = false
    
    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.2))
                .frame(width: 60, height: 60)
            
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 16)
                    .frame(maxWidth: .infinity)
                
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 12)
                    .frame(width: 120)
                
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 12)
                    .frame(width: 80)
            }
            
            Spacer()
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .opacity(isAnimating ? 0.5 : 1.0)
        .onAppear {
            withAnimation(Animation.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
    }
}

struct DashboardView_Previews: PreviewProvider {
    static var previews: some View {
        DashboardView(appState: AppState())
            .environmentObject(AppDataService.shared)
            .environmentObject(AppState())
    }
}


struct ItineraryPin: View {
    let item: ItineraryItem
    let isSelected: Bool
    
    // Warm theme colors
    private let warmAccent = Color(red: 0.76, green: 0.42, blue: 0.32)
    private let warmAccentLight = Color(red: 0.85, green: 0.55, blue: 0.4)
    
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Image(systemName: iconForType(item.type))
                    .font(.system(size: 20))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(item.isAISuggestion ? warmAccentLight : warmAccent)
                    .clipShape(Circle())
                    .scaleEffect(isSelected ? 1.2 : 1.0)
                    .shadow(radius: 5)
                
                if item.isAISuggestion {
                    Image(systemName: "sparkles")
                        .font(.caption2)
                        .foregroundStyle(.white)
                        .offset(x: 14, y: -14)
                }
                
                if item.location.aiRemark != nil {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.caption2)
                        .foregroundStyle(warmAccent)
                        .offset(x: -14, y: -14)
                        .background(Circle().fill(Color.white).frame(width: 12, height: 12).offset(x: -14, y: -14))
                }
            }
            
            Image(systemName: "triangle.fill")
                .font(.caption)
                .foregroundStyle(item.isAISuggestion ? warmAccentLight : warmAccent)
                .offset(y: -4)
                .rotationEffect(.degrees(180))
        }
        .animation(.spring(), value: isSelected)
    }
    
    private func iconForType(_ type: ItineraryItemType) -> String {
        switch type {
        case .appetizer: return "fork.knife"
        case .main: return "fork.knife.circle.fill"
        case .dessert: return "birthday.cake"
        case .drinks: return "wineglass"
        case .activity: return "figure.walk"
        }
    }
}

// MARK: - Fancy Map Marker
struct FancyMapMarker: View {
    enum MarkerType {
        case search
        case itinerary
        case aiSuggestion
        case saved
    }
    
    let type: MarkerType
    let icon: String
    let isAI: Bool
    let name: String?
    
    @State private var isAnimating = false
    
    // Warm theme accent
    private let warmAccent = Color(red: 0.76, green: 0.42, blue: 0.32)
    
    private var gradientColors: [Color] {
        switch type {
        case .search:
            // Darker terracotta for search
            return [Color(red: 0.65, green: 0.35, blue: 0.25), Color(red: 0.55, green: 0.28, blue: 0.2)]
        case .itinerary:
            // Main terracotta
            return [Color(red: 0.76, green: 0.42, blue: 0.32), Color(red: 0.66, green: 0.32, blue: 0.22)]
        case .aiSuggestion:
            // Lighter warm tone for AI
            return [Color(red: 0.85, green: 0.55, blue: 0.4), Color(red: 0.76, green: 0.42, blue: 0.32)]
        case .saved:
            // Deep warm red for saved
            return [Color(red: 0.8, green: 0.35, blue: 0.28), Color(red: 0.7, green: 0.25, blue: 0.2)]
        }
    }
    
    private var glowColor: Color {
        warmAccent
    }
    
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                // Outer glow ring
                Circle()
                    .fill(glowColor.opacity(0.2))
                    .frame(width: 52, height: 52)
                    .scaleEffect(isAnimating ? 1.15 : 1.0)
                    .opacity(isAnimating ? 0.5 : 0.8)
                
                // Main marker body
                ZStack {
                    // Background with gradient
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: gradientColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)
                        .shadow(color: glowColor.opacity(0.4), radius: 8, x: 0, y: 4)
                    
                    // Inner highlight
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.white.opacity(0.4), .clear],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                        .frame(width: 44, height: 44)
                    
                    // Icon
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.2), radius: 1, x: 0, y: 1)
                }
                
            }
            
            // Pointer triangle
            Canvas { context, size in
                let path = Path { p in
                    p.move(to: CGPoint(x: size.width / 2 - 10, y: 0))
                    p.addLine(to: CGPoint(x: size.width / 2, y: size.height))
                    p.addLine(to: CGPoint(x: size.width / 2 + 10, y: 0))
                    p.closeSubpath()
                }
                context.fill(path, with: .linearGradient(
                    Gradient(colors: gradientColors),
                    startPoint: CGPoint(x: 0, y: size.height / 2),
                    endPoint: CGPoint(x: size.width, y: size.height / 2)
                ))
            }
            .frame(width: 30, height: 12)
            .offset(y: -2)
            .shadow(color: glowColor.opacity(0.3), radius: 4, x: 0, y: 2)
        }
        .onAppear {
            withAnimation(
                .easeInOut(duration: 1.5)
                .repeatForever(autoreverses: true)
            ) {
                isAnimating = true
            }
        }
    }
}

#Preview {
    DashboardView(appState: AppState())
        .environmentObject(AppDataService.shared)
        .environmentObject(AppState())
}

struct SearchResultsOverlay: View {
    @Binding var searchText: String
    let items: [ItineraryItem]
    let onSelect: (ItineraryItem) -> Void
    
    @State private var isLoading = true
    
    var filteredItems: [ItineraryItem] {
        if searchText.isEmpty { return [] }
        return items.filter { item in
            item.location.name.localizedCaseInsensitiveContains(searchText) ||
            (item.notes?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }
    
    var body: some View {
        VStack {
            if isLoading {
                ScrollView {
                    VStack(spacing: 16) {
                        ForEach(0..<6) { _ in
                            SkeletonRow()
                        }
                    }
                    .padding()
                }
            } else {
                if searchText.isEmpty {
                     ContentUnavailableView("Start Searching", systemImage: "magnifyingglass", description: Text("Find your next favorite spot."))
                } else if filteredItems.isEmpty {
                    ContentUnavailableView("No Results", systemImage: "magnifyingglass", description: Text("Try searching for something else."))
                } else {

                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(filteredItems) { item in
                                Button(action: { onSelect(item) }) {
                                    HStack {
                                        Image(systemName: "mappin.circle.fill")
                                            .foregroundStyle(.blue)
                                            .font(.title2)
                                        
                                        VStack(alignment: .leading) {
                                            Text(item.location.name)
                                                .font(.headline)
                                                .foregroundStyle(.primary)
                                            if let notes = item.notes {
                                                Text(notes)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(1)
                                            }
                                        }
                                        Spacer()
                                    }
                                    .padding(.vertical, 8)
                                    .padding(.horizontal)
                                    .contentShape(Rectangle())
                                }
                                Divider()
                                    .padding(.leading, 40)
                            }
                        }
                    }
                    .frame(maxHeight: 300)
                }
            }
        }
        .background(.ultraThinMaterial)
        .cornerRadius(20)
        .padding(.horizontal)
        .padding(.bottom)
        .onAppear {
            // Simulate loading
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { // Reduced delay for better UX
                withAnimation {
                    isLoading = false
                }
            }
        }
        .onChange(of: searchText) {
            // Reset loading on new search
            isLoading = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { // Reduced delay
                withAnimation {
                    isLoading = false
                }
            }
        }
    }
}

struct SkeletonRow: View {
    @State private var isAnimating = false
    
    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.2))
                .frame(width: 60, height: 60)
            
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 16)
                    .frame(maxWidth: .infinity)
                
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 12)
                    .frame(width: 100)
            }
        }
        .opacity(isAnimating ? 0.5 : 1.0)
        .onAppear {
            withAnimation(Animation.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
    }
}
