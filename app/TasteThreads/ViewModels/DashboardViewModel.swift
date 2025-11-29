import Foundation
import MapKit
import Combine
import SwiftUI

class DashboardViewModel: ObservableObject {
    @Published var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.8003, longitude: -122.415), // SF default
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    )
    @Published var itineraryItems: [ItineraryItem] = []
    @Published var searchResults: [YelpBusiness] = []
    @Published var selectedItem: ItineraryItem?
    @Published var showList: Bool = false
    @Published var isSearching: Bool = false
    @Published var previewItem: ItineraryItem? // For displaying business from chat before adding to itinerary
    @Published var aiSuggestedItems: [ItineraryItem] = [] // AI-suggested businesses from chat
    
    private let dataService: AppDataService
    private let appState: AppState
    private let apiService = APIService.shared
    private var cancellables = Set<AnyCancellable>()
    
    init(dataService: AppDataService = .shared, appState: AppState) {
        self.dataService = dataService
        self.appState = appState // Initialize appState
        subscribeToData()
        
        // Listen for focus requests
        appState.$focusLocation
            .compactMap { $0 }
            .sink { [weak self] location in
                self?.focusOnLocation(location)
            }
            .store(in: &cancellables)
    }
    
    private func subscribeToData() {
        Publishers.CombineLatest(dataService.$rooms, dataService.$currentRoomId)
            .map { rooms, currentRoomId -> [ItineraryItem] in
                guard let id = currentRoomId, let room = rooms.first(where: { $0.id == id }) else {
                    return []
                }
                
                // Inject AI remarks
                return room.itinerary.map { item in
                    var newItem = item
                    if let yelpId = item.location.yelpId,
                       let remark = self.dataService.businessRemarks[yelpId] {
                        newItem.location.aiRemark = remark
                    }
                    return newItem
                }
            }
            .assign(to: \.itineraryItems, on: self)
            .store(in: &cancellables)
        
        // Subscribe to AI-suggested locations
        dataService.$aiSuggestedLocations
            .map { locations in
                locations.map { location in
                    ItineraryItem(
                        id: UUID().uuidString,
                        type: .main,
                        location: location,
                        time: nil,
                        notes: nil,
                        votes: 0,
                        isAISuggestion: true
                    )
                }
            }
            .assign(to: \.aiSuggestedItems, on: self)
            .store(in: &cancellables)
    }
    
    func searchBusinesses(query: String) {
        guard !query.isEmpty else {
            searchResults = []
            return
        }
        
        // Clear preview item when starting a new search
        previewItem = nil
        isSearching = true
        
        // Get current location from map center
        let latitude = region.center.latitude
        let longitude = region.center.longitude
        
        apiService.search(term: query, latitude: latitude, longitude: longitude)
            .sink(receiveCompletion: { [weak self] completion in
                self?.isSearching = false
                if case .failure(let error) = completion {
                    print("Search error: \(error)")
                }
            }, receiveValue: { [weak self] response in
                self?.searchResults = response.businesses
                print("Found \(response.businesses.count) businesses")
            })
            .store(in: &cancellables)
    }
    
    func selectBusiness(_ business: YelpBusiness) {
        // Convert YelpBusiness to Location and focus on it
        let location = business.toLocation()
        focusOnLocation(location)
    }
    
    private func focusOnLocation(_ location: Location) {
        // Check if already in itinerary
        if let existingItem = itineraryItems.first(where: { $0.location == location }) {
            previewItem = nil
            selectItem(existingItem)
        } else {
            // Create a preview item for display
            let item = ItineraryItem(
                id: UUID().uuidString,
                type: .main, // Default type
                location: location,
                time: Date(),
                notes: nil,
                votes: 0,
                isAISuggestion: true
            )
            previewItem = item
            selectItem(item)
        }
    }
    
    func selectItem(_ item: ItineraryItem) {
        selectedItem = item
        withAnimation {
            // Offset the center slightly South so the pin appears in the top half (above the sheet)
            // Latitude increases North. So we subtract from latitude to move the center South.
            let offset = 0.005 // Approx offset for the zoom level
            region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: item.location.latitude - offset, longitude: item.location.longitude),
                span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
            )
        }
    }
}
