import SwiftUI

struct ChatRoomView: View {
    @StateObject private var viewModel = ChatViewModel()
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    @Environment(\.openURL) var openURL
    @FocusState private var isFocused: Bool
    @State private var showRoomInfo = false
    @State private var hasAppliedDraft = false
    
    // Warm theme colors
    private let warmAccent = Color(red: 0.76, green: 0.42, blue: 0.32)
    private let warmBackground = Color(red: 0.98, green: 0.96, blue: 0.93)
    
    private var currentRoom: Room? {
        AppDataService.shared.currentRoom
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.black)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(currentRoom?.name ?? "Group Chat")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.black)
                    if let room = currentRoom {
                        Text("\(room.members.count) members")
                            .font(.system(size: 13))
                            .foregroundColor(.black.opacity(0.5))
                    }
                }
                
                Spacer()
                
                // Invite to WhatsApp button
                Button(action: {
                    if let url = URL(string: "whatsapp://") {
                        openURL(url)
                    }
                }) {
                    Image(systemName: "phone.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 32, height: 32)
                        .background(Color(red: 0.09, green: 0.73, blue: 0.36))
                        .clipShape(Circle())
                }
                .padding(.trailing, 6)
                
                Button(action: { showRoomInfo = true }) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 20))
                        .foregroundColor(.black.opacity(0.5))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.white)
            .shadow(color: .black.opacity(0.04), radius: 2, y: 2)
            
            // Messages List
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if viewModel.isLoading && viewModel.messages.isEmpty {
                            ForEach(0..<5, id: \.self) { index in
                                MessageSkeletonView(isLeft: index % 2 == 0)
                            }
                        } else {
                            ForEach(viewModel.messages) { message in
                                if message.type == .system {
                                    Text(message.content)
                                        .font(.system(size: 13))
                                        .foregroundColor(.black.opacity(0.4))
                                        .padding(.vertical, 4)
                                } else {
                                    MessageBubble(
                                        message: message,
                                        isCurrentUser: viewModel.isCurrentUser(userId: message.senderId),
                                        user: viewModel.getUser(userId: message.senderId),
                                        relatedItem: viewModel.getItem(id: message.relatedItemId),
                                        onBusinessSelected: { business in
                                            viewModel.selectBusiness(business) { location in
                                                appState.navigateToMap(location: location)
                                            }
                                        }
                                    )
                                    .id(message.id)
                                }
                            }
                        }
                        
                        let otherTypingUsers = AppDataService.shared.typingUsers.filter { $0 != AppDataService.shared.currentUser.id }
                        
                        if !otherTypingUsers.isEmpty {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    let typingUserNames = otherTypingUsers.compactMap { userId in
                                        viewModel.getUser(userId: userId)?.name
                                    }.joined(separator: ", ")
                                    
                                    if !typingUserNames.isEmpty {
                                        Text("\(typingUserNames) \(otherTypingUsers.count == 1 ? "is" : "are") typing...")
                                            .font(.system(size: 13))
                                            .foregroundColor(.black.opacity(0.4))
                                    }
                                    TypingIndicatorView()
                                }
                                Spacer()
                            }
                            .transition(.opacity)
                            .id("typingIndicator")
                        }
                    }
                    .padding(16)
                }
                .background(warmBackground)
                .onChange(of: viewModel.messages) {
                    scrollToBottom(proxy: proxy)
                }
                .onChange(of: AppDataService.shared.typingUsers) {
                    if !AppDataService.shared.typingUsers.isEmpty {
                        withAnimation {
                            proxy.scrollTo("typingIndicator", anchor: .bottom)
                        }
                    } else {
                        scrollToBottom(proxy: proxy)
                    }
                }
            }
            
            // Quick Replies
            if let lastMessage = viewModel.messages.last, let replies = lastMessage.quickReplies, !replies.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(replies, id: \.self) { reply in
                            Button(action: { viewModel.sendMessage(content: reply) }) {
                                Text(reply)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(warmAccent)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(warmAccent.opacity(0.1))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                .background(Color.white)
            }
            
            // Input Area
            HStack(spacing: 12) {
                AIHighlightTextField(
                    text: $viewModel.newMessageText,
                    placeholder: "Type a message... @Tess for suggestions",
                    isFocused: $isFocused,
                    accent: warmAccent
                )
                .onChange(of: viewModel.newMessageText) { oldValue, newValue in
                    if !newValue.isEmpty && oldValue.isEmpty {
                        AppDataService.shared.sendTypingIndicator(isTyping: true)
                    } else if newValue.isEmpty && !oldValue.isEmpty {
                        AppDataService.shared.sendTypingIndicator(isTyping: false)
                    }
                }
                
                Button(action: { viewModel.sendMessage() }) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(viewModel.newMessageText.isEmpty ? .black.opacity(0.2) : warmAccent)
                }
                .disabled(viewModel.newMessageText.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.white)
            .shadow(color: .black.opacity(0.04), radius: 2, y: -2)
        }
        .background(warmBackground)
        .onTapGesture {
            isFocused = false
        }
        .task {
            viewModel.connectToRoom()
            
            // Apply chat draft only once
            if !hasAppliedDraft && !appState.chatDraft.isEmpty {
                hasAppliedDraft = true
                let draft = appState.chatDraft
                appState.chatDraft = ""
                
                // Small delay to ensure view is fully loaded
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                await MainActor.run {
                    viewModel.newMessageText = draft
                    isFocused = true
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .alert("Error", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { _ in viewModel.errorMessage = nil }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .sheet(isPresented: $showRoomInfo) {
            RoomInfoSheet(room: currentRoom, onRoomDeleted: {
                // Dismiss the sheet first
                showRoomInfo = false
                // Then dismiss the chat room view to go back to room list
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    dismiss()
                }
            })
                .presentationDetents([.medium])
        }
    }
    
    private func scrollToBottom(proxy: ScrollViewProxy) {
        if let lastMessage = viewModel.messages.last {
            withAnimation {
                proxy.scrollTo(lastMessage.id, anchor: .bottom)
            }
        }
    }
}

// MARK: - Message Skeleton Loading View
struct MessageSkeletonView: View {
    let isLeft: Bool
    @State private var isAnimating = false
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isLeft {
                Circle()
                    .fill(Color.black.opacity(0.08))
                    .frame(width: 32, height: 32)
            } else {
                Spacer()
            }
            
            VStack(alignment: isLeft ? .leading : .trailing, spacing: 4) {
                if isLeft {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.black.opacity(0.08))
                        .frame(width: 60, height: 10)
                        .padding(.leading, 4)
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.black.opacity(0.08))
                        .frame(width: isLeft ? 180 : 150, height: 12)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.black.opacity(0.08))
                        .frame(width: isLeft ? 140 : 120, height: 12)
                    
                    if isLeft {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.black.opacity(0.08))
                            .frame(width: 100, height: 12)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 18))
            }
            
            if isLeft {
                Spacer()
            }
        }
        .opacity(isAnimating ? 0.5 : 1.0)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
    }
}

