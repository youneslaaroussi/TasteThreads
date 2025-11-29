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
    
    // Computed properties for room filtering
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
            List {
                // My Rooms Section
                Section(header: Text("My Rooms")) {
                    if myRooms.isEmpty {
                        Text("No rooms found")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(myRooms) { room in
                            Button {
                                dataService.currentRoomId = room.id
                                navigationPath.append("chatRoom")
                            } label: {
                                RoomRow(room: room, isOwner: dataService.isRoomOwner(room: room))
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
                        }
                    }
                }
                
                // Public Rooms Section
                if !publicRooms.isEmpty {
                    Section(header: Text("Public Rooms")) {
                        ForEach(publicRooms) { room in
                            Button {
                                dataService.currentRoomId = room.id
                                navigationPath.append("chatRoom")
                            } label: {
                                RoomRow(room: room, isOwner: false)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .refreshable {
                print("RoomListView: Refreshing rooms...")
                dataService.fetchRooms()
            }
            .navigationDestination(for: String.self) { destination in
                if destination == "chatRoom" {
                    ChatRoomView()
                }
            }
            .onAppear {
                print("RoomListView: appeared. Current User ID: \(dataService.currentUser.id)")
                print("RoomListView: All Rooms Count: \(dataService.rooms.count)")
                let myRooms = dataService.rooms.filter { $0.members.contains(where: { $0.id == dataService.currentUser.id }) }
                print("RoomListView: My Rooms Count: \(myRooms.count)")
                
                // Handle pending navigation from LocationDetailView mention
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
                            .font(.title2)
                            .foregroundStyle(.primary)
                    }
                }
            }
            .sheet(isPresented: $showCreateRoom) {
                NavigationView {
                    Form {
                        TextField("Room Name", text: $newRoomName)
                        Toggle("Public Room", isOn: $isPublic)
                    }
                    .navigationTitle("New Room")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { showCreateRoom = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Create") {
                                dataService.createRoom(name: newRoomName, isPublic: isPublic)
                                showCreateRoom = false
                                newRoomName = ""
                                isPublic = false
                            }
                            .disabled(newRoomName.isEmpty)
                        }
                    }
                }
                .presentationDetents([.medium])
            }
            .alert("Join Room", isPresented: $showJoinRoom) {
                TextField("Enter 6-digit code", text: $joinCode)
                Button("Join") {
                    dataService.joinRoom(code: joinCode) { success in
                        if success {
                            joinCode = ""
                        } else {
                            // TODO: Show error
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
        
        // Set the current room and navigate
        dataService.currentRoomId = roomId
        appState.clearPendingNavigation()
        
        // Small delay to ensure state is updated before navigation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            navigationPath.append("chatRoom")
        }
    }
}

struct RoomRow: View {
    let room: Room
    var isOwner: Bool = false
    
    var body: some View {
        HStack {
            ZStack {
                Circle()
                    .fill(isOwner ? Color(red: 0.4, green: 0.3, blue: 0.9).opacity(0.15) : Color.blue.opacity(0.1))
                    .frame(width: 48, height: 48)
                
                Text(String(room.name.prefix(1)))
                    .font(.headline)
                    .foregroundStyle(isOwner ? Color(red: 0.4, green: 0.3, blue: 0.9) : .blue)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(room.name)
                        .font(.headline)
                    
                    if isOwner {
                        Text("Owner")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(red: 0.4, green: 0.3, blue: 0.9))
                            .clipShape(Capsule())
                    }
                }
                
                HStack(spacing: 4) {
                    if room.isPublic {
                        Image(systemName: "globe")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text("\(room.members.count) members")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            if let lastMsg = room.messages.last {
                Text(lastMsg.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    RoomListView()
        .environmentObject(AppState())
}
