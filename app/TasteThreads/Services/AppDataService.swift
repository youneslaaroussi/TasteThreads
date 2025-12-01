import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore
import CoreLocation

protocol DataService {
    func getCurrentUser() -> User
    func getRoom(id: String) -> AnyPublisher<Room, Error>
    func sendMessage(content: String)
    func addItineraryItem(item: ItineraryItem)
}

class AppDataService: DataService, ObservableObject {
    
    static let shared = AppDataService()
    
    @Published var rooms: [Room] = []
    @Published var currentRoomId: String?
    @Published var isAITyping: Bool = false
    @Published var savedLocations: [Location] = []
    @Published var typingUsers: Set<String> = [] // Track who is typing
    @Published var businessRemarks: [String: String] = [:] // Store AI remarks for businesses
    @Published var aiSuggestedLocations: [Location] = [] // All businesses mentioned by AI in current room
    
    @Published var currentUser: User
    let aiUser: User
    
    private var cancellables = Set<AnyCancellable>()
    private let authService = AuthenticationService.shared
    private let db = Firestore.firestore()
    private var messageListener: ListenerRegistration?
    
    // Background location service
    private let locationService = BackgroundLocationService()
    
    var currentRoom: Room? {
        guard let id = currentRoomId else { return nil }
        return rooms.first(where: { $0.id == id })
    }
    
    init() {
        // AI User
        self.aiUser = User(id: User.aiUserId, name: "Tess (AI)", avatarURL: nil, profileImageURL: nil, isCurrentUser: false)
        
        // Initial dummy user until auth loads
        self.currentUser = User(id: "loading", name: "Loading...", avatarURL: nil, profileImageURL: nil, isCurrentUser: true)
        
        setupAuthListener()
        locationService.startMonitoring()
    }
    
    private func setupAuthListener() {
        authService.$user
            .sink { [weak self] firebaseUser in
                guard let self = self else { return }
                if let firebaseUser = firebaseUser {
                    // Update current user from Firebase initially
                    self.currentUser = User(
                        id: firebaseUser.uid,
                        name: firebaseUser.displayName ?? firebaseUser.email ?? "User",
                        avatarURL: nil,
                        profileImageURL: nil,
                        isCurrentUser: true
                    )
                    self.fetchRooms()
                    self.fetchSavedLocations()
                    self.fetchAIDiscoveries()
                    self.fetchUserProfile()  // Fetch profile picture
                } else {
                    self.rooms = []
                    self.currentRoomId = nil
                    self.savedLocations = []
                    self.aiSuggestedLocations = []
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - User Profile
    
    func fetchUserProfile() {
        print("AppDataService: Fetching user profile...")
        APIService.shared.getUserProfile()
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { completion in
                if case .failure(let error) = completion {
                    print("AppDataService: Error fetching user profile: \(error)")
                }
            }, receiveValue: { [weak self] response in
                guard let self = self else { return }
                print("AppDataService: Fetched user profile with image: \(response.profile_image_url ?? "none")")
                
                // Update current user with profile image, bio, preferences, and contact info
                let profileImageURL = response.profile_image_url.flatMap { URL(string: $0) }
                self.currentUser = User(
                    id: self.currentUser.id,
                    name: response.name,
                    avatarURL: self.currentUser.avatarURL,
                    profileImageURL: profileImageURL,
                    bio: response.bio,
                    preferences: response.preferences,
                    isCurrentUser: true,
                    firstName: response.first_name,
                    lastName: response.last_name,
                    phoneNumber: response.phone_number,
                    email: response.email
                )
            })
            .store(in: &cancellables)
    }
    
    func updateUserProfile(name: String? = nil, bio: String? = nil, preferences: [String]? = nil,
                           profileImageData: Data? = nil,
                           firstName: String? = nil, lastName: String? = nil,
                           phoneNumber: String? = nil, email: String? = nil,
                           completion: ((Bool) -> Void)? = nil) {
        print("AppDataService: Updating user profile...")
        
        // Convert image data to base64 data URL if provided
        var profileImageURL: String? = nil
        if let imageData = profileImageData {
            profileImageURL = "data:image/jpeg;base64,\(imageData.base64EncodedString())"
        }
        
        APIService.shared.updateUserProfile(
            name: name,
            bio: bio,
            preferences: preferences,
            profileImageURL: profileImageURL,
            firstName: firstName,
            lastName: lastName,
            phoneNumber: phoneNumber,
            email: email
        )
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { completionStatus in
                if case .failure(let error) = completionStatus {
                    print("AppDataService: Error updating user profile: \(error)")
                    completion?(false)
                }
            }, receiveValue: { [weak self] response in
                guard let self = self else { return }
                print("AppDataService: Updated user profile")
                
                // Update current user with all fields
                let newProfileImageURL = response.profile_image_url.flatMap { URL(string: $0) }
                self.currentUser = User(
                    id: self.currentUser.id,
                    name: response.name,
                    avatarURL: self.currentUser.avatarURL,
                    profileImageURL: newProfileImageURL,
                    bio: response.bio,
                    preferences: response.preferences,
                    isCurrentUser: true,
                    firstName: response.first_name,
                    lastName: response.last_name,
                    phoneNumber: response.phone_number,
                    email: response.email
                )
                completion?(true)
            })
            .store(in: &cancellables)
    }
    
    // MARK: - Saved Locations (Persisted)
    
    func fetchSavedLocations() {
        print("AppDataService: Fetching saved locations...")
        APIService.shared.getSavedLocations()
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { completion in
                if case .failure(let error) = completion {
                    print("AppDataService: Error fetching saved locations: \(error)")
                }
            }, receiveValue: { [weak self] responses in
                let locations = responses.map { $0.toLocation() }
                print("AppDataService: Fetched \(locations.count) saved locations")
                self?.savedLocations = locations
            })
            .store(in: &cancellables)
    }
    
