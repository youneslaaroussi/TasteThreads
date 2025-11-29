import Foundation
import Combine

class APIService: ObservableObject {
    static let shared = APIService()
    private let baseURL = Config.yelpAPIURL
    private let roomsBaseURL = Config.roomsAPIURL
    private let userBaseURL = Config.userAPIURL
    private let aiBaseURL = Config.aiAPIURL
    
    private func authenticatedRequest(url: URL, method: String = "GET", body: Encodable? = nil) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Add Auth Token
        let token = try await AuthenticationService.shared.getIDToken()
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        if let body = body {
            request.httpBody = try JSONEncoder().encode(body)
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.backendError("Invalid response")
        }
        
        if !(200...299).contains(httpResponse.statusCode) {
            if let errorJson = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                throw APIError.backendError(errorJson.detail)
            } else if let str = String(data: data, encoding: .utf8) {
                throw APIError.backendError(str)
            } else {
                throw APIError.backendError("Unknown error")
            }
        }
        
        return data
    }
    
    // MARK: - Yelp API (Public endpoints, but we can secure them too if needed)
    
    func chat(query: String, chatId: String? = nil) -> AnyPublisher<ChatResponse, Error> {
        // ... (Keep existing implementation for now, or update to async/await)
        // For simplicity, leaving Combine implementation as is since Yelp endpoints might not require auth yet
        // But ideally, everything should be authenticated.
        // Let's update it to use the authenticatedRequest pattern but wrap in Future for Combine compatibility if needed
        // Or just keep it as is if Yelp endpoints are public.
        // Assuming Yelp endpoints are public for now based on previous code.
        print("APIService: Sending chat request: \(query)")
        guard let url = URL(string: "\(baseURL)/chat") else {
            return Fail(error: URLError(.badURL)).eraseToAnyPublisher()
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = ChatRequest(query: query, chat_id: chatId)
        do {
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            return Fail(error: error).eraseToAnyPublisher()
        }
        
        return URLSession.shared.dataTaskPublisher(for: request)
            .map(\.data)
            .decode(type: ChatResponse.self, decoder: JSONDecoder())
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }
    
    func search(term: String, location: String? = nil, latitude: Double? = nil, longitude: Double? = nil) -> AnyPublisher<SearchResponse, Error> {
        // ... (Keep existing implementation)
        var components = URLComponents(string: "\(baseURL)/search")
        var queryItems = [URLQueryItem(name: "term", value: term)]
        
        if let location = location {
            queryItems.append(URLQueryItem(name: "location", value: location))
        }
        if let latitude = latitude {
            queryItems.append(URLQueryItem(name: "latitude", value: String(latitude)))
        }
        if let longitude = longitude {
            queryItems.append(URLQueryItem(name: "longitude", value: String(longitude)))
        }
        
        components?.queryItems = queryItems
        
        guard let url = components?.url else {
            return Fail(error: URLError(.badURL)).eraseToAnyPublisher()
        }
        
        return URLSession.shared.dataTaskPublisher(for: url)
            .map(\.data)
            .decode(type: SearchResponse.self, decoder: JSONDecoder())
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }
    
    func getBusinessDetails(id: String) -> AnyPublisher<YelpBusinessDetails, Error> {
        guard let url = URL(string: "\(baseURL)/business/\(id)") else {
            return Fail(error: URLError(.badURL)).eraseToAnyPublisher()
        }
        
        return URLSession.shared.dataTaskPublisher(for: url)
            .map(\.data)
            .decode(type: YelpBusinessDetails.self, decoder: JSONDecoder())
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }
    
    /// Fetches comprehensive business details including reviews in a single call
    func getFullBusinessDetails(id: String) -> AnyPublisher<YelpBusinessFull, Error> {
        guard let url = URL(string: "\(baseURL)/business/\(id)/full") else {
            return Fail(error: URLError(.badURL)).eraseToAnyPublisher()
        }
        
        return URLSession.shared.dataTaskPublisher(for: url)
            .map(\.data)
            .decode(type: YelpBusinessFull.self, decoder: JSONDecoder())
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }
    
    func generateTastePersona(savedPlaces: [Location], aiSuggestions: [Location]) -> AnyPublisher<TastePersona, Error> {
        print("APIService: Generating taste persona via orchestrator backend")
        
        // Persona is now generated on the backend using the user's saved locations
        // and AI discoveries from the database (no direct Yelp AI call here).
        return futureRequest {
            guard let url = URL(string: "\(self.aiBaseURL)/taste-persona") else {
                throw URLError(.badURL)
            }
            let data = try await self.authenticatedRequest(url: url)
            return try JSONDecoder().decode(TastePersona.self, from: data)
        }
    }
    
    // MARK: - Reservations (Yelp Reservations API via backend)
    
    func getReservationOpenings(
        businessId: String,
        date: String,
        time: String,
        covers: Int = 2
    ) -> AnyPublisher<ReservationOpeningsResponse, Error> {
        return futureRequest {
            var components = URLComponents(string: "\(self.aiBaseURL)/reservations/openings")
            components?.queryItems = [
                URLQueryItem(name: "business_id", value: businessId),
                URLQueryItem(name: "date", value: date),
                URLQueryItem(name: "time", value: time),
                URLQueryItem(name: "covers", value: String(covers)),
            ]
            
            guard let url = components?.url else { throw URLError(.badURL) }
            let data = try await self.authenticatedRequest(url: url)
            return try JSONDecoder().decode(ReservationOpeningsResponse.self, from: data)
        }
    }
    
    // MARK: - Room API (Authenticated)
    
    // Helper to bridge Async/Await to Combine
    private func futureRequest<T: Decodable>(operation: @escaping () async throws -> T) -> AnyPublisher<T, Error> {
        return Future { promise in
            Task {
                do {
                    let result = try await operation()
                    promise(.success(result))
                } catch {
                    promise(.failure(error))
                }
            }
        }
        .receive(on: DispatchQueue.main)
        .eraseToAnyPublisher()
    }
    
    // Helper for void requests (no response body)
    private func futureVoidRequest(operation: @escaping () async throws -> Void) -> AnyPublisher<Void, Error> {
        return Future { promise in
            Task {
                do {
                    try await operation()
                    promise(.success(()))
                } catch {
                    promise(.failure(error))
                }
            }
        }
        .receive(on: DispatchQueue.main)
        .eraseToAnyPublisher()
    }
    
    func getRooms(userId: String) -> AnyPublisher<[Room], Error> {
        return futureRequest {
            guard let url = URL(string: "\(self.roomsBaseURL)/") else { throw URLError(.badURL) }
            let data = try await self.authenticatedRequest(url: url)
            return try JSONDecoder.iso8601.decode([Room].self, from: data)
        }
    }
    
    func getPublicRooms() -> AnyPublisher<[Room], Error> {
        return futureRequest {
            guard let url = URL(string: "\(self.roomsBaseURL)/public") else { throw URLError(.badURL) }
            let data = try await self.authenticatedRequest(url: url)
            return try JSONDecoder.iso8601.decode([Room].self, from: data)
        }
    }
    
    func getMyRooms(userId: String) -> AnyPublisher<[Room], Error> {
        return futureRequest {
            guard let url = URL(string: "\(self.roomsBaseURL)/mine") else { throw URLError(.badURL) }
            let data = try await self.authenticatedRequest(url: url)
            return try JSONDecoder.iso8601.decode([Room].self, from: data)
        }
    }
    
    func createRoom(name: String, isPublic: Bool, ownerId: String, ownerName: String) -> AnyPublisher<Room, Error> {
        return futureRequest {
            guard let url = URL(string: "\(self.roomsBaseURL)/") else { throw URLError(.badURL) }
            let body = CreateRoomRequest(name: name, is_public: isPublic, owner_id: ownerId, owner_name: ownerName)
            let data = try await self.authenticatedRequest(url: url, method: "POST", body: body)
            return try JSONDecoder.iso8601.decode(Room.self, from: data)
        }
    }
    
    func joinRoom(code: String, userId: String, userName: String) -> AnyPublisher<Room, Error> {
        return futureRequest {
            guard let url = URL(string: "\(self.roomsBaseURL)/join") else { throw URLError(.badURL) }
            let body = JoinRoomRequest(code: code, user_id: userId, user_name: userName)
            let data = try await self.authenticatedRequest(url: url, method: "POST", body: body)
            return try JSONDecoder.iso8601.decode(Room.self, from: data)
        }
    }
    
    func sendMessage(roomId: String, senderId: String, content: String, includeContext: Bool = true) -> AnyPublisher<Message, Error> {
        return futureRequest {
            guard let url = URL(string: "\(self.roomsBaseURL)/\(roomId)/messages") else { throw URLError(.badURL) }
            
            // Build user context if enabled
            let context: [String: Any]? = includeContext ? UserContextProvider.shared.buildContext() : nil
            
            let body = SendMessageRequest(sender_id: senderId, content: content, user_context: context)
            let data = try await self.authenticatedRequest(url: url, method: "POST", body: body)
            return try JSONDecoder.iso8601.decode(Message.self, from: data)
        }
    }
    
    func deleteRoom(roomId: String) -> AnyPublisher<Void, Error> {
        return futureVoidRequest {
            guard let url = URL(string: "\(self.roomsBaseURL)/\(roomId)") else { throw URLError(.badURL) }
            _ = try await self.authenticatedRequest(url: url, method: "DELETE", body: nil as String?)
        }
    }
    
    func leaveRoom(roomId: String) -> AnyPublisher<Void, Error> {
        return futureVoidRequest {
            guard let url = URL(string: "\(self.roomsBaseURL)/\(roomId)/leave") else { throw URLError(.badURL) }
            _ = try await self.authenticatedRequest(url: url, method: "POST", body: nil as String?)
        }
    }
    
    // MARK: - User Collections API (Saved Locations & AI Discoveries)
    
    func getSavedLocations() -> AnyPublisher<[SavedLocationResponse], Error> {
        return futureRequest {
            guard let url = URL(string: "\(self.userBaseURL)/saved") else { throw URLError(.badURL) }
            let data = try await self.authenticatedRequest(url: url)
            return try JSONDecoder.iso8601.decode([SavedLocationResponse].self, from: data)
        }
    }
    
    func saveLocation(_ location: Location) -> AnyPublisher<SavedLocationResponse, Error> {
        return futureRequest {
            guard let url = URL(string: "\(self.userBaseURL)/saved") else { throw URLError(.badURL) }
            let body = SaveLocationRequest(location: location.toAPILocation())
            let data = try await self.authenticatedRequest(url: url, method: "POST", body: body)
            return try JSONDecoder.iso8601.decode(SavedLocationResponse.self, from: data)
        }
    }
    
    func unsaveLocation(yelpId: String) -> AnyPublisher<Void, Error> {
        return futureVoidRequest {
            guard let url = URL(string: "\(self.userBaseURL)/saved/\(yelpId)") else { throw URLError(.badURL) }
            _ = try await self.authenticatedRequest(url: url, method: "DELETE", body: nil as String?)
        }
    }
    
    func getAIDiscoveries() -> AnyPublisher<[AIDiscoveryResponse], Error> {
        return futureRequest {
            guard let url = URL(string: "\(self.userBaseURL)/discoveries") else { throw URLError(.badURL) }
            let data = try await self.authenticatedRequest(url: url)
            return try JSONDecoder.iso8601.decode([AIDiscoveryResponse].self, from: data)
        }
    }
    
    func addAIDiscovery(location: Location, aiRemark: String?, roomId: String?) -> AnyPublisher<AIDiscoveryResponse, Error> {
        return futureRequest {
            guard let url = URL(string: "\(self.userBaseURL)/discoveries") else { throw URLError(.badURL) }
            let body = AIDiscoveryRequest(location: location.toAPILocation(), ai_remark: aiRemark, room_id: roomId)
            let data = try await self.authenticatedRequest(url: url, method: "POST", body: body)
            return try JSONDecoder.iso8601.decode(AIDiscoveryResponse.self, from: data)
        }
    }
    
    func addAIDiscoveriesBatch(discoveries: [AIDiscoveryRequest]) -> AnyPublisher<BatchDiscoveryResponse, Error> {
        return futureRequest {
            guard let url = URL(string: "\(self.userBaseURL)/discoveries/batch") else { throw URLError(.badURL) }
            let data = try await self.authenticatedRequest(url: url, method: "POST", body: discoveries)
            return try JSONDecoder().decode(BatchDiscoveryResponse.self, from: data)
        }
    }
    
    func removeAIDiscovery(yelpId: String) -> AnyPublisher<Void, Error> {
        return futureVoidRequest {
            guard let url = URL(string: "\(self.userBaseURL)/discoveries/\(yelpId)") else { throw URLError(.badURL) }
            _ = try await self.authenticatedRequest(url: url, method: "DELETE", body: nil as String?)
        }
    }
}

