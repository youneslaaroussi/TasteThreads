import Foundation
import CoreLocation

// MARK: - User Context Protocol

/// Protocol for providing contextual data to AI requests
/// Implement this to add new context sources
protocol UserContextSource {
    /// Unique key for this context source
    var contextKey: String { get }
    
    /// Build context data. Return nil if no data available.
    func buildContext() -> [String: Any]?
}

// MARK: - User Context Provider

/// Central provider that aggregates context from multiple sources
final class UserContextProvider {
    static let shared = UserContextProvider()
    
    private var sources: [UserContextSource] = []
    
    private init() {
        // Register default sources
        registerDefaultSources()
    }
    
    private func registerDefaultSources() {
        register(UserProfileContext())
        register(LocationContext())
        register(SavedPlacesContext())
        register(PreferencesContext())
    }
    
    /// Register a new context source
    func register(_ source: UserContextSource) {
        // Avoid duplicates
        if !sources.contains(where: { $0.contextKey == source.contextKey }) {
            sources.append(source)
        }
    }
    
    /// Build aggregated context from all sources
    func buildContext() -> [String: Any] {
        var context: [String: Any] = [:]
        
        for source in sources {
            if let sourceContext = source.buildContext() {
                context[source.contextKey] = sourceContext
            }
        }
        
        // Add metadata
        context["_meta"] = [
            "client": "ios",
            "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        
        return context
    }
}

// MARK: - Default Context Sources

/// User profile information
struct UserProfileContext: UserContextSource {
    var contextKey: String { "user" }
    
    func buildContext() -> [String: Any]? {
        let user = AppDataService.shared.currentUser
        guard user.id != "loading" else { return nil }
        
        return [
            "name": user.name,
            "first_name": user.name.components(separatedBy: " ").first ?? user.name
        ]
    }
}

/// User's current location (city-level for display, coordinates for Yelp API)
struct LocationContext: UserContextSource {
    var contextKey: String { "location" }
    
    func buildContext() -> [String: Any]? {
        // Get cached location from LocationManager if available
        guard let location = LocationContextCache.shared.currentLocation else {
            return nil
        }
        
        var context: [String: Any] = [:]
        
        // Include city-level info for context
        if let city = location.city {
            context["city"] = city
        }
        if let state = location.state {
            context["state"] = state
        }
        if let country = location.country {
            context["country"] = country
        }
        
        // Include coordinates for Yelp API (rounded to ~100m for reasonable privacy)
        // Yelp needs these to provide location-based results
        if let lat = location.latitude, let lon = location.longitude {
            context["approximate_area"] = [
                "latitude": (lat * 1000).rounded() / 1000,  // ~100m precision
                "longitude": (lon * 1000).rounded() / 1000
            ]
            // Also include at top level for easier extraction
            context["latitude"] = (lat * 1000).rounded() / 1000
            context["longitude"] = (lon * 1000).rounded() / 1000
        }
        
        return context.isEmpty ? nil : context
    }
}

/// User's saved places and taste profile
struct SavedPlacesContext: UserContextSource {
    var contextKey: String { "taste_profile" }
    
    func buildContext() -> [String: Any]? {
        let dataService = AppDataService.shared
        
        var context: [String: Any] = [:]
        
        // Saved places summary (not full data, just key info for AI context)
        let savedPlaces = dataService.savedLocations
        if !savedPlaces.isEmpty {
            let placeNames = savedPlaces.prefix(10).map { $0.name }
            let categories = savedPlaces.compactMap { $0.yelpDetails?.categories }.flatMap { $0 }
            let uniqueCategories = Array(Set(categories)).prefix(10)
            let avgRating = savedPlaces.reduce(0.0) { $0 + $1.rating } / Double(savedPlaces.count)
            let priceRanges = savedPlaces.compactMap { $0.yelpDetails?.price }.filter { !$0.isEmpty }
            
            context["saved_count"] = savedPlaces.count
            context["favorite_places"] = Array(placeNames)
            context["preferred_categories"] = Array(uniqueCategories)
            context["average_rating_preference"] = String(format: "%.1f", avgRating)
            
            if !priceRanges.isEmpty {
                let priceCounts = Dictionary(grouping: priceRanges, by: { $0 }).mapValues { $0.count }
                let preferredPrice = priceCounts.max(by: { $0.value < $1.value })?.key
                context["preferred_price_range"] = preferredPrice
            }
        }
        
        // AI discoveries summary
        let aiDiscoveries = dataService.aiSuggestedLocations
        if !aiDiscoveries.isEmpty {
            context["ai_suggested_count"] = aiDiscoveries.count
            context["recent_ai_suggestions"] = Array(aiDiscoveries.prefix(5).map { $0.name })
        }
        
        return context.isEmpty ? nil : context
    }
}

/// User preferences and settings
struct PreferencesContext: UserContextSource {
    var contextKey: String { "preferences" }
    
