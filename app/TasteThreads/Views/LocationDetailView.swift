import SwiftUI
import Combine

struct LocationDetailView: View {
    let item: ItineraryItem
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var dataService: AppDataService
    @State private var isSharing = false
    @State private var fullDetails: YelpBusinessFull?
    @State private var isLoading = false
    @State private var showAllHours = false
    @State private var showRoomSelector = false
    @State private var cancellables = Set<AnyCancellable>()
    
    private let apiService = APIService.shared
    
    // Get rooms user is a member of
    private var availableRooms: [Room] {
        dataService.rooms.filter { room in
            room.members.contains(where: { $0.id == dataService.currentUser.id })
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header Image Carousel
            ZStack(alignment: .topTrailing) {
                let photos = fullDetails?.photos ?? item.location.yelpDetails?.photos ?? []
                if !photos.isEmpty {
                    TabView {
                        ForEach(photos, id: \.self) { photoUrl in
                            AsyncImage(url: URL(string: photoUrl)) { phase in
                                switch phase {
                                case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                case .failure:
                                    placeholderImage
                                case .empty:
                                    ProgressView()
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                        .background(Color.gray.opacity(0.1))
                                @unknown default:
                                    placeholderImage
                                }
                            }
                        }
                    }
                    .tabViewStyle(PageTabViewStyle(indexDisplayMode: .automatic))
                    .frame(height: 260)
                    .clipped()
                } else if let imageUrl = item.location.imageURL {
                    AsyncImage(url: imageUrl) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        placeholderImage
                    }
                    .frame(height: 260)
                    .clipped()
                } else {
                    placeholderImage
                        .frame(height: 260)
                }
                
                // Close button
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title)
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.5), radius: 4)
                        .padding()
                }
            }
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Title & Rating Section
                    titleSection
                    
                    // Action Buttons
                    actionButtons
                    
                    Divider()
                    
                    // Open/Closed Status & Hours
                    if fullDetails != nil || item.location.yelpDetails != nil {
                        hoursSection
                    }
                    
                    // AI Chat Remark
                    if let remark = item.location.aiRemark {
                        aiRemarkSection(remark: remark)
                    }
                    
                    // AI Summary (Yelp Review Snippet)
                    if let summary = item.location.yelpDetails?.aiSummary {
                        aiSummarySection(summary: summary)
                    }
                    
                    // Reviews Section
                    if let reviews = fullDetails?.reviews, !reviews.isEmpty {
                        reviewsSection(reviews: reviews)
                    }
                    
                    // Transactions (Delivery, Pickup, etc.)
                    if let transactions = fullDetails?.transactions, !transactions.isEmpty {
                        transactionsSection(transactions: transactions)
                    }
                    
                    // Popular Dishes
                    if let dishes = item.location.yelpDetails?.popularDishes, !dishes.isEmpty {
                        popularDishesSection(dishes: dishes)
                    }
                    
                    // Notes
                    if let notes = item.notes {
                        notesSection(notes: notes)
                    }
                    
                    // Loading indicator while fetching details
                    if isLoading {
                        HStack {
                            Spacer()
                            ProgressView("Loading details...")
                                .padding()
                            Spacer()
                        }
                    }
                    
                    // Yelp Attribution
                    yelpAttribution
                }
                .padding()
            }
        }
        .ignoresSafeArea(edges: .top)
        .sheet(isPresented: $isSharing) {
            ActivityViewController(activityItems: [
                item.location.name,
                item.location.address,
                fullDetails?.url ?? item.location.yelpDetails?.url?.absoluteString ?? ""
            ])
        }
        .sheet(isPresented: $showRoomSelector) {
            RoomSelectorSheet(
                rooms: availableRooms,
                businessName: item.location.name
            ) { selectedRoom in
                // Navigate to selected room with mention
                appState.navigateToChatRoom(roomId: selectedRoom.id, businessName: item.location.name)
                dismiss()
            }
            .presentationDetents([.medium])
        }
        .onAppear {
            fetchFullDetails()
        }
    }
    
    // MARK: - View Components
    
    private var placeholderImage: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [Color.gray.opacity(0.3), Color.gray.opacity(0.1)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                Image(systemName: iconForType(item.type))
                    .font(.system(size: 60))
                    .foregroundStyle(.secondary)
            )
    }
    
    private var titleSection: some View {
                    VStack(alignment: .leading, spacing: 8) {
            HStack {
                        Text(item.location.name)
                            .font(.title)
                            .fontWeight(.bold)
                        
                if item.isAISuggestion {
                    Image(systemName: "sparkles")
                        .foregroundStyle(.purple)
                        .font(.title3)
                }
            }
            
            // Rating Stars
                        HStack(spacing: 4) {
                            HStack(spacing: 2) {
                                ForEach(0..<5) { index in
                        Image(systemName: ratingIcon(for: index, rating: fullDetails?.rating ?? item.location.rating))
                            .foregroundStyle(.orange)
                            .font(.subheadline)
                                }
                            }
                            
                Text(String(format: "%.1f", fullDetails?.rating ?? item.location.rating))
                                .fontWeight(.bold)
                                .font(.subheadline)
                            
                let reviewCount = fullDetails?.review_count ?? item.location.yelpDetails?.reviewCount ?? 0
                Text("(\(reviewCount) reviews)")
                                    .foregroundStyle(.secondary)
                                    .font(.subheadline)
                            }
            
            // Price & Categories
            let price = fullDetails?.price ?? item.location.yelpDetails?.price ?? ""
            let categories = fullDetails?.categories.map { $0.title } ?? item.location.yelpDetails?.categories ?? []
                        
            if !price.isEmpty || !categories.isEmpty {
                            HStack {
                    if !price.isEmpty {
                        Text(price)
                            .foregroundStyle(.green)
                            .fontWeight(.medium)
                    }
                    if !price.isEmpty && !categories.isEmpty {
                                Text("•")
                            .foregroundStyle(.secondary)
                    }
                    Text(categories.prefix(3).joined(separator: ", "))
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)
            }
            
            // Address
            Text(item.location.address)
                .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
    
    private var actionButtons: some View {
        HStack(spacing: 10) {
            // Mention in Chat Button
            ActionButton(icon: "bubble.left.fill", label: "Mention") {
                showRoomSelector = true
            }
            
            // Call Button
            let phoneNumber = fullDetails?.phone ?? item.location.yelpDetails?.phoneNumber ?? ""
            if !phoneNumber.isEmpty {
                ActionButton(icon: "phone.fill", label: "Call") {
                    if let url = URL(string: "tel:\(phoneNumber.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "-", with: ""))") {
                        UIApplication.shared.open(url)
                    }
                }
                        }
                        
                        ActionButton(icon: "map.fill", label: "Directions") {
                            let url = URL(string: "http://maps.apple.com/?daddr=\(item.location.latitude),\(item.location.longitude)")!
                            UIApplication.shared.open(url)
                        }
                        
                        ActionButton(icon: "square.and.arrow.up", label: "Share") {
                            isSharing = true
                        }
                        
                        let isFavorite = dataService.isFavorite(location: item.location)
                        ActionButton(
                            icon: isFavorite ? "heart.fill" : "heart",
                            label: isFavorite ? "Saved" : "Save",
                            isPrimary: isFavorite
                        ) {
                            dataService.toggleFavorite(location: item.location)
                        }
                    }
    }
    
    private var hoursSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Open/Closed Status
            let isOpen = fullDetails?.isOpenNow ?? item.location.yelpDetails?.isOpen ?? false
            
            HStack {
                Circle()
                    .fill(isOpen ? Color.green : Color.red)
                    .frame(width: 10, height: 10)
                
                Text(isOpen ? "Open Now" : "Closed")
                    .font(.headline)
                    .foregroundStyle(isOpen ? .green : .red)
                
                if let closingTime = item.location.yelpDetails?.closingTime, !closingTime.isEmpty, isOpen {
                    Text("• Closes \(closingTime)")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                }
                
                Spacer()
                
                if let hours = fullDetails?.formattedHours, !hours.isEmpty {
                    Button(action: { withAnimation { showAllHours.toggle() } }) {
                        Image(systemName: showAllHours ? "chevron.up" : "chevron.down")
                            .foregroundStyle(.blue)
                    }
                }
            }
            
            // Full Hours
            if showAllHours, let hours = fullDetails?.formattedHours, !hours.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(hours, id: \.self) { hourString in
                        HStack {
                            Text(hourString.components(separatedBy: ": ").first ?? "")
                                .frame(width: 40, alignment: .leading)
                                .foregroundStyle(.secondary)
                            Text(hourString.components(separatedBy: ": ").dropFirst().joined(separator: ": "))
                                .foregroundStyle(.primary)
                        }
                        .font(.subheadline)
                    }
                }
                .padding(.leading, 20)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private func aiRemarkSection(remark: String) -> some View {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "bubble.left.and.bubble.right.fill")
                                    .foregroundStyle(.blue)
                                Text("Mentioned in Chat")
                                    .font(.headline)
                            }
                            
                            // Use SwiftUI's built-in Markdown parsing for links and formatting
                            Text(.init(remark))
                                .font(.body)
                                .foregroundStyle(.primary)
                                .padding()
                .background(Color.blue.opacity(0.08))
                                .cornerRadius(12)
                        }
                    }
                    
    private func aiSummarySection(summary: String) -> some View {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "sparkles")
                                    .foregroundStyle(.purple)
                                Text("Tess's Take")
                                    .font(.headline)
                            }
                            
                            Text(cleanSummary(summary))
                                .font(.body)
                                .foregroundStyle(.primary)
                                .padding()
                .background(Color.purple.opacity(0.08))
                                .cornerRadius(12)
                        }
                    }
                    
    private func reviewsSection(reviews: [YelpReview]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "star.bubble.fill")
                    .foregroundStyle(.orange)
                Text("Recent Reviews")
                    .font(.headline)
                
                Spacer()
                
                if let url = fullDetails?.url, let yelpURL = URL(string: url) {
                    Button(action: { UIApplication.shared.open(yelpURL) }) {
                        Text("See All")
                            .font(.subheadline)
                            .foregroundStyle(.blue)
                    }
                }
            }
            
            ForEach(reviews.prefix(3)) { review in
                reviewCard(review: review)
            }
        }
    }
    
    private func reviewCard(review: YelpReview) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                // User Avatar
                AsyncImage(url: URL(string: review.user.image_url ?? "")) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                        .overlay(
                            Text(review.user.name.prefix(1))
                                .font(.headline)
                                .foregroundStyle(.secondary)
                        )
                }
                .frame(width: 40, height: 40)
                .clipShape(Circle())
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(review.user.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    HStack(spacing: 2) {
                        ForEach(0..<5) { i in
                            Image(systemName: i < review.rating ? "star.fill" : "star")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                        Text("• \(formatReviewDate(review.time_created))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
            }
            
            Text(review.text)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(4)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private func transactionsSection(transactions: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Services")
                .font(.headline)
            
            HStack(spacing: 8) {
                ForEach(transactions, id: \.self) { transaction in
                    HStack(spacing: 4) {
                        Image(systemName: transactionIcon(for: transaction))
                            .font(.caption)
                        Text(transaction.capitalized.replacingOccurrences(of: "_", with: " "))
                            .font(.caption)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.blue.opacity(0.1))
                    .foregroundStyle(.blue)
                    .cornerRadius(20)
                }
            }
        }
    }
    
    private func popularDishesSection(dishes: [Dish]) -> some View {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Popular Dishes")
                                .font(.headline)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 16) {
                                    ForEach(dishes) { dish in
                                        VStack(alignment: .leading) {
                            if let imageURL = dish.imageURL {
                                AsyncImage(url: imageURL) { image in
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                } placeholder: {
                                    Rectangle()
                                        .fill(Color.gray.opacity(0.1))
                                }
                                .frame(width: 140, height: 100)
                                .cornerRadius(8)
                            } else {
                                            Rectangle()
                                                .fill(Color.gray.opacity(0.1))
                                                .frame(width: 140, height: 100)
                                                .cornerRadius(8)
                                    .overlay(
                                        Image(systemName: "fork.knife")
                                            .foregroundStyle(.secondary)
                                    )
                            }
                                            
                                            Text(dish.name)
                                                .font(.subheadline)
                                                .fontWeight(.medium)
                                                .lineLimit(1)
                                            
                                            if let price = dish.price {
                                                Text(price)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        .frame(width: 140)
                                    }
                                }
                            }
                        }
                    }
                    
    private func notesSection(notes: String) -> some View {
                        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "note.text")
                    .foregroundStyle(.secondary)
                            Text("Group Notes")
                                .font(.headline)
            }
                            Text(notes)
                                .foregroundStyle(.secondary)
                        }
                    }
    
    private var yelpAttribution: some View {
        HStack {
            Spacer()
            if let url = fullDetails?.url ?? item.location.yelpDetails?.url?.absoluteString,
               let yelpURL = URL(string: url) {
                Button(action: { UIApplication.shared.open(yelpURL) }) {
                    HStack(spacing: 4) {
                        Image(systemName: "link")
                        Text("View on Yelp")
                    }
                    .font(.caption)
                    .foregroundStyle(.red)
                }
            }
            Spacer()
        }
        .padding(.top, 8)
    }
    
    // MARK: - Helper Functions
    
    private func fetchFullDetails() {
        guard let yelpId = item.location.yelpId else { return }
        
        isLoading = true
        apiService.getFullBusinessDetails(id: yelpId)
            .sink(
                receiveCompletion: { completion in
                    isLoading = false
                    if case .failure(let error) = completion {
                        print("Failed to fetch full details: \(error)")
                    }
                },
                receiveValue: { details in
                    withAnimation {
                        fullDetails = details
                    }
                }
            )
            .store(in: &cancellables)
    }
    
    private func iconForType(_ type: ItineraryItemType) -> String {
        switch type {
        case .appetizer: return "fork.knife"
        case .main: return "fork.knife.circle.fill"
        case .dessert: return "birthday.cake"
        case .drinks: return "wineglass"
        case .activity: return "figure.walk"
        }
    }
    
    private func ratingIcon(for index: Int, rating: Double) -> String {
        let fullStars = Int(rating)
        let hasHalfStar = rating - Double(fullStars) >= 0.5
        
        if index < fullStars {
            return "star.fill"
        } else if index == fullStars && hasHalfStar {
            return "star.leadinghalf.filled"
        } else {
            return "star"
        }
    }
    
    private func cleanSummary(_ text: String) -> String {
        return text.replacingOccurrences(of: "[[HIGHLIGHT]]", with: "")
                   .replacingOccurrences(of: "[[ENDHIGHLIGHT]]", with: "")
    }
    
    private func formatReviewDate(_ dateString: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        
        if let date = formatter.date(from: dateString) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateFormat = "MMM d, yyyy"
            return displayFormatter.string(from: date)
        }
        return dateString
    }
    
    private func transactionIcon(for transaction: String) -> String {
        switch transaction.lowercased() {
        case "delivery": return "bicycle"
        case "pickup": return "bag"
        case "restaurant_reservation": return "calendar"
        default: return "checkmark.circle"
        }
    }
}