extension JSONDecoder {
    static var iso8601: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            
            // Try multiple ISO8601 formats
            let formatters: [ISO8601DateFormatter] = [
                {
                    let f = ISO8601DateFormatter()
                    f.formatOptions = [.withInternetDateTime]
                    return f
                }(),
                {
                    let f = ISO8601DateFormatter()
                    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    return f
                }()
            ]
            
            for formatter in formatters {
                if let date = formatter.date(from: dateString) {
                    return date
                }
            }
            
            // Fallback: try DateFormatter for non-standard formats
            let fallback = DateFormatter()
            fallback.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
            fallback.timeZone = TimeZone(identifier: "UTC")
            if let date = fallback.date(from: dateString) {
                return date
            }
            
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Cannot decode date: \(dateString)")
            )
        }
        return decoder
    }
}

// MARK: - Request/Response Models

struct ChatRequest: Codable {
    let query: String
    let chat_id: String?
}

struct ChatResponse: Codable, Hashable {
    let chat_id: String
    let response: AIResponse
    let entities: [Entity]?
}

struct SearchResponse: Codable {
    let businesses: [YelpBusiness]
}

struct AIResponse: Codable, Hashable {
    let text: String
    let tags: [Tag]?
}

struct Tag: Codable, Hashable {
    let tag_type: String
    let start: Int
    let end: Int
    let meta: TagMeta?
}