struct MessageBubble: View {
    let message: Message
    let isCurrentUser: Bool
    let user: User?
    var relatedItem: ItineraryItem? = nil
    var onBusinessSelected: ((YelpBusiness) -> Void)? = nil
    var onReservationAction: ((ReservationAction, ReservationTimeSlot?) -> Void)? = nil
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var dataService: AppDataService
    @State private var showDetails = false
    @State private var showReservationSheet = false
    @State private var selectedReservationAction: ReservationAction?
    
    private let warmAccent = Color(red: 0.76, green: 0.42, blue: 0.32)
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if !isCurrentUser {
                AvatarView(user: user, size: 32)
            } else {
                Spacer()
            }
            
            VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: 4) {
                VStack(alignment: .leading, spacing: 8) {
                    HighlightedMessageText(text: message.content, isCurrentUser: isCurrentUser)
                    
                    if message.type == .map, let location = message.mapCoordinates {
                        MapMessageBubble(location: location) {
                            appState.navigateToMap(location: location)
                        }
                    } else if let item = relatedItem {
                        MiniItineraryCard(item: item)
                    }
                    
                    if let businesses = message.businesses, !businesses.isEmpty {
                        BusinessCarousel(businesses: businesses) { business in
                            onBusinessSelected?(business)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(isCurrentUser ? warmAccent : Color.white)
                .foregroundStyle(isCurrentUser ? .white : .primary)
                .clipShape(
                    .rect(
                        topLeadingRadius: 18,
                        bottomLeadingRadius: isCurrentUser ? 18 : 4,
                        bottomTrailingRadius: isCurrentUser ? 4 : 18,
                        topTrailingRadius: 18
                    )
                )
                .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
                .contextMenu {
                    Button {
                        UIPasteboard.general.string = message.content
                    } label: {
                        Label("Copy message", systemImage: "doc.on.doc")
                    }
                    
                    Button {
                        showDetails = true
                    } label: {
                        Label("Show details", systemImage: "info.circle")
                    }
                }
                .alert("Message Details", isPresented: $showDetails) {
                    Button("OK", role: .cancel) { }
                } message: {
                    Text(
                        """
                        From: \(user?.name ?? "Unknown")
                        At: \(message.timestamp.formatted(date: .omitted, time: .shortened))

                        \(message.content)
                        """
                    )
                }
                
                // Reservation Actions
                if let actions = message.actions {
                    ForEach(actions) { action in
                        switch action.type {
                        case .reservationPrompt:
                            ReservationCard(
                                action: action,
                                onSelectTime: { slot in
                                    selectedReservationAction = action
                                    showReservationSheet = true
                                },
                                onMoreOptions: {
                                    selectedReservationAction = action
                                    showReservationSheet = true
                                }
                            )
                            .padding(.top, 8)
                            
                        case .reservationConfirmed:
                            ReservationConfirmationCard(action: action)
                                .padding(.top, 8)
                        }
                    }
                }
                
                // Timestamp and username
                HStack(spacing: 4) {
                    if !isCurrentUser, let name = user?.name {
                        Text(name)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.black.opacity(0.4))
                        
                        Text("·")
                            .font(.system(size: 11))
                            .foregroundColor(.black.opacity(0.3))
                    }
                    
                    Text(message.timestamp, style: .time)
                        .font(.system(size: 11))
                        .foregroundColor(.black.opacity(0.4))
                }
                .padding(isCurrentUser ? .trailing : .leading, 4)
            }
            
            if !isCurrentUser {
                Spacer()
            }
        }
        .sheet(isPresented: $showReservationSheet) {
            if let action = selectedReservationAction {
                ReservationSheet(
                    action: action,
                    userProfile: dataService.currentUser,
                    onConfirm: { details in
                        handleReservationConfirm(details: details)
                    }
                )
            }
        }
    }
    
    private func handleReservationConfirm(details: ReservationBookingDetails) {
        showReservationSheet = false
        
        if let action = selectedReservationAction {
            let slot = ReservationTimeSlot(date: details.date, time: details.time)
            onReservationAction?(action, slot)
        }
    }
}

