import SwiftUI

struct RoomListView: View {
    @ObservedObject private var dataService = AppDataService.shared
    @EnvironmentObject var appState: AppState
    @State private var showCreateRoom = false
    @State private var showJoinRoom = false
    @State private var newRoomName = ""
    @State private var isPublic = false
    @State private var joinCode = ""
    @State private var roomToDelete: Room?
    @State private var showDeleteConfirmation = false
    @State private var deleteError: String?
    @State private var showDeleteError = false
    @State private var navigationPath = NavigationPath()
    
    // Warm theme colors
    private let warmAccent = Color(red: 0.76, green: 0.42, blue: 0.32)
    private let warmBackground = Color(red: 0.98, green: 0.96, blue: 0.93)
    
    private var myRooms: [Room] {
        dataService.rooms.filter { room in
            room.members.contains(where: { $0.id == dataService.currentUser.id })
        }
    }
    
    private var publicRooms: [Room] {
        dataService.rooms.filter { room in
            room.isPublic && !room.members.contains(where: { $0.id == dataService.currentUser.id })
        }
    }
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
            ScrollView {
                VStack(spacing: 24) {
                        // My Rooms Section
                        VStack(alignment: .leading, spacing: 12) {
                            Text("MY ROOMS")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.black.opacity(0.4))
                                .padding(.horizontal, 4)
                            
                            if myRooms.isEmpty {
                                VStack(spacing: 12) {
                                    Image(systemName: "bubble.left.and.bubble.right")
                                        .font(.system(size: 32))
                                        .foregroundColor(warmAccent.opacity(0.4))
                                    Text("No rooms yet")
                                        .font(.system(size: 15))
                                        .foregroundColor(.black.opacity(0.5))
                                    Text("Create or join a room to start chatting")
                                        .font(.system(size: 13))
                                        .foregroundColor(.black.opacity(0.4))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 32)
                                .background(Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            } else {
                                VStack(spacing: 0) {
                                    ForEach(myRooms) { room in
                                        Button {
                                            dataService.currentRoomId = room.id
                                            navigationPath.append("chatRoom")
                                        } label: {
                                            RoomRow(room: room, isOwner: dataService.isRoomOwner(room: room), accent: warmAccent)
                                        }
                                        .buttonStyle(.plain)
                                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                            if dataService.isRoomOwner(room: room) {
                                                Button(role: .destructive) {
                                                    roomToDelete = room
                                                    showDeleteConfirmation = true
                                                } label: {
                                                    Label("Delete", systemImage: "trash")
                                                }
                                            } else {
                                                Button(role: .destructive) {
                                                    roomToDelete = room
                                                    showDeleteConfirmation = true
                                                } label: {
                                                    Label("Leave", systemImage: "rectangle.portrait.and.arrow.right")
                                                }
                                            }
                                        }
                                        
                                        if room.id != myRooms.last?.id {
                                            Divider().padding(.leading, 72)
                                        }
                                    }
                                }
                                .background(Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }
                        
                        // Public Rooms Section
                        if !publicRooms.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("PUBLIC ROOMS")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.black.opacity(0.4))
                                    .padding(.horizontal, 4)
                                
                                VStack(spacing: 0) {
                                    ForEach(publicRooms) { room in
                                        Button {
                                            dataService.currentRoomId = room.id
                                            navigationPath.append("chatRoom")
                                        } label: {
                                            RoomRow(room: room, isOwner: false, accent: warmAccent)
                                        }
                                        .buttonStyle(.plain)
                                        
                                        if room.id != publicRooms.last?.id {
                                            Divider().padding(.leading, 72)
                                        }
                                    }
                                }
                                .background(Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }
                    }
                    .padding(16)
                }
            .background(warmBackground)
            .refreshable {
                dataService.fetchRooms()
            }
            .navigationDestination(for: String.self) { destination in
                if destination == "chatRoom" {
                    ChatRoomView()
                }
            }
            .onAppear {
                handlePendingNavigation()
            }
            .onChange(of: appState.shouldNavigateToRoom) { _, shouldNavigate in
                if shouldNavigate {
                    handlePendingNavigation()
                }
            }
            .navigationTitle("Rooms")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(action: { showCreateRoom = true }) {
                            Label("Create Room", systemImage: "plus")
                        }
                        Button(action: { showJoinRoom = true }) {
                            Label("Join with Code", systemImage: "qrcode")
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(warmAccent)
                    }
                }
            }
            .sheet(isPresented: $showCreateRoom) {
                CreateRoomSheet(
                    roomName: $newRoomName,
                    isPublic: $isPublic,
                    accent: warmAccent,
                    onCreate: {
                        dataService.createRoom(name: newRoomName, isPublic: isPublic)
                        showCreateRoom = false
                        newRoomName = ""
                        isPublic = false
                    },
                    onCancel: {
                        showCreateRoom = false
                    }
                )
                .presentationDetents([.medium])
            }
            .alert("Join Room", isPresented: $showJoinRoom) {
                TextField("Enter 6-digit code", text: $joinCode)
                Button("Join") {
                    dataService.joinRoom(code: joinCode) { success in
                        if success {
                            joinCode = ""
                        }
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Ask your friend for the invite code.")
            }
            .confirmationDialog(
                roomToDelete.map { dataService.isRoomOwner(room: $0) ? "Delete \"\($0.name)\"?" : "Leave \"\($0.name)\"?" } ?? "Confirm",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                if let room = roomToDelete {
                    if dataService.isRoomOwner(room: room) {
                        Button("Delete Room", role: .destructive) {
                            dataService.deleteRoom(roomId: room.id) { success in
                                if !success {
                                    deleteError = "Failed to delete room. Please try again."
                                    showDeleteError = true
                                }
                                roomToDelete = nil
                            }
                        }
                    } else {
                        Button("Leave Room", role: .destructive) {
                            dataService.leaveRoom(roomId: room.id) { success in
                                if !success {
                                    deleteError = "Failed to leave room. Please try again."
                                    showDeleteError = true
                                }
                                roomToDelete = nil
                            }
                        }
                    }
                }
                Button("Cancel", role: .cancel) {
                    roomToDelete = nil
                }
            } message: {
                if let room = roomToDelete {
                    if dataService.isRoomOwner(room: room) {
                        Text("This will permanently delete the room and all messages for everyone.")
                    } else {
                        Text("You will no longer see messages from this room.")
                    }
                }
            }
            .alert("Error", isPresented: $showDeleteError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(deleteError ?? "An error occurred")
            }
        }
    }
    
    private func handlePendingNavigation() {
        guard appState.shouldNavigateToRoom,
              let roomId = appState.pendingRoomId,
              dataService.rooms.contains(where: { $0.id == roomId }) else {
            return
        }
        
        dataService.currentRoomId = roomId
        appState.clearPendingNavigation()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            navigationPath.append("chatRoom")
        }
    }
}

