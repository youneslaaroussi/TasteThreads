import SwiftUI

struct ChatRoomView: View {
    @StateObject private var viewModel = ChatViewModel()
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    @Environment(\.openURL) var openURL
    @FocusState private var isFocused: Bool
    @State private var showRoomInfo = false
    
    private var currentRoom: Room? {
        AppDataService.shared.currentRoom
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button(action: {
                    dismiss()
                }) {
                    Image(systemName: "chevron.left")
                        .font(.title2)
                        .foregroundStyle(.primary)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(currentRoom?.name ?? "Group Chat")
                        .font(.headline)
                    if let room = currentRoom {
                        Text("\(room.members.count) members")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                // Invite to WhatsApp button
                Button(action: {
                    if let url = URL(string: "whatsapp://") {
                        openURL(url)
                    }
                }) {
                    ZStack {
                        Circle()
                            .fill(Color(red: 0.09, green: 0.73, blue: 0.36))
                            .frame(width: 30, height: 30)
                        Image(systemName: "phone.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .padding(.trailing, 4)
                
                Button(action: { showRoomInfo = true }) {
                    Image(systemName: "info.circle")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(.ultraThinMaterial)
            
            // Messages List
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        // Show skeleton loading state
                        if viewModel.isLoading && viewModel.messages.isEmpty {
                            ForEach(0..<5, id: \.self) { index in
                                MessageSkeletonView(isLeft: index % 2 == 0)
                            }
                        } else {
                            ForEach(viewModel.messages) { message in
                                if message.type == .system {
                                    Text(message.content)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
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
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    TypingIndicatorView()
                                }
                                Spacer()
                            }
                            .transition(.opacity)
                            .id("typingIndicator")
                        }
                    }
                    .padding()
                }
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
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.blue)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(Color.blue.opacity(0.1))
                                    .cornerRadius(20)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 20)
                                            .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                                    )
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }
            }
            
