import Foundation

// MARK: - User
struct User: Identifiable, Codable, Hashable {
    let id: String
    var name: String
    var avatarURL: URL?
    var profileImageURL: URL?  // User's uploaded profile picture
    var bio: String?           // User's bio/description
    var preferences: [String]? // User's preferences (cuisines, dietary, vibes, etc.)
    let isCurrentUser: Bool
    
    // Contact info for reservations
    var firstName: String?
    var lastName: String?
    var phoneNumber: String?
    var email: String?
    
    // AI User ID constant
    static let aiUserId = "00000000-0000-0000-0000-000000000001"
    
    var isAI: Bool {
        id == User.aiUserId
    }
    
    /// Full name for reservations, defaults to display name
    var fullName: String {
        if let first = firstName, let last = lastName, !first.isEmpty, !last.isEmpty {
            return "\(first) \(last)"
        }
        return name
    }
    
    enum CodingKeys: String, CodingKey {
        case id, name, email, bio, preferences
        case avatarURL = "avatar_url"
        case profileImageURL = "profile_image_url"
        case isCurrentUser = "is_current_user"
        case firstName = "first_name"
        case lastName = "last_name"
        case phoneNumber = "phone_number"
    }
    
    init(id: String, name: String, avatarURL: URL? = nil, profileImageURL: URL? = nil, bio: String? = nil, 
         preferences: [String]? = nil, isCurrentUser: Bool,
         firstName: String? = nil, lastName: String? = nil, phoneNumber: String? = nil, email: String? = nil) {
        self.id = id
        self.name = name
        self.avatarURL = avatarURL
        self.profileImageURL = profileImageURL
        self.bio = bio
        self.preferences = preferences
        self.isCurrentUser = isCurrentUser
        self.firstName = firstName
        self.lastName = lastName
        self.phoneNumber = phoneNumber
        self.email = email
    }
}

// MARK: - Room
struct Room: Identifiable, Codable {
    let id: String
    let name: String
    let members: [User]
    var messages: [Message]
    var itinerary: [ItineraryItem]
    var isPublic: Bool
    var joinCode: String
    let ownerId: String
    
    enum CodingKeys: String, CodingKey {
        case id, name, members, messages, itinerary
        case isPublic = "is_public"
        case joinCode = "join_code"
        case ownerId = "owner_id"
    }
}

// MARK: - Message
enum MessageType: String, Codable, Hashable {
    case text
    case system
    case map
}

struct Message: Identifiable, Codable, Hashable {
    let id: String
    let senderId: String
    let content: String
    let timestamp: Date
    var type: MessageType = .text
    var relatedItemId: String?
    var reactions: [String: [String]] = [:]
    var quickReplies: [String]? = nil
    var mapCoordinates: Location? = nil // Reusing Location for simplicity (lat/long + name)
    var businesses: [YelpBusiness]? = nil
    var actions: [ReservationAction]? = nil  // Reservation actions that trigger special UI
    
    var isSystemMessage: Bool { type == .system }
    
    /// Get the first reservation action if present
    var reservationAction: ReservationAction? {
        actions?.first
    }
    
    enum CodingKeys: String, CodingKey {
        case id, content, timestamp, type, reactions, businesses, actions
        case senderId = "sender_id"
        case relatedItemId = "related_item_id"
        case quickReplies = "quick_replies"
        case mapCoordinates = "map_coordinates"
    }
}

// MARK: - Reservation Models

/// A single available reservation time slot
struct ReservationTimeSlot: Codable, Hashable, Identifiable {
    var id: String { "\(date)-\(time)" }
    let date: String  // YYYY-MM-DD
    let time: String  // HH:MM
    var creditCardRequired: Bool = false
    
    enum CodingKeys: String, CodingKey {
        case date, time
        case creditCardRequired = "credit_card_required"
    }
    
    /// Formatted time for display (e.g., "7:00 PM")
    var formattedTime: String {
        let components = time.split(separator: ":")
        guard components.count >= 2,
              let hour = Int(components[0]),
              let minute = Int(components[1]) else {
            return time
        }
        
        let period = hour >= 12 ? "PM" : "AM"
        let hour12 = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour)
        return minute == 0 ? "\(hour12) \(period)" : "\(hour12):\(String(format: "%02d", minute)) \(period)"
    }
    
    /// Formatted date for display (e.g., "Mon, Dec 2")
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: date) else { return self.date }
        
        formatter.dateFormat = "EEE, MMM d"
        return formatter.string(from: date)
    }
}