    func buildContext() -> [String: Any]? {
        var context: [String: Any] = [:]
        
        // Dietary preferences (could be expanded with user settings)
        // For now, placeholder for future user preferences
        
        // Time context
        let hour = Calendar.current.component(.hour, from: Date())
        let mealTime: String
        switch hour {
        case 5..<11: mealTime = "breakfast"
        case 11..<14: mealTime = "lunch"
        case 14..<17: mealTime = "afternoon"
        case 17..<21: mealTime = "dinner"
        default: mealTime = "late_night"
        }
        context["current_meal_time"] = mealTime
        
        // Day of week context
        let dayOfWeek = Calendar.current.component(.weekday, from: Date())
        context["is_weekend"] = (dayOfWeek == 1 || dayOfWeek == 7)
        
        return context
    }
}

// MARK: - Location Cache

/// Caches reverse-geocoded location data
/// ALL operations happen on background queue - NEVER blocks UI
class LocationContextCache {
    static let shared = LocationContextCache()
    
    struct CachedLocation {
        let city: String?
        let state: String?
        let country: String?
        let latitude: Double?
        let longitude: Double?
        let timestamp: Date
    }
    
    private(set) var currentLocation: CachedLocation?
    private let geocoder = CLGeocoder()
    private let backgroundQueue = DispatchQueue(label: "com.tastethreads.location", qos: .utility)
    private var lastUpdateCoordinate: CLLocationCoordinate2D?
    private let minimumUpdateDistance: Double = 1000 // Only re-geocode if moved 1km+
    
    private init() {}
    
    /// Update location from CLLocation - runs entirely on background
    func updateAsync(from location: CLLocation) {
        backgroundQueue.async { [weak self] in
            self?.performUpdate(from: location)
        }
    }
    
    private func performUpdate(from location: CLLocation) {
        let lat = location.coordinate.latitude
        let lon = location.coordinate.longitude
        
        // Skip geocoding if we haven't moved much (saves API calls and battery)
        if let lastCoord = lastUpdateCoordinate {
            let lastLocation = CLLocation(latitude: lastCoord.latitude, longitude: lastCoord.longitude)
            if location.distance(from: lastLocation) < minimumUpdateDistance && currentLocation != nil {
                // Just update coordinates, skip geocoding
                currentLocation = CachedLocation(
                    city: currentLocation?.city,
                    state: currentLocation?.state,
                    country: currentLocation?.country,
                    latitude: lat,
                    longitude: lon,
                    timestamp: Date()
                )
                return
            }
        }
        
        lastUpdateCoordinate = location.coordinate
        
        // Geocode on background - CLGeocoder handles its own threading
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
            // Still on background-ish thread from geocoder callback
            guard let placemark = placemarks?.first, error == nil else {
                // Cache coordinates even without geocoding
                self?.currentLocation = CachedLocation(
                    city: nil,
                    state: nil,
                    country: nil,
                    latitude: lat,
                    longitude: lon,
                    timestamp: Date()
                )
                return
            }
            
            self?.currentLocation = CachedLocation(
                city: placemark.locality,
                state: placemark.administrativeArea,
                country: placemark.country,
                latitude: lat,
                longitude: lon,
                timestamp: Date()
            )
            
            #if DEBUG
            print("LocationContext: Updated to \(placemark.locality ?? "Unknown"), \(placemark.administrativeArea ?? "")")
            #endif
        }
    }
}