            // Input Area
            HStack(spacing: 12) {
                AIHighlightTextField(
                    text: $viewModel.newMessageText,
                    placeholder: "Type a message... @Tess for suggestions",
                    isFocused: $isFocused
                )
                .onChange(of: viewModel.newMessageText) { oldValue, newValue in
                    // Broadcast typing indicator
                    if !newValue.isEmpty && oldValue.isEmpty {
                        // Started typing
                        AppDataService.shared.sendTypingIndicator(isTyping: true)
                    } else if newValue.isEmpty && !oldValue.isEmpty {
                        // Stopped typing
                        AppDataService.shared.sendTypingIndicator(isTyping: false)
                    }
                }
                .onAppear {
                    if !appState.chatDraft.isEmpty {
                        viewModel.newMessageText = appState.chatDraft
                        appState.chatDraft = ""
                        isFocused = true
                    }
                }
                
                Button(action: { viewModel.sendMessage() }) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(viewModel.newMessageText.isEmpty ? .gray : .blue)
                }
                .disabled(viewModel.newMessageText.isEmpty)
            }
            .padding()
            .background(.ultraThinMaterial)
        }
        .onTapGesture {
            isFocused = false
        }
        .task {
            // Connect to room asynchronously in background
            viewModel.connectToRoom()
        }
        // Note: We don't disconnect on disappear - connection persists for better UX
        // Disconnection happens when explicitly leaving the room or switching rooms
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
            RoomInfoSheet(room: currentRoom)
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
                // Avatar skeleton
                Circle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 32, height: 32)
            } else {
                Spacer()
            }
            
            VStack(alignment: isLeft ? .leading : .trailing, spacing: 4) {
                if isLeft {
                    // Name skeleton
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 60, height: 10)
                        .padding(.leading, 4)
                }
                
                // Message bubble skeleton
                VStack(alignment: .leading, spacing: 6) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: isLeft ? 180 : 150, height: 12)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: isLeft ? 140 : 120, height: 12)
                    
                    if isLeft {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 100, height: 12)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(20)
                
                // Time skeleton
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.15))
                    .frame(width: 40, height: 8)
                    .padding(isLeft ? .leading : .trailing, 4)
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
    @EnvironmentObject var appState: AppState
    @State private var showDetails = false
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if !isCurrentUser {
                // Avatar
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 32, height: 32)
                    .overlay(Text(user?.name.prefix(1) ?? "?").font(.caption))
            } else {
                Spacer()
            }
            
            VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: 4) {
                if !isCurrentUser, let name = user?.name {
                    Text(name)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 4)
                }
                
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
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(isCurrentUser ? Color.blue : Color(uiColor: .systemGray5))
                .foregroundStyle(isCurrentUser ? .white : .primary)
                .cornerRadius(20)
                .clipShape(
                    .rect(
                        topLeadingRadius: 20,
                        bottomLeadingRadius: isCurrentUser ? 20 : 4,
                        bottomTrailingRadius: isCurrentUser ? 4 : 20,
                        topTrailingRadius: 20
                    )
                )
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
                
                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(isCurrentUser ? .trailing : .leading, 4)
            }
            
            if !isCurrentUser {
                Spacer()
            }
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
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Image
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
                            Rectangle()
                                .fill(Color(uiColor: .secondarySystemFill))
                            Image(systemName: "photo")
                                .foregroundStyle(.secondary)
                        }
                    case .empty:
                        ZStack {
                            Rectangle()
                                .fill(Color(uiColor: .secondarySystemFill))
                            ProgressView()
                                .tint(.secondary)
                        }
                    @unknown default:
                        Rectangle()
                            .fill(Color(uiColor: .secondarySystemFill))
                    }
                }
                .frame(width: 200, height: 120)
                .clipped()
            } else {
                ZStack {
                    Rectangle()
                        .fill(Color(uiColor: .secondarySystemFill))
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                }
                .frame(width: 200, height: 120)
            }
            
            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(business.name)
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                
                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                    Text(String(format: "%.1f", business.rating))
                        .font(.caption2)
                        .foregroundStyle(.primary)
                    Text("(\(business.review_count))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                
                HStack {
                    Text(business.categories?.first?.title ?? "Restaurant")
                    Spacer()
                    Text(business.price ?? "")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            .padding(10)
            .background(Color(uiColor: .systemBackground).opacity(colorScheme == .dark ? 0.9 : 1.0))
        }
        .frame(width: 200)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.5 : 0.1), radius: 4, x: 0, y: 2)
    }
}

struct MapMessageBubble: View {
    let location: Location
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                // Placeholder Map Image
                Rectangle()
                    .fill(Color.blue.opacity(0.1))
                    .frame(height: 100)
                    .overlay(
                        Image(systemName: "map.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.blue)
                    )
                
                HStack {
                    VStack(alignment: .leading) {
                        Text(location.name)
                            .font(.caption)
                            .fontWeight(.bold)
                        Text(location.address)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(8)
                .background(Color.white.opacity(0.5))
            }
        }
        .frame(width: 200)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
    }
}

struct MiniItineraryCard: View {
    let item: ItineraryItem
    
    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.5))
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: "fork.knife") // Placeholder
                        .foregroundStyle(.secondary)
                )
            
            VStack(alignment: .leading, spacing: 2) {
                Text(item.location.name)
                    .font(.caption)
                    .fontWeight(.bold)
                
                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                    Text(String(format: "%.1f", item.location.rating))
                        .font(.caption2)
                }
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(Color.white.opacity(0.2))
        .cornerRadius(10)
    }
}

// MARK: - AI Highlight Text Field
struct AIHighlightTextField: View {
    @Binding var text: String
    let placeholder: String
    var isFocused: FocusState<Bool>.Binding
    
    /// Triggers for AI assistant - @tess, @ai, or @yelp
    private static let aiTriggers = ["@tess", "@ai", "@yelp"]
    
    private var containsAITrigger: Bool {
        let lowercased = text.lowercased()
        return Self.aiTriggers.contains { lowercased.contains($0) }
    }
    