struct BusinessCarousel: View {
    let businesses: [YelpBusiness]
    let onSelect: (YelpBusiness) -> Void
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(businesses) { business in
                    BusinessCardView(business: business)
                        .onTapGesture {
                            onSelect(business)
                        }
                }
            }
            .padding(.top, 8)
        }
    }
}

struct BusinessCardView: View {
    let business: YelpBusiness
    
    private let warmBackground = Color(red: 0.98, green: 0.96, blue: 0.93)
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let imageUrlString = business.contextual_info?.photos?.first?.original_url ?? business.image_url,
               let url = URL(string: imageUrlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure:
                        ZStack {
                            Rectangle().fill(warmBackground)
                            Image(systemName: "photo")
                                .foregroundColor(.black.opacity(0.2))
                        }
                    case .empty:
                        ZStack {
                            Rectangle().fill(warmBackground)
                            ProgressView()
                                .tint(.black.opacity(0.3))
                        }
                    @unknown default:
                        Rectangle().fill(warmBackground)
                    }
                }
                .frame(width: 200, height: 120)
                .clipped()
            } else {
                ZStack {
                    Rectangle().fill(warmBackground)
                    Image(systemName: "photo")
                        .foregroundColor(.black.opacity(0.2))
                }
                .frame(width: 200, height: 120)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(business.name)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                    .foregroundColor(.black)
                
                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.orange)
                    Text(String(format: "%.1f", business.rating))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.black)
                    Text("(\(business.review_count))")
                        .font(.system(size: 12))
                        .foregroundColor(.black.opacity(0.5))
                }
                
                HStack {
                    Text(business.categories?.first?.title ?? "Restaurant")
                    Spacer()
                    Text(business.price ?? "")
                }
                .font(.system(size: 12))
                .foregroundColor(.black.opacity(0.5))
            }
            .padding(10)
            .background(Color.white)
        }
        .frame(width: 200)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
    }
}

struct MapMessageBubble: View {
    let location: Location
    let action: () -> Void
    