struct TagMeta: Codable, Hashable {
    let business_id: String?
}

struct Entity: Codable, Hashable {
    let businesses: [YelpBusiness]?
}

struct YelpBusiness: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let image_url: String?
    let url: String?
    let rating: Double
    let review_count: Int
    let price: String?
    let categories: [Category]?
    let location: BusinessLocation?
    let coordinates: Coordinates?
    let phone: String?
    let display_phone: String?
    let contextual_info: ContextualInfo?
}

struct YelpBusinessDetails: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let image_url: String?
    let url: String?
    let rating: Double
    let review_count: Int
    let price: String?
    let categories: [Category]
    let location: BusinessLocation
    let coordinates: Coordinates
    let phone: String?
    let display_phone: String?
    let photos: [String]?
    let hours: [BusinessHour]?
    let is_closed: Bool?
    let transactions: [String]?
}

// Full business details including reviews (from /business/{id}/full endpoint)
struct YelpBusinessFull: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let image_url: String?
    let url: String?
    let rating: Double
    let review_count: Int
    let price: String?
    let categories: [Category]
    let location: BusinessLocation
    let coordinates: Coordinates
    let phone: String?
    let display_phone: String?
    let photos: [String]?
    let hours: [BusinessHour]?
    let is_closed: Bool?
    let transactions: [String]?
    let reviews: [YelpReview]?
    let total_reviews: Int?
    
    var isOpenNow: Bool {
        hours?.first?.is_open_now ?? false
    }
    
    var formattedHours: [String] {
        guard let businessHours = hours?.first?.open else { return [] }
        let dayNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        var result: [String] = []
        
        for dayHour in businessHours {
            let dayName = dayNames[safe: dayHour.day] ?? "Day \(dayHour.day)"
            let startFormatted = formatTime(dayHour.start)
            let endFormatted = formatTime(dayHour.end)
            result.append("\(dayName): \(startFormatted) - \(endFormatted)")
        }
        return result
    }
    
    private func formatTime(_ time: String) -> String {
        guard time.count == 4 else { return time }
        let hour = Int(time.prefix(2)) ?? 0
        let minute = time.suffix(2)
        let period = hour >= 12 ? "PM" : "AM"
        let hour12 = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour)
        return minute == "00" ? "\(hour12) \(period)" : "\(hour12):\(minute) \(period)"
    }
}