    var body: some View {
        HStack(spacing: 8) {
            // Yelp/Tess indicator when AI trigger is typed
            if containsAITrigger {
                HStack(spacing: 4) {
                    // Yelp logo - using a stylized "Y" with fork icon
                    ZStack {
                        Circle()
                            .fill(Color(red: 0.95, green: 0.2, blue: 0.2))
                            .frame(width: 20, height: 20)
                        
                        Text("Y")
                            .font(.system(size: 12, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    Text("Yelp")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundStyle(Color(red: 0.95, green: 0.2, blue: 0.2))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Color(red: 0.95, green: 0.2, blue: 0.2).opacity(0.1)
                )
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(Color(red: 0.95, green: 0.2, blue: 0.2).opacity(0.3), lineWidth: 1)
                )
                .transition(.scale.combined(with: .opacity))
            }
            
            TextField(placeholder, text: $text)
                .focused(isFocused)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            ZStack {
                Color(uiColor: .systemGray6)
                
                // Subtle red glow when AI trigger is present (Yelp branding)
                if containsAITrigger {
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(
                            Color(red: 0.95, green: 0.2, blue: 0.2).opacity(0.4),
                            lineWidth: 2
                        )
                }
            }
        )
        .cornerRadius(20)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: containsAITrigger)
    }
}

// MARK: - Attributed Text View for Message Content
struct HighlightedMessageText: View {
    let text: String
    let isCurrentUser: Bool
    
    var body: some View {
        // Use SwiftUI's built-in Markdown parsing so links and basic formatting render correctly.
        Text(.init(text))
    }
}

// MARK: - Room Info Sheet
struct RoomInfoSheet: View {
    let room: Room?
    @Environment(\.dismiss) var dismiss
    @State private var copied = false
    
    var body: some View {
        NavigationView {
            if let room = room {
                List {
                    Section("Room Details") {
                        HStack {
                            Text("Name")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(room.name)
                                .fontWeight(.medium)
                        }
                        
                        HStack {
                            Text("Type")
                                .foregroundStyle(.secondary)
                            Spacer()
                            HStack(spacing: 4) {
                                Image(systemName: room.isPublic ? "globe" : "lock.fill")
                                    .font(.caption)
                                Text(room.isPublic ? "Public" : "Private")
                            }
                            .foregroundStyle(room.isPublic ? .blue : .orange)
                        }
                        
                        HStack {
                            Text("Members")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(room.members.count)")
                                .fontWeight(.medium)
                        }
                    }
                    
                    Section("Invite Code") {
                        VStack(alignment: .center, spacing: 12) {
                            Text("Share this code to invite friends")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            Text(room.joinCode)
                                .font(.system(size: 32, weight: .bold, design: .monospaced))
                                .tracking(4)
                                .foregroundStyle(Color(red: 0.4, green: 0.3, blue: 0.9))
                            
                            Button(action: {
                                UIPasteboard.general.string = room.joinCode
                                copied = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    copied = false
                                }
                            }) {
                                HStack {
                                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                    Text(copied ? "Copied!" : "Copy Code")
                                }
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                                .background(copied ? Color.green : Color(red: 0.4, green: 0.3, blue: 0.9))
                                .clipShape(Capsule())
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                    
                    Section("Members") {
                        ForEach(room.members, id: \.id) { member in
                            HStack {
                                ZStack {
                                    Circle()
                                        .fill(Color.blue.opacity(0.1))
                                        .frame(width: 36, height: 36)
                                    
                                    Text(String(member.name.prefix(1)))
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundStyle(.blue)
                                }
                                
                                Text(member.name)
                                    .font(.subheadline)
                                
                                Spacer()
                                
                                if member.id == room.ownerId {
                                    Text("Owner")
                                        .font(.caption)
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 2)
                                        .background(Color(red: 0.4, green: 0.3, blue: 0.9))
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }
                }
                .navigationTitle("Room Info")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
            } else {
                Text("Room not found")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    ChatRoomView()
        .environmentObject(AppState())
}
