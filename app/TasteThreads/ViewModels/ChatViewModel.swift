import Foundation
import Combine

class ChatViewModel: ObservableObject {
    @Published var messages: [Message] = []
    @Published var newMessageText: String = ""
    @Published var isAITyping: Bool = false
    @Published var errorMessage: String?
    @Published var isLoading: Bool = true
    @Published var isConnected: Bool = false
    
    private let dataService: AppDataService
    private let apiService: APIService
    private var cancellables = Set<AnyCancellable>()
    private var currentChatId: String?
    
    init(dataService: AppDataService = .shared, apiService: APIService = .shared) {
        self.dataService = dataService
        self.apiService = apiService
        subscribeToRoom()
    }
    
    private func subscribeToRoom() {
        // Subscribe to rooms and currentRoomId to find the active room's messages
        Publishers.CombineLatest(dataService.$rooms, dataService.$currentRoomId)
            .receive(on: DispatchQueue.main)
            .map { [weak self] rooms, currentRoomId -> [Message] in
                guard let id = currentRoomId, let room = rooms.first(where: { $0.id == id }) else {
                    return []
                }
                // Mark as loaded once we have room data
                DispatchQueue.main.async {
                    self?.isLoading = false
                    self?.isConnected = true
                }
                return room.messages
            }
            .assign(to: \.messages, on: self)
            .store(in: &cancellables)
            
        dataService.$isAITyping
            .assign(to: \.isAITyping, on: self)
            .store(in: &cancellables)
    }
    
    /// Connect to room in background
    func connectToRoom() {
        guard let roomId = dataService.currentRoomId else { return }
        
        isLoading = true
        
        // Connect on background queue to avoid UI blocking
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            DispatchQueue.main.async {
                self?.dataService.connectToRoom(roomId)
            }
        }
    }
    
    func sendMessage(content: String? = nil) {
        let textToSend = content ?? newMessageText
        guard !textToSend.isEmpty else { return }
        
        // Send message to room via API
        // Backend will handle AI triggering
        dataService.sendMessage(content: textToSend)
        newMessageText = ""
    }
    
    func isCurrentUser(userId: String) -> Bool {
        return dataService.currentUser.id == userId
    }
    
    func getUser(userId: String) -> User? {
        if userId == dataService.currentUser.id { return dataService.currentUser }
        if userId == dataService.aiUser.id { return dataService.aiUser }
        guard let roomId = dataService.currentRoomId,
              let room = dataService.rooms.first(where: { $0.id == roomId }) else { return nil }
        return room.members.first(where: { $0.id == userId })
    }
    
    func getItem(id: String?) -> ItineraryItem? {
        guard let id = id,
              let roomId = dataService.currentRoomId,
              let room = dataService.rooms.first(where: { $0.id == roomId }) else { return nil }
        return room.itinerary.first(where: { $0.id == id })
    }
    
    func selectBusiness(_ business: YelpBusiness, completion: @escaping (Location) -> Void) {
        apiService.getBusinessDetails(id: business.id)
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { [weak self] completionStatus in
                if case .failure(let error) = completionStatus {
                    print("Error fetching details: \(error)")
                    // Fallback to basic info if fetch fails
                    var fallbackLocation = business.toLocation()
                    // Add AI remark even on fallback
                    fallbackLocation.aiRemark = self?.dataService.businessRemarks[business.id]
                    completion(fallbackLocation)
                }
            }, receiveValue: { details in
                var location = business.toLocation()
                
                // Format hours
                let formattedHours = details.hours?.first?.open.map { openHour -> String in
                    let days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
                    let day = days[openHour.day]
                    let start = self.formatTime(openHour.start)
                    let end = self.formatTime(openHour.end)
                    return "\(day): \(start) - \(end)"
                }
                
                // Calculate closing time
                var closingTime = ""
                if let hours = details.hours?.first?.open {
                    let weekday = Calendar.current.component(.weekday, from: Date())
                    // Convert Swift weekday (1=Sun...7=Sat) to Yelp (0=Mon...6=Sun)
                    let yelpDay = (weekday + 5) % 7
                    
                    if let todayHours = hours.first(where: { $0.day == yelpDay }) {
                        closingTime = self.formatTime(todayHours.end)
                    }
                }

                let enrichedDetails = YelpDetails(
                    price: location.yelpDetails?.price ?? "",
                    reviewCount: location.yelpDetails?.reviewCount ?? 0,
                    categories: location.yelpDetails?.categories ?? [],
                    isOpen: details.hours?.first?.is_open_now ?? true,
                    closingTime: closingTime,
                    phoneNumber: location.yelpDetails?.phoneNumber ?? "",
                    url: location.yelpDetails?.url,
                    popularDishes: [],
                    aiSummary: location.yelpDetails?.aiSummary,
                    photos: details.photos,
                    hours: formattedHours
                )
                
                // Add AI remark if available
                let aiRemark = self.dataService.businessRemarks[business.id]
                
                let enrichedLocation = Location(
                    name: location.name,
                    address: location.address,
                    latitude: location.latitude,
                    longitude: location.longitude,
                    rating: location.rating,
                    imageURL: location.imageURL,
                    yelpDetails: enrichedDetails,
                    aiRemark: aiRemark,
                    yelpId: business.id
                )
                
                print("ChatViewModel: Selected business with AI remark: \(aiRemark ?? "none")")
                completion(enrichedLocation)
            })
            .store(in: &cancellables)
    }
    
    private func formatTime(_ time: String) -> String {
        guard time.count == 4 else { return time }
        let hour = time.prefix(2)
        let minute = time.suffix(2)
        return "\(hour):\(minute)"
    }
}