struct YelpReview: Codable, Identifiable, Hashable {
    let id: String
    let text: String
    let rating: Int
    let time_created: String
    let user: YelpReviewUser
    let url: String?
}

struct YelpReviewUser: Codable, Hashable {
    let id: String
    let name: String
    let image_url: String?
    let profile_url: String?
}

struct BusinessHour: Codable, Hashable {
    let open: [OpenHour]
    let hours_type: String
    let is_open_now: Bool
}

struct OpenHour: Codable, Hashable {
    let is_overnight: Bool
    let start: String
    let end: String
    let day: Int
}

extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

struct ContextualInfo: Codable, Hashable {
    let photos: [Photo]?
    let review_snippet: String?
}

struct Photo: Codable, Hashable {
    let original_url: String
}

struct Category: Codable, Hashable {
    let alias: String
    let title: String
}

struct Coordinates: Codable, Hashable {
    let latitude: Double
    let longitude: Double
}

struct BusinessLocation: Codable, Hashable {
    let address1: String?
    let city: String?
    let zip_code: String?
    let country: String?
    let state: String?
    let display_address: [String]?
    let formatted_address: String?
}

extension YelpBusiness {
    func toLocation() -> Location {
        return Location(
            name: name,
            address: location?.formatted_address ?? location?.address1 ?? "",
            latitude: coordinates?.latitude ?? 0.0,
            longitude: coordinates?.longitude ?? 0.0,
            rating: rating,
            imageURL: URL(string: image_url ?? ""),
            yelpDetails: YelpDetails(
                price: price ?? "",
                reviewCount: review_count,
                categories: categories?.map { $0.title } ?? [],
                isOpen: true, // Defaulting as API doesn't always return this in search
                closingTime: "",
                phoneNumber: display_phone ?? phone ?? "",
                url: URL(string: url ?? ""),
                popularDishes: [], // Not in basic business object
                aiSummary: contextual_info?.review_snippet,
                photos: nil,
                hours: nil
            ),
            aiRemark: nil,
            yelpId: id
        )
    }
}

