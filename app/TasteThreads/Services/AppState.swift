import SwiftUI
import Combine

enum Tab: String {
    case map
    case chat
    case profile
}

class AppState: ObservableObject {
    @Published var selectedTab: Tab = .map
    @Published var chatDraft: String = ""
    @Published var focusLocation: Location? = nil
    @Published var pendingRoomId: String? = nil  // Room to auto-navigate to
    @Published var shouldNavigateToRoom: Bool = false
    
    func navigateToChat(withMention name: String) {
        chatDraft = "@\(name) "
        selectedTab = .chat
    }
    
    /// Navigate to a specific chat room with a business mention
    func navigateToChatRoom(roomId: String, businessName: String) {
        chatDraft = "@\(businessName) "
        pendingRoomId = roomId
        shouldNavigateToRoom = true
        selectedTab = .chat
    }
    
    /// Clear pending navigation after it's handled
    func clearPendingNavigation() {
        pendingRoomId = nil
        shouldNavigateToRoom = false
    }
    
    func navigateToMap(location: Location) {
        focusLocation = location
        selectedTab = .map
    }
}