    private let warmAccent = Color(red: 0.76, green: 0.42, blue: 0.32)
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                Rectangle()
                    .fill(warmAccent.opacity(0.1))
                    .frame(height: 100)
                    .overlay(
                        Image(systemName: "map.fill")
                            .font(.system(size: 32))
                            .foregroundColor(warmAccent.opacity(0.5))
                    )
                
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(location.name)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.black)
                        Text(location.address)
                            .font(.system(size: 12))
                            .foregroundColor(.black.opacity(0.5))
                            .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.black.opacity(0.3))
                }
                .padding(10)
                .background(Color.white)
            }
        }
        .frame(width: 200)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
    }
}

struct MiniItineraryCard: View {
    let item: ItineraryItem
    
    private let warmAccent = Color(red: 0.76, green: 0.42, blue: 0.32)
    
    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 8)
                .fill(warmAccent.opacity(0.1))
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: "fork.knife")
                        .foregroundColor(warmAccent)
                )
            
            VStack(alignment: .leading, spacing: 2) {
                Text(item.location.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.black)
                
                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                    Text(String(format: "%.1f", item.location.rating))
                        .font(.system(size: 12))
                        .foregroundColor(.black.opacity(0.6))
                }
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.black.opacity(0.3))
        }
        .padding(10)
        .background(Color.white.opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - AI Highlight Text Field
struct AIHighlightTextField: View {
    @Binding var text: String
    let placeholder: String
    var isFocused: FocusState<Bool>.Binding
    var accent: Color = Color(red: 0.76, green: 0.42, blue: 0.32)
    
    private static let aiTriggers = ["@tess", "@ai", "@yelp"]
    
    private var containsAITrigger: Bool {
        let lowercased = text.lowercased()
        return Self.aiTriggers.contains { lowercased.contains($0) }
    }
    
    var body: some View {
        HStack(spacing: 8) {
            if containsAITrigger {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Tess")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(accent)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(accent.opacity(0.1))
                .clipShape(Capsule())
                .transition(.scale.combined(with: .opacity))
            }
            
            TextField(placeholder, text: $text)
                .font(.system(size: 16))
                .focused(isFocused)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            ZStack {
                Color(red: 0.98, green: 0.96, blue: 0.93)
                
                if containsAITrigger {
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(accent.opacity(0.4), lineWidth: 1.5)
                }
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .animation(.easeInOut(duration: 0.2), value: containsAITrigger)
    }
}

// MARK: - Attributed Text View for Message Content
struct HighlightedMessageText: View {
    let text: String
    let isCurrentUser: Bool
    
    var body: some View {
        Text(.init(text))
    }
}

// MARK: - Room Info Sheet
struct RoomInfoSheet: View {
    let room: Room?
    let onRoomDeleted: (() -> Void)?
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var dataService = AppDataService.shared
    @State private var copied = false
    @State private var showDeleteConfirmation = false
    @State private var isDeleting = false
    
    private let warmAccent = Color(red: 0.76, green: 0.42, blue: 0.32)
    private let warmBackground = Color(red: 0.98, green: 0.96, blue: 0.93)
    
    private var isOwner: Bool {
        guard let room = room else { return false }
        return dataService.currentUser.id == room.ownerId
    }
    
    private var isMember: Bool {
        guard let room = room else { return false }
        return room.members.contains { $0.id == dataService.currentUser.id }
    }
    
    init(room: Room?, onRoomDeleted: (() -> Void)? = nil) {
        self.room = room
        self.onRoomDeleted = onRoomDeleted
    }
    
    var body: some View {
        NavigationView {
            if let room = room {
                ZStack {
                    warmBackground.ignoresSafeArea()
                    
                    ScrollView {
                        VStack(spacing: 16) {
                            // Room Details Card
                            VStack(spacing: 0) {
                                HStack {
                                    Text("Name")
                                        .foregroundColor(.black.opacity(0.5))
                                    Spacer()
                                    Text(room.name)
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundColor(.black)
                                }
                                .padding(16)
                                
                                Divider().padding(.leading, 16)
                                
                                HStack {
                                    Text("Type")
                                        .foregroundColor(.black.opacity(0.5))
                                    Spacer()
                                    HStack(spacing: 4) {
                                        Image(systemName: room.isPublic ? "globe" : "lock.fill")
                                            .font(.system(size: 12))
                                        Text(room.isPublic ? "Public" : "Private")
                                    }
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(warmAccent)
                                }
                                .padding(16)
                                
                                Divider().padding(.leading, 16)
                                
                                HStack {
                                    Text("Members")
                                        .foregroundColor(.black.opacity(0.5))
                                    Spacer()
                                    Text("\(room.members.count)")
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundColor(.black)
                                }
                                .padding(16)
                            }
                            .font(.system(size: 15))
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            
                            // Invite Code Card
                            VStack(spacing: 14) {
                                Text("Share this code to invite friends")
                                    .font(.system(size: 13))
                                    .foregroundColor(.black.opacity(0.5))
                                
                                Text(room.joinCode)
                                    .font(.system(size: 32, weight: .bold, design: .monospaced))
                                    .tracking(4)
                                    .foregroundColor(.black)
                                
                                Button(action: {
                                    UIPasteboard.general.string = room.joinCode
                                    copied = true
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                        copied = false
                                    }
                                }) {
                                    HStack(spacing: 6) {
                                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                            .font(.system(size: 14, weight: .medium))
                                        Text(copied ? "Copied!" : "Copy Code")
                                            .font(.system(size: 15, weight: .semibold))
                                    }
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 24)
                                    .padding(.vertical, 12)
                                    .background(copied ? Color(red: 0.2, green: 0.7, blue: 0.4) : warmAccent)
                                    .clipShape(Capsule())
                                }
                            }
                            .padding(20)
                            .frame(maxWidth: .infinity)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            
                            // Members Card
                            VStack(alignment: .leading, spacing: 0) {
                                Text("MEMBERS")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.black.opacity(0.4))
                                    .padding(.horizontal, 16)
                                    .padding(.top, 16)
                                    .padding(.bottom, 12)
                                
                                ForEach(room.members, id: \.id) { member in
                                    HStack(spacing: 12) {
                                        AvatarView(user: member, size: 40)
                                        
                                        Text(member.name)
                                            .font(.system(size: 15, weight: .medium))
                                            .foregroundColor(.black)
                                        
                                        Spacer()
                                        
                                        if member.id == room.ownerId {
                                            Text("Owner")
                                                .font(.system(size: 11, weight: .semibold))
                                                .foregroundColor(.white)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(warmAccent)
                                                .clipShape(Capsule())
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    
                                    if member.id != room.members.last?.id {
                                        Divider().padding(.leading, 68)
                                    }
                                }
                            }
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            
                            // Delete/Leave Room Button
                            Button(action: {
                                showDeleteConfirmation = true
                            }) {
                                HStack(spacing: 8) {
                                    if isDeleting {
                                        ProgressView()
                                            .tint(.red)
                                    } else {
                                        Image(systemName: isOwner ? "trash.fill" : "rectangle.portrait.and.arrow.right")
                                            .font(.system(size: 16, weight: .medium))
                                        Text(isOwner ? "Delete Room" : "Leave Room")
                                            .font(.system(size: 16, weight: .semibold))
                                    }
                                }
                                .foregroundColor(.red)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .disabled(isDeleting)
                            .padding(.top, 8)
                        }
                        .padding(16)
                    }
                }
                .navigationTitle("Room Info")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                            .foregroundColor(warmAccent)
                    }
                }
                .confirmationDialog(
                    isOwner ? "Delete \"\(room.name)\"?" : "Leave \"\(room.name)\"?",
                    isPresented: $showDeleteConfirmation,
                    titleVisibility: .visible
                ) {
                    Button(isOwner ? "Delete Room" : "Leave Room", role: .destructive) {
                        isDeleting = true
                        if isOwner {
                            dataService.deleteRoom(roomId: room.id) { success in
                                isDeleting = false
                                if success {
                                    dismiss()
                                    // Navigate out of the room after deletion
                                    onRoomDeleted?()
                                }
                            }
                        } else {
                            dataService.leaveRoom(roomId: room.id) { success in
                                isDeleting = false
                                if success {
                                    dismiss()
                                    // Navigate out after leaving (no longer a member)
                                    onRoomDeleted?()
                                }
                            }
                        }
                    }
                    Button("Cancel", role: .cancel) { }
                } message: {
                    Text(isOwner 
                         ? "This will permanently delete the room and all messages for everyone."
                         : "You will no longer see messages from this room.")
                }
            } else {
                Text("Room not found")
                    .foregroundColor(.black.opacity(0.5))
            }
        }
    }
}

#Preview {
    ChatRoomView()
        .environmentObject(AppState())
}
