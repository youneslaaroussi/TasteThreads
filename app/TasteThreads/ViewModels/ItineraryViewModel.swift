import Foundation
import Combine
import SwiftUI

class ItineraryViewModel: ObservableObject {
    @Published var itinerary: [ItineraryItem] = []
    
    private let dataService: AppDataService
    private var cancellables = Set<AnyCancellable>()
    
    init(dataService: AppDataService = .shared) {
        self.dataService = dataService
        subscribeToRoom()
    }
    
    private func subscribeToRoom() {
        Publishers.CombineLatest(dataService.$rooms, dataService.$currentRoomId)
            .map { rooms, currentRoomId -> [ItineraryItem] in
                guard let id = currentRoomId, let room = rooms.first(where: { $0.id == id }) else {
                    return []
                }
                return room.itinerary
            }
            .assign(to: \.itinerary, on: self)
            .store(in: &cancellables)
    }
    
    func moveItem(from source: IndexSet, to destination: Int) {
        // In a real app, we'd call the service to update the backend.
        // For now, we'll just update the local model via the service (if we added a method for it)
        // or directly modify the published property if it was a two-way binding, 
        // but since we are observing the service, we should update the service.
        
        // Let's add a reorder method to AppDataService or handle it locally for now.
        // Since AppDataService owns the source of truth:
        guard let roomId = dataService.currentRoomId,
              let index = dataService.rooms.firstIndex(where: { $0.id == roomId }) else { return }
        
        var currentItems = dataService.rooms[index].itinerary
        currentItems.move(fromOffsets: source, toOffset: destination)
        dataService.rooms[index].itinerary = currentItems
    }
    
    func deleteItem(at offsets: IndexSet) {
        guard let roomId = dataService.currentRoomId,
              let index = dataService.rooms.firstIndex(where: { $0.id == roomId }) else { return }
              
        var currentItems = dataService.rooms[index].itinerary
        currentItems.remove(atOffsets: offsets)
        dataService.rooms[index].itinerary = currentItems
    }
}
