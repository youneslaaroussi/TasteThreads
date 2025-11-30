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
    
    // Warm theme colors
    private let warmAccent = Color(red: 0.76, green: 0.42, blue: 0.32)
    private let warmBackground = Color(red: 0.98, green: 0.96, blue: 0.93)
    
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
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.black.opacity(0.6))
                        .frame(width: 32, height: 32)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
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
                        .padding(.vertical, 4)
                    
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
            .background(warmBackground)
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
                // Navigate to selected room with business name and address
                appState.navigateToChatRoom(
                    roomId: selectedRoom.id,
                    businessName: item.location.name,
                    address: item.location.address,
                    yelpId: item.location.yelpId
                )
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
            .fill(warmBackground)
            .overlay(
                Image(systemName: iconForType(item.type))
                    .font(.system(size: 60))
                    .foregroundColor(warmAccent.opacity(0.4))
            )
    }
    
    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(item.location.name)
                .font(.system(size: 26, weight: .bold))
                .foregroundColor(.black)
            
            // Rating Stars
            HStack(spacing: 4) {
                HStack(spacing: 2) {
                    ForEach(0..<5) { index in
                        Image(systemName: ratingIcon(for: index, rating: fullDetails?.rating ?? item.location.rating))
                            .foregroundColor(.orange)
                            .font(.system(size: 14))
                    }
                }
                
                Text(String(format: "%.1f", fullDetails?.rating ?? item.location.rating))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.black)
                
                let reviewCount = fullDetails?.review_count ?? item.location.yelpDetails?.reviewCount ?? 0
                Text("(\(reviewCount) reviews)")
                    .font(.system(size: 15))
                    .foregroundColor(.black.opacity(0.5))
            }
            
            // Price & Categories
            let price = fullDetails?.price ?? item.location.yelpDetails?.price ?? ""
            let categories = fullDetails?.categories.map { $0.title } ?? item.location.yelpDetails?.categories ?? []
            
            if !price.isEmpty || !categories.isEmpty {
                HStack(spacing: 6) {
                    if !price.isEmpty {
                        Text(price)
                            .foregroundColor(Color(red: 0.2, green: 0.6, blue: 0.4))
                            .fontWeight(.medium)
                    }
                    if !price.isEmpty && !categories.isEmpty {
                        Text("•")
                            .foregroundColor(.black.opacity(0.3))
                    }
                    Text(categories.prefix(3).joined(separator: ", "))
                        .foregroundColor(.black.opacity(0.5))
                }
                .font(.system(size: 15))
            }
            
            // Address
            Text(item.location.address)
                .font(.system(size: 14))
                .foregroundColor(.black.opacity(0.5))
        }
    }
    
    private var actionButtons: some View {
        HStack(spacing: 8) {
            // Share in Chat Button
            ActionButton(icon: "bubble.left.fill", label: "Share", accent: warmAccent) {
                showRoomSelector = true
            }
            
            // Call Button
            let phoneNumber = fullDetails?.phone ?? item.location.yelpDetails?.phoneNumber ?? ""
            if !phoneNumber.isEmpty {
                ActionButton(icon: "phone.fill", label: "Call", accent: warmAccent) {
                    if let url = URL(string: "tel:\(phoneNumber.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "-", with: ""))") {
                        UIApplication.shared.open(url)
                    }
                }
            }
            
            ActionButton(icon: "map.fill", label: "Directions", accent: warmAccent) {
                let url = URL(string: "http://maps.apple.com/?daddr=\(item.location.latitude),\(item.location.longitude)")!
                UIApplication.shared.open(url)
            }
            
            ActionButton(icon: "square.and.arrow.up", label: "Share", accent: warmAccent) {
                isSharing = true
            }
            
            let isFavorite = dataService.isFavorite(location: item.location)
            ActionButton(
                icon: isFavorite ? "heart.fill" : "heart",
                label: isFavorite ? "Saved" : "Save",
                accent: warmAccent,
                isPrimary: isFavorite
            ) {
                dataService.toggleFavorite(location: item.location)
            }
        }
    }
    
    private var hoursSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            let isOpen = fullDetails?.isOpenNow ?? item.location.yelpDetails?.isOpen ?? false
            
            HStack {
                Circle()
                    .fill(isOpen ? Color(red: 0.2, green: 0.7, blue: 0.4) : Color(red: 0.9, green: 0.3, blue: 0.3))
                    .frame(width: 10, height: 10)
                
                Text(isOpen ? "Open Now" : "Closed")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(isOpen ? Color(red: 0.2, green: 0.6, blue: 0.4) : Color(red: 0.9, green: 0.3, blue: 0.3))
                
                if let closingTime = item.location.yelpDetails?.closingTime, !closingTime.isEmpty, isOpen {
                    Text("• Closes \(closingTime)")
                        .font(.system(size: 14))
                        .foregroundColor(.black.opacity(0.5))
                }
                
                Spacer()
                
                if let hours = fullDetails?.formattedHours, !hours.isEmpty {
                    Button(action: { withAnimation { showAllHours.toggle() } }) {
                        Image(systemName: showAllHours ? "chevron.up" : "chevron.down")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(warmAccent)
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
                                .foregroundColor(.black.opacity(0.5))
                            Text(hourString.components(separatedBy: ": ").dropFirst().joined(separator: ": "))
                                .foregroundColor(.black)
                        }
                        .font(.system(size: 14))
                    }
                }
                .padding(.leading, 20)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
    }
    
    private func aiRemarkSection(remark: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .foregroundColor(warmAccent)
                Text("Shared in Chat")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.black)
            }
            
            Text(.init(remark))
                .font(.system(size: 15))
                .foregroundColor(.black.opacity(0.8))
                .padding(14)
                .background(warmAccent.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
    
    private func aiSummarySection(summary: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundColor(warmAccent)
                Text("Tess's Take")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.black)
            }
            
            Text(cleanSummary(summary))
                .font(.system(size: 15))
                .foregroundColor(.black.opacity(0.8))
                .padding(14)
                .background(warmAccent.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
    
    private func reviewsSection(reviews: [YelpReview]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "star.bubble.fill")
                    .foregroundColor(.orange)
                Text("Recent Reviews")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.black)
                
                Spacer()
                
                if let url = fullDetails?.url, let yelpURL = URL(string: url) {
                    Button(action: { UIApplication.shared.open(yelpURL) }) {
                        Text("See All")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(warmAccent)
                    }
                }
            }
            
            ForEach(reviews.prefix(3)) { review in
                reviewCard(review: review)
            }
        }
    }
    
    private func reviewCard(review: YelpReview) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                AsyncImage(url: URL(string: review.user.image_url ?? "")) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Circle()
                        .fill(warmAccent.opacity(0.15))
                        .overlay(
                            Text(review.user.name.prefix(1))
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(warmAccent)
                        )
                }
                .frame(width: 40, height: 40)
                .clipShape(Circle())
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(review.user.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.black)
                    
                    HStack(spacing: 2) {
                        ForEach(0..<5) { i in
                            Image(systemName: i < review.rating ? "star.fill" : "star")
                                .font(.system(size: 10))
                                .foregroundColor(.orange)
                        }
                        Text("• \(formatReviewDate(review.time_created))")
                            .font(.system(size: 12))
                            .foregroundColor(.black.opacity(0.5))
                    }
                }
                
                Spacer()
            }
            
            Text(review.text)
                .font(.system(size: 14))
                .foregroundColor(.black.opacity(0.7))
                .lineLimit(4)
        }
        .padding(14)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
    }
    
    private func transactionsSection(transactions: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Services")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.black)
            
            HStack(spacing: 8) {
                ForEach(transactions, id: \.self) { transaction in
                    HStack(spacing: 4) {
                        Image(systemName: transactionIcon(for: transaction))
                            .font(.system(size: 12))
                        Text(transaction.capitalized.replacingOccurrences(of: "_", with: " "))
                            .font(.system(size: 13))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(warmAccent.opacity(0.1))
                    .foregroundColor(warmAccent)
                    .clipShape(Capsule())
                }
            }
        }
    }
    
    private func popularDishesSection(dishes: [Dish]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Popular Dishes")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.black)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(dishes) { dish in
                        VStack(alignment: .leading, spacing: 8) {
                            if let imageURL = dish.imageURL {
                                AsyncImage(url: imageURL) { image in
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                } placeholder: {
                                    Rectangle()
                                        .fill(warmBackground)
                                }
                                .frame(width: 140, height: 100)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            } else {
                                Rectangle()
                                    .fill(warmBackground)
                                    .frame(width: 140, height: 100)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .overlay(
                                        Image(systemName: "fork.knife")
                                            .foregroundColor(warmAccent.opacity(0.4))
                                    )
                            }
                            
                            Text(dish.name)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.black)
                                .lineLimit(1)
                            
                            if let price = dish.price {
                                Text(price)
                                    .font(.system(size: 13))
                                    .foregroundColor(.black.opacity(0.5))
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
            HStack(spacing: 8) {
                Image(systemName: "note.text")
                    .foregroundColor(warmAccent)
                Text("Group Notes")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.black)
            }
            Text(notes)
                .font(.system(size: 14))
                .foregroundColor(.black.opacity(0.6))
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
                    .font(.system(size: 13))
                    .foregroundColor(warmAccent)
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
    
    private let warmAccent = Color(red: 0.76, green: 0.42, blue: 0.32)
    private let warmBackground = Color(red: 0.98, green: 0.96, blue: 0.93)
    
    var body: some View {
        NavigationView {
            ZStack {
                warmBackground.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Header explanation
                    VStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(warmAccent.opacity(0.12))
                                .frame(width: 64, height: 64)
                            Image(systemName: "bubble.left.and.bubble.right.fill")
                                .font(.system(size: 28))
                                .foregroundColor(warmAccent)
                        }
                        
                        Text("Share \"\(businessName)\"")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.black)
                        
                        Text("Select a room to share this place")
                            .font(.system(size: 15))
                            .foregroundColor(.black.opacity(0.5))
                    }
                    .padding(.vertical, 24)
                    
                    if rooms.isEmpty {
                        VStack(spacing: 16) {
                            Spacer()
                            Image(systemName: "bubble.left.and.exclamationmark.bubble.right")
                                .font(.system(size: 50))
                                .foregroundColor(warmAccent.opacity(0.4))
                            Text("No Rooms Yet")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(.black)
                            Text("Join or create a room first")
                                .font(.system(size: 15))
                                .foregroundColor(.black.opacity(0.5))
                            Spacer()
                        }
                    } else {
                        ScrollView {
                            VStack(spacing: 10) {
                                ForEach(rooms) { room in
                                    Button {
                                        onSelect(room)
                                        dismiss()
                                    } label: {
                                        HStack(spacing: 14) {
                                            ZStack {
                                                Circle()
                                                    .fill(warmAccent.opacity(0.12))
                                                    .frame(width: 48, height: 48)
                                                Text(String(room.name.prefix(1)))
                                                    .font(.system(size: 18, weight: .semibold))
                                                    .foregroundColor(warmAccent)
                                            }
                                            
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(room.name)
                                                    .font(.system(size: 16, weight: .semibold))
                                                    .foregroundColor(.black)
                                                
                                                HStack(spacing: 4) {
                                                    Image(systemName: room.isPublic ? "globe" : "lock.fill")
                                                        .font(.system(size: 11))
                                                    Text("\(room.members.count) members")
                                                        .font(.system(size: 13))
                                                }
                                                .foregroundColor(.black.opacity(0.5))
                                            }
                                            
                                            Spacer()
                                            
                                            Image(systemName: "chevron.right")
                                                .font(.system(size: 14, weight: .medium))
                                                .foregroundColor(.black.opacity(0.3))
                                        }
                                        .padding(14)
                                        .background(Color.white)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                        .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                }
            }
            .navigationTitle("Select Room")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(warmAccent)
                }
            }
        }
    }
}

struct ActionButton: View {
    let icon: String
    let label: String
    var accent: Color = Color(red: 0.76, green: 0.42, blue: 0.32)
    var isPrimary: Bool = false
    var action: () -> Void = {}
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                Text(label)
                    .font(.system(size: 11, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(isPrimary ? accent : Color.white)
            .foregroundColor(isPrimary ? .white : .black.opacity(0.7))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
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