/// Party size range supported by the restaurant
struct ReservationCoversRange: Codable, Hashable {
    let minPartySize: Int
    let maxPartySize: Int
    
    enum CodingKeys: String, CodingKey {
        case minPartySize = "min_party_size"
        case maxPartySize = "max_party_size"
    }
    
    init(minPartySize: Int = 1, maxPartySize: Int = 10) {
        self.minPartySize = minPartySize
        self.maxPartySize = maxPartySize
    }
}

/// Reservation action type
enum ReservationActionType: String, Codable, Hashable {
    case reservationPrompt = "reservation_prompt"
    case reservationConfirmed = "reservation_confirmed"
}

/// Structured reservation action that triggers special UI
struct ReservationAction: Codable, Hashable, Identifiable {
    var id: String { "\(type.rawValue)-\(businessId)" }
    
    let type: ReservationActionType
    let businessId: String
    let businessName: String
    var businessImageUrl: String?
    var businessAddress: String?
    var businessPhone: String?
    var businessRating: Double?
    var businessUrl: String?
    
    // For reservation_prompt
    var availableTimes: [ReservationTimeSlot]?
    var coversRange: ReservationCoversRange?
    var requestedDate: String?
    var requestedTime: String?
    var requestedCovers: Int?
    
    // For reservation_confirmed
    var holdId: String?
    var reservationId: String?
    var confirmationUrl: String?
    var confirmedDate: String?
    var confirmedTime: String?
    var confirmedCovers: Int?
    
    enum CodingKeys: String, CodingKey {
        case type
        case businessId = "business_id"
        case businessName = "business_name"
        case businessImageUrl = "business_image_url"
        case businessAddress = "business_address"
        case businessPhone = "business_phone"
        case businessRating = "business_rating"
        case businessUrl = "business_url"
        case availableTimes = "available_times"
        case coversRange = "covers_range"
        case requestedDate = "requested_date"
        case requestedTime = "requested_time"
        case requestedCovers = "requested_covers"
        case holdId = "hold_id"
        case reservationId = "reservation_id"
        case confirmationUrl = "confirmation_url"
        case confirmedDate = "confirmed_date"
        case confirmedTime = "confirmed_time"
        case confirmedCovers = "confirmed_covers"
    }
    
    /// Get the top N available time slots for quick selection
    func topTimeSlots(_ count: Int = 4) -> [ReservationTimeSlot] {
        guard let times = availableTimes else { return [] }
        return Array(times.prefix(count))
    }
    
    /// Formatted confirmed date/time for display
    var formattedConfirmation: String? {
        guard let date = confirmedDate, let time = confirmedTime else { return nil }
        let slot = ReservationTimeSlot(date: date, time: time)
        return "\(slot.formattedDate) at \(slot.formattedTime)"
    }
}

// MARK: - Itinerary
enum ItineraryItemType: String, Codable, CaseIterable {
    case appetizer = "Appetizer"
    case main = "Main Course"
    case dessert = "Dessert"
    case activity = "Activity"
    case drinks = "Drinks"
}

struct Dish: Codable, Hashable, Identifiable {
    let id: String
    let name: String
    let imageURL: URL?
    let price: String?
}

struct YelpDetails: Codable, Hashable {
    let price: String
    let reviewCount: Int
    let categories: [String]
    let isOpen: Bool
    let closingTime: String
    let phoneNumber: String
    let url: URL?
    let popularDishes: [Dish]
    let aiSummary: String?
    let photos: [String]?
    let hours: [String]? // Simplified for display, e.g. ["Mon: 9-5", ...]
}

struct Location: Codable, Hashable, Identifiable {
    var id: String { name + String(latitude) + String(longitude) }
    let name: String
    let address: String
    let latitude: Double
    let longitude: Double
    let rating: Double
    let imageURL: URL?
    let yelpDetails: YelpDetails?
    var aiRemark: String?
    var yelpId: String?
}

struct ItineraryItem: Identifiable, Codable, Hashable {
    let id: String
    var type: ItineraryItemType
    var location: Location
    var time: Date?
    var notes: String?
    var votes: Int
    var isAISuggestion: Bool = false
}