enum APIError: Error, LocalizedError {
    case backendError(String)
    case unknown
    
    var errorDescription: String? {
        switch self {
        case .backendError(let message):
            return message
        case .unknown:
            return "An unknown error occurred."
        }
    }
}

struct ErrorResponse: Codable {
    let detail: String
}

struct CreateRoomRequest: Codable {
    let name: String
    let is_public: Bool
    let owner_id: String
    let owner_name: String
}

struct JoinRoomRequest: Codable {
    let code: String
    let user_id: String
    let user_name: String
}

struct SendMessageRequest: Codable {
    let sender_id: String
    let content: String
    let type: String
    let user_context: [String: AnyCodable]?
    
    init(sender_id: String, content: String, type: String = "text", user_context: [String: Any]? = nil) {
        self.sender_id = sender_id
        self.content = content
        self.type = type
        self.user_context = user_context?.mapValues { AnyCodable($0) }
    }
}

/// Type-erased Codable wrapper for dynamic context data
struct AnyCodable: Codable {
    let value: Any
    
    init(_ value: Any) {
        self.value = value
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            value = NSNull()
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch value {
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            try container.encodeNil()
        }
    }
}

struct TastePersona: Codable {
    let title: String
    let bio: String
}

// MARK: - Reservations Models

struct ReservationOpeningsResponse: Codable {
    let reservation_times: [ReservationDay]
    let covers_range: CoversRange?
}

