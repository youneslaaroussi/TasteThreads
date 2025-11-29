import Foundation

// MARK: - User
struct User: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let avatarURL: URL?
    let isCurrentUser: Bool
    
    enum CodingKeys: String, CodingKey {
        case id, name
        case avatarURL = "avatar_url"
        case isCurrentUser = "is_current_user"
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
    
    var isSystemMessage: Bool { type == .system }
    
    enum CodingKeys: String, CodingKey {
        case id, content, timestamp, type, reactions, businesses
        case senderId = "sender_id"
        case relatedItemId = "related_item_id"
        case quickReplies = "quick_replies"
        case mapCoordinates = "map_coordinates"
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