// MARK: - Create Room Sheet
struct CreateRoomSheet: View {
    @Binding var roomName: String
    @Binding var isPublic: Bool
    let accent: Color
    let onCreate: () -> Void
    let onCancel: () -> Void
    
    private let warmBackground = Color(red: 0.98, green: 0.96, blue: 0.93)
    
    var body: some View {
        NavigationView {
            ZStack {
                warmBackground.ignoresSafeArea()
                
                VStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Room Name")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.black.opacity(0.5))
                        
                        TextField("e.g. Friday Dinner Plans", text: $roomName)
                            .font(.system(size: 16))
                            .padding(16)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
                    }
                    
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Public Room")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(.black)
                            Text("Anyone can find and join")
                                .font(.system(size: 13))
                                .foregroundColor(.black.opacity(0.5))
                        }
                        
                        Spacer()
                        
                        Toggle("", isOn: $isPublic)
                            .tint(accent)
                    }
                    .padding(16)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    
                    Spacer()
                }
                .padding(20)
            }
            .navigationTitle("New Room")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                        .foregroundColor(accent)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { onCreate() }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(roomName.isEmpty ? .black.opacity(0.3) : accent)
                        .disabled(roomName.isEmpty)
                }
            }
        }
    }
}

struct RoomRow: View {
    let room: Room
    var isOwner: Bool = false
    var accent: Color = Color(red: 0.76, green: 0.42, blue: 0.32)
    
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(accent.opacity(0.12))
                    .frame(width: 48, height: 48)
                
                Text(String(room.name.prefix(1)))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(accent)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(room.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.black)
                    
                    if isOwner {
                        Text("Owner")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(accent)
                            .clipShape(Capsule())
                    }
                }
                
                HStack(spacing: 4) {
                    Image(systemName: room.isPublic ? "globe" : "lock.fill")
                        .font(.system(size: 11))
                    Text("\(room.members.count) members")
                        .font(.system(size: 13))
                }
                .foregroundColor(.black.opacity(0.5))
            }
            
            Spacer()
            
            if let lastMsg = room.messages.last {
                Text(lastMsg.timestamp, style: .time)
                    .font(.system(size: 12))
                    .foregroundColor(.black.opacity(0.4))
            }
            
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.black.opacity(0.3))
        }
        .padding(14)
    }
}

#Preview {
    RoomListView()
        .environmentObject(AppState())
}