struct ActivityViewController: UIViewControllerRepresentable {
    let activityItems: [Any]
    let applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: UIViewControllerRepresentableContext<ActivityViewController>) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: UIViewControllerRepresentableContext<ActivityViewController>) {}
}

// MARK: - Room Selector Sheet
struct RoomSelectorSheet: View {
    let rooms: [Room]
    let businessName: String
    let onSelect: (Room) -> Void
    
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header explanation
                VStack(spacing: 8) {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.blue)
                    
                    Text("Mention \"\(businessName)\"")
                        .font(.headline)
                    
                    Text("Select a chat room to mention this place")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 20)
                
                Divider()
                
                if rooms.isEmpty {
                    VStack(spacing: 16) {
                        Spacer()
                        Image(systemName: "bubble.left.and.exclamationmark.bubble.right")
                            .font(.system(size: 50))
                            .foregroundStyle(.secondary)
                        Text("No Rooms Yet")
                            .font(.headline)
                        Text("Join or create a room first to mention places")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Spacer()
                    }
                    .padding()
                } else {
                    List {
                        ForEach(rooms) { room in
                            Button {
                                onSelect(room)
                                dismiss()
                            } label: {
                                HStack(spacing: 12) {
                                    // Room Avatar
                                    ZStack {
                                        Circle()
                                            .fill(Color.blue.opacity(0.1))
                                            .frame(width: 48, height: 48)
                                        
                                        Text(String(room.name.prefix(1)))
                                            .font(.headline)
                                            .foregroundStyle(.blue)
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(room.name)
                                            .font(.headline)
                                            .foregroundStyle(.primary)
                                        
                                        HStack(spacing: 4) {
                                            Image(systemName: room.isPublic ? "globe" : "lock.fill")
                                                .font(.caption2)
                                            Text("\(room.members.count) members")
                                                .font(.caption)
                                        }
                                        .foregroundStyle(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Select Room")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct ActionButton: View {
    let icon: String
    let label: String
    var isPrimary: Bool = false
    var action: () -> Void = {}
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                Text(label)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(isPrimary ? Color.red : Color(.systemGray6))
            .foregroundStyle(isPrimary ? .white : .primary)
            .cornerRadius(10)
        }
    }
}

#Preview {
    LocationDetailView(item: ItineraryItem(
        id: UUID().uuidString,
        type: .main,
        location: Location(
            name: "Tony's Pizza Napoletana",
            address: "1570 Stockton St, San Francisco, CA",
            latitude: 37.8003,
            longitude: -122.4091,
            rating: 4.5,
            imageURL: nil,
            yelpDetails: YelpDetails(
                price: "$$",
                reviewCount: 4500,
                categories: ["Pizza", "Italian"],
                isOpen: true,
                closingTime: "10:00 PM",
                phoneNumber: "(415) 835-9888",
                url: nil,
                popularDishes: [
                    Dish(id: UUID().uuidString, name: "Margherita", imageURL: nil, price: "$22"),
                    Dish(id: UUID().uuidString, name: "Calzone", imageURL: nil, price: "$24")
                ],
                aiSummary: "Famous for its variety of pizza styles. High demand, so expect a wait.",
                photos: nil,
                hours: nil
            ),
            yelpId: "tonys-pizza-napoletana-san-francisco"
        ),
        time: Date(),
        notes: "Great pizza!",
        votes: 0,
        isAISuggestion: true
    ))
    .environmentObject(AppState())
    .environmentObject(AppDataService.shared)
}