    // MARK: - AI Discoveries (Persisted)
    
    func fetchAIDiscoveries() {
        print("AppDataService: Fetching AI discoveries...")
        APIService.shared.getAIDiscoveries()
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { completion in
                if case .failure(let error) = completion {
                    print("AppDataService: Error fetching AI discoveries: \(error)")
                }
            }, receiveValue: { [weak self] responses in
                let locations = responses.map { $0.toLocation() }
                print("AppDataService: Fetched \(locations.count) AI discoveries")
                self?.aiSuggestedLocations = locations
                // Also populate business remarks
                for response in responses {
                    if let remark = response.ai_remark {
                        self?.businessRemarks[response.yelp_id] = remark
                    }
                }
            })
            .store(in: &cancellables)
    }
    
    func persistAIDiscovery(location: Location, aiRemark: String?, roomId: String?) {
        print("AppDataService: Persisting AI discovery: \(location.name)")
        APIService.shared.addAIDiscovery(location: location, aiRemark: aiRemark, roomId: roomId)
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { completion in
                if case .failure(let error) = completion {
                    print("AppDataService: Error persisting AI discovery: \(error)")
                }
            }, receiveValue: { [weak self] response in
                print("AppDataService: Persisted AI discovery: \(response.id)")
                // Add to local array if not already present
                if !(self?.aiSuggestedLocations.contains(where: { $0.yelpId == response.yelp_id }) ?? false) {
                    self?.aiSuggestedLocations.append(response.toLocation())
                }
            })
            .store(in: &cancellables)
    }
    
    // MARK: - Firestore Real-time Listener
    
    private func setupFirestoreListener(for roomId: String) {
        // Remove existing listener
        messageListener?.remove()
        
        print("Firestore: Setting up listener for room \(roomId)")
        print("Firestore: Current rooms in array: \(rooms.map { $0.id })")
        
        messageListener = db.collection("rooms").document(roomId).collection("messages")
            .order(by: "timestamp", descending: false)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else {
                    print("Firestore: Self is nil in listener callback")
                    return
                }
                
                if let error = error {
                    print("Firestore: Error listening to messages: \(error)")
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    print("Firestore: No documents found")
                    return
                }
                
                print("Firestore: Received \(documents.count) messages for room \(roomId)")
                
                // Find the room index
                guard let roomIndex = self.rooms.firstIndex(where: { $0.id == roomId }) else {
                    print("Firestore: Room \(roomId) not found in local array. Available rooms: \(self.rooms.map { $0.id })")
                    return
                }
                
                var newMessages: [Message] = []
                
                for doc in documents {
                    let data = doc.data()
                    
                    guard let senderId = data["senderId"] as? String,
                          let content = data["content"] as? String,
                          let timestamp = data["timestamp"] as? Timestamp else {
                        print("Firestore: Skipping message \(doc.documentID) - missing required fields. Data: \(data)")
                        continue
                    }
                    
                    let messageId = doc.documentID
                    let messageType = MessageType(rawValue: data["type"] as? String ?? "text") ?? .text
                    
                    // Parse businesses if present
                    var businesses: [YelpBusiness]? = nil
                    if let businessesData = data["businesses"] as? [[String: Any]] {
                        if let jsonData = try? JSONSerialization.data(withJSONObject: businessesData),
                           let decodedBusinesses = try? JSONDecoder().decode([YelpBusiness].self, from: jsonData) {
                            businesses = decodedBusinesses
                            print("Firestore: Decoded \(decodedBusinesses.count) businesses for message \(messageId)")
                            
                            // Store AI remark for each business and persist to server
                            if senderId == self.aiUser.id {
                                for business in decodedBusinesses {
                                    self.businessRemarks[business.id] = content
                                    
                                    var location = business.toLocation()
                                    location.aiRemark = content
                                    
                                    if !self.aiSuggestedLocations.contains(where: { $0.yelpId == business.id }) {
                                        self.aiSuggestedLocations.append(location)
                                        // Persist new AI discovery to server
                                        self.persistAIDiscovery(location: location, aiRemark: content, roomId: roomId)
                                    }
                                }
                            }
                        } else {
                            print("Firestore: Failed to decode businesses for message \(messageId)")
                        }
                    }
                    
                    let message = Message(
                        id: messageId,
                        senderId: senderId,
                        content: content,
                        timestamp: timestamp.dateValue(),
                        type: messageType,
                        businesses: businesses
                    )
                    
                    newMessages.append(message)
                }
                
                // Update the room's messages
                self.rooms[roomIndex].messages = newMessages
                self.objectWillChange.send()
                print("Firestore: Updated room \(roomId) with \(newMessages.count) messages")
            }
    }
    
    private func listenToTyping(for roomId: String) {
        db.collection("rooms").document(roomId).collection("typing")
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self, let documents = snapshot?.documents else { return }
                
                var typing = Set<String>()
                let now = Date()
                
                for doc in documents {
                    let data = doc.data()
                    if let isTyping = data["isTyping"] as? Bool,
                       let timestamp = data["timestamp"] as? Timestamp,
                       isTyping,
                       now.timeIntervalSince(timestamp.dateValue()) < 5 {
                        typing.insert(doc.documentID)
                    }
                }
                
                self.typingUsers = typing
                self.isAITyping = typing.contains(self.aiUser.id)
            }
    }
    
    func fetchRooms() {
        print("AppDataService: Fetching rooms for user \(currentUser.id)")
        
        let publicRooms = APIService.shared.getPublicRooms()
            .handleEvents(receiveCompletion: { completion in
                if case .failure(let error) = completion {
                    print("AppDataService: Error fetching public rooms: \(error)")
                }
            })
            .replaceError(with: [])
            
        let myRooms = APIService.shared.getMyRooms(userId: currentUser.id)
            .handleEvents(receiveCompletion: { completion in
                if case .failure(let error) = completion {
                    print("AppDataService: Error fetching my rooms: \(error)")
                }
            })
            .replaceError(with: [])
        
        Publishers.Zip(publicRooms, myRooms)
            .receive(on: DispatchQueue.main)
            .sink(receiveValue: { [weak self] publicR, myR in
                let allRooms = (publicR + myR).reduce(into: [Room]()) { result, room in
                    if !result.contains(where: { $0.id == room.id }) {
                        result.append(room)
                    }
                }
                print("AppDataService: Fetched \(allRooms.count) total unique rooms")
                allRooms.forEach { print(" - Room: \($0.name), ID: \($0.id)") }
                self?.rooms = allRooms
            })
            .store(in: &cancellables)
    }
    
    func getCurrentUser() -> User {
        return currentUser
    }
    
    func getRoom(id: String) -> AnyPublisher<Room, Error> {
        if let room = rooms.first(where: { $0.id == id }) {
            return Just(room).setFailureType(to: Error.self).eraseToAnyPublisher()
        }
        return Fail(error: NSError(domain: "RoomNotFound", code: 404, userInfo: nil)).eraseToAnyPublisher()
    }
    
    func sendMessage(content: String) {
        guard let roomId = currentRoomId else {
            print("AppDataService: Cannot send message - no current room ID")
            return
        }
        
        print("AppDataService: Sending message to room \(roomId): '\(content)'")
        
        // Stop typing indicator
        sendTypingIndicator(isTyping: false)
        
        // Call API to send message (handles AI processing, Yelp integration, etc.)
        // The API will write to Firestore, which triggers our listener
        print("AppDataService: Calling API to send message...")
        APIService.shared.sendMessage(roomId: roomId, senderId: currentUser.id, content: content)
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { completion in
                if case .failure(let error) = completion {
                    print("Error sending message: \(error)")
                }
            }, receiveValue: { sentMessage in
                print("AppDataService: Message sent successfully")
                // Firestore listener will automatically update the UI
            })
            .store(in: &cancellables)
    }
    
    private var typingTimer: Timer?
    
    func sendTypingIndicator(isTyping: Bool) {
        guard let roomId = currentRoomId else { return }
        
        // Update typing status in Firestore
        db.collection("rooms").document(roomId).collection("typing").document(currentUser.id).setData([
            "isTyping": isTyping,
            "timestamp": FieldValue.serverTimestamp(),
            "userName": currentUser.name
        ])
        
        // If starting to type, set up a timer to keep broadcasting
        if isTyping {
            typingTimer?.invalidate()
            typingTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
                guard let self = self, let roomId = self.currentRoomId else { return }
                self.db.collection("rooms").document(roomId).collection("typing").document(self.currentUser.id).setData([
                    "isTyping": true,
                    "timestamp": FieldValue.serverTimestamp(),
                    "userName": self.currentUser.name
                ])
            }
        } else {
            typingTimer?.invalidate()
            typingTimer = nil
        }
    }
    
    func connectToRoom(_ roomId: String) {
        // Skip if already connected to this room
        if currentRoomId == roomId && messageListener != nil {
            print("AppDataService: Already connected to room \(roomId)")
            return
        }
        
        print("AppDataService: Connecting to room \(roomId)")
        print("AppDataService: Room exists in array: \(rooms.contains { $0.id == roomId })")
        print("AppDataService: Total rooms in array: \(rooms.count)")
        
        // Note: AI suggestions and saved locations are now persisted globally per user
        // They don't get cleared when switching rooms
        
        currentRoomId = roomId
        
        // Set up Firestore real-time listener
        setupFirestoreListener(for: roomId)
        listenToTyping(for: roomId)
    }
    
    func disconnectFromRoom() {
        // Only disconnect, don't clear currentRoomId - this allows reconnection
        messageListener?.remove()
        messageListener = nil
        typingTimer?.invalidate()
        typingTimer = nil
    }
    
    /// Fully leave a room (called when user explicitly leaves)
    func leaveCurrentRoom() {
        disconnectFromRoom()
        currentRoomId = nil
    }
    
    func addItineraryItem(item: ItineraryItem) {
        // TODO: Implement API for itinerary
    }
    
    func createRoom(name: String, isPublic: Bool) {
        print("AppDataService: Creating room '\(name)'")
        APIService.shared.createRoom(name: name, isPublic: isPublic, ownerId: currentUser.id, ownerName: currentUser.name)
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { completion in
                if case .failure(let error) = completion {
                    print("AppDataService: Error creating room: \(error)")
                }
            }, receiveValue: { [weak self] room in
                print("AppDataService: Created room: \(room.name), ID: \(room.id)")
                self?.rooms.append(room)
                self?.currentRoomId = room.id
            })
            .store(in: &cancellables)
    }
    
    func joinRoom(code: String, completion: @escaping (Bool) -> Void) {
        APIService.shared.joinRoom(code: code, userId: currentUser.id, userName: currentUser.name)
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { completionStatus in
                if case .failure = completionStatus {
                    completion(false)
                }
            }, receiveValue: { [weak self] room in
                self?.rooms.append(room)
                self?.currentRoomId = room.id
                completion(true)
            })
            .store(in: &cancellables)
    }
    
    func deleteRoom(roomId: String, completion: @escaping (Bool) -> Void) {
        print("AppDataService: Deleting room \(roomId)")
        APIService.shared.deleteRoom(roomId: roomId)
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { completionStatus in
                if case .failure(let error) = completionStatus {
                    print("AppDataService: Error deleting room: \(error)")
                    completion(false)
                }
            }, receiveValue: { [weak self] _ in
                print("AppDataService: Successfully deleted room \(roomId)")
                self?.rooms.removeAll { $0.id == roomId }
                if self?.currentRoomId == roomId {
                    self?.currentRoomId = nil
                }
                completion(true)
            })
            .store(in: &cancellables)
    }
    
    func leaveRoom(roomId: String, completion: @escaping (Bool) -> Void) {
        print("AppDataService: Leaving room \(roomId)")
        APIService.shared.leaveRoom(roomId: roomId)
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { completionStatus in
                if case .failure(let error) = completionStatus {
                    print("AppDataService: Error leaving room: \(error)")
                    completion(false)
                }
            }, receiveValue: { [weak self] _ in
                print("AppDataService: Successfully left room \(roomId)")
                self?.rooms.removeAll { $0.id == roomId }
                if self?.currentRoomId == roomId {
                    self?.currentRoomId = nil
                }
                completion(true)
            })
            .store(in: &cancellables)
    }
    
    func isRoomOwner(room: Room) -> Bool {
        return room.ownerId == currentUser.id
    }
    
    func toggleFavorite(location: Location) {
        let yelpId = location.yelpId ?? "custom_\(location.name)_\(location.latitude)"
        
        if let index = savedLocations.firstIndex(where: { $0.yelpId == yelpId || $0 == location }) {
            // Remove from favorites
            savedLocations.remove(at: index)
            
            // Persist removal to API
            APIService.shared.unsaveLocation(yelpId: yelpId)
                .receive(on: DispatchQueue.main)
                .sink(receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        print("AppDataService: Error removing saved location: \(error)")
                    }
                }, receiveValue: { _ in
                    print("AppDataService: Removed saved location from server")
                })
                .store(in: &cancellables)
        } else {
            // Add to favorites (optimistic update)
            savedLocations.append(location)
            
            // Persist to API
            APIService.shared.saveLocation(location)
                .receive(on: DispatchQueue.main)
                .sink(receiveCompletion: { [weak self] completion in
                    if case .failure(let error) = completion {
                        print("AppDataService: Error saving location: \(error)")
                        // Rollback on failure
                        self?.savedLocations.removeAll { $0.yelpId == yelpId || $0 == location }
                    }
                }, receiveValue: { response in
                    print("AppDataService: Saved location to server: \(response.id)")
                })
                .store(in: &cancellables)
        }
    }
    
    func isFavorite(location: Location) -> Bool {
        let yelpId = location.yelpId ?? "custom_\(location.name)_\(location.latitude)"
        return savedLocations.contains(where: { $0.yelpId == yelpId || $0 == location })
    }
    
    // MARK: - Account Deletion
    
    /// Delete the current user's account and all associated server-side data.
    /// On success, local cached data is cleared. The caller is responsible for signing out.
    func deleteAccount(completion: @escaping (Bool) -> Void) {
        print("AppDataService: Deleting account for user \(currentUser.id)")
        
        APIService.shared.deleteAccount()
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { completionStatus in
                if case .failure(let error) = completionStatus {
                    print("AppDataService: Error deleting account: \(error)")
                    completion(false)
                }
            }, receiveValue: { [weak self] _ in
                print("AppDataService: Account deleted successfully")
                // Clear local state; auth listener will also reset when the caller signs out.
                self?.rooms = []
                self?.currentRoomId = nil
                self?.savedLocations = []
                self?.aiSuggestedLocations = []
                completion(true)
            })
            .store(in: &cancellables)
    }
}

// MARK: - Background Location Service
/// Handles location updates entirely on background thread - NO UI blocking
private class BackgroundLocationService: NSObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    private let backgroundQueue = DispatchQueue(label: "com.tastethreads.location.service", qos: .utility)
    
    override init() {
        super.init()
        backgroundQueue.async { [weak self] in
            self?.setupLocationManager()
        }
    }
    
    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager.distanceFilter = 500
        locationManager.allowsBackgroundLocationUpdates = false
        locationManager.pausesLocationUpdatesAutomatically = true
    }
    
    func startMonitoring() {
        backgroundQueue.async { [weak self] in
            if CLLocationManager.locationServicesEnabled() {
                self?.locationManager.startUpdatingLocation()
            }
        }
    }
    
    // CLLocationManagerDelegate - called on arbitrary thread
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        // Update cache async on background
        LocationContextCache.shared.updateAsync(from: location)
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Silently handle - location is optional context
        #if DEBUG
        print("BackgroundLocationService: \(error.localizedDescription)")
        #endif
    }
}