struct ReservationDay: Codable {
    let date: String
    let times: [ReservationTime]
}

struct ReservationTime: Codable {
    let credit_card_required: Bool
    let time: String
}

struct CoversRange: Codable {
    let min_party_size: Int
    let max_party_size: Int
}

// MARK: - User Collections Models

struct APILocationData: Codable {
    let name: String
    let address: String
    let latitude: Double
    let longitude: Double
    let rating: Double
    let image_url: String?
    let yelp_id: String?
    let yelp_details: APIYelpDetails?
    let ai_remark: String?
}

struct APIYelpDetails: Codable {
    let price: String?
    let reviewCount: Int?
    let categories: [String]?
    let isOpen: Bool?
    let closingTime: String?
    let phoneNumber: String?
    let url: String?
    let aiSummary: String?
    let photos: [String]?
}

struct SaveLocationRequest: Codable {
    let location: APILocationData
}

struct AIDiscoveryRequest: Codable {
    let location: APILocationData
    let ai_remark: String?
    let room_id: String?
}

struct SavedLocationResponse: Codable, Identifiable {
    let id: String
    let yelp_id: String
    let location: APILocationData
    let created_at: Date
    
    func toLocation() -> Location {
        return Location(
            name: location.name,
            address: location.address,
            latitude: location.latitude,
            longitude: location.longitude,
            rating: location.rating,
            imageURL: location.image_url.flatMap { URL(string: $0) },
            yelpDetails: location.yelp_details.map { details in
                YelpDetails(
                    price: details.price ?? "",
                    reviewCount: details.reviewCount ?? 0,
                    categories: details.categories ?? [],
                    isOpen: details.isOpen ?? false,
                    closingTime: details.closingTime ?? "",
                    phoneNumber: details.phoneNumber ?? "",
                    url: details.url.flatMap { URL(string: $0) },
                    popularDishes: [],
                    aiSummary: details.aiSummary,
                    photos: details.photos,
                    hours: nil
                )
            },
            aiRemark: location.ai_remark,
            yelpId: location.yelp_id
        )
    }
}

struct AIDiscoveryResponse: Codable, Identifiable {
    let id: String
    let yelp_id: String
    let location: APILocationData
    let ai_remark: String?
    let room_id: String?
    let created_at: Date
    
    func toLocation() -> Location {
        var loc = Location(
            name: location.name,
            address: location.address,
            latitude: location.latitude,
            longitude: location.longitude,
            rating: location.rating,
            imageURL: location.image_url.flatMap { URL(string: $0) },
            yelpDetails: location.yelp_details.map { details in
                YelpDetails(
                    price: details.price ?? "",
                    reviewCount: details.reviewCount ?? 0,
                    categories: details.categories ?? [],
                    isOpen: details.isOpen ?? false,
                    closingTime: details.closingTime ?? "",
                    phoneNumber: details.phoneNumber ?? "",
                    url: details.url.flatMap { URL(string: $0) },
                    popularDishes: [],
                    aiSummary: details.aiSummary,
                    photos: details.photos,
                    hours: nil
                )
            },
            aiRemark: ai_remark ?? location.ai_remark,
            yelpId: location.yelp_id
        )
        return loc
    }
}

struct BatchDiscoveryResponse: Codable {
    let success: Bool
    let added_count: Int
    let ids: [String]
}

extension Location {
    func toAPILocation() -> APILocationData {
        return APILocationData(
            name: name,
            address: address,
            latitude: latitude,
            longitude: longitude,
            rating: rating,
            image_url: imageURL?.absoluteString,
            yelp_id: yelpId,
            yelp_details: yelpDetails.map { details in
                APIYelpDetails(
                    price: details.price,
                    reviewCount: details.reviewCount,
                    categories: details.categories,
                    isOpen: details.isOpen,
                    closingTime: details.closingTime,
                    phoneNumber: details.phoneNumber,
                    url: details.url?.absoluteString,
                    aiSummary: details.aiSummary,
                    photos: details.photos
                )
            },
            ai_remark: aiRemark
        )
    }
}
