import SwiftUI

struct ChatView: View {
    var body: some View {
        RoomListView()
    }
}

#Preview {
    ChatView()
        .environmentObject(AppState())
}
