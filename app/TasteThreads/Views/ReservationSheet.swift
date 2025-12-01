//
//  ReservationSheet.swift
//  TasteThreads
//
//  Full reservation booking form sheet
//

import SwiftUI
import Combine

struct ReservationSheet: View {
    let action: ReservationAction
    let userProfile: User
    let room: Room?
    let onConfirm: (ReservationBookingDetails, ReserveResponse?) -> Void
    
    @Environment(\.dismiss) var dismiss
    
    @State private var selectedDate: Date
    @State private var selectedTime: ReservationTimeSlot?
    @State private var covers: Int
    @State private var firstName: String
    @State private var lastName: String
    @State private var email: String
    @State private var phone: String
    @State private var notes: String = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var reservationCancellable: AnyCancellable?
    @State private var reservationResponse: ReserveResponse?
    @State private var showSuccessState = false
    @State private var confirmedBookingDetails: ReservationBookingDetails?
    
    private let accentColor = Color(red: 0.4, green: 0.3, blue: 0.9)
    
    /// Check if the current user is the room owner
    private var isRoomOwner: Bool {
        guard let room = room else { return false }
        return userProfile.id == room.ownerId
    }
    
    init(action: ReservationAction, userProfile: User, room: Room? = nil, onConfirm: @escaping (ReservationBookingDetails, ReserveResponse?) -> Void) {
        self.action = action
        self.userProfile = userProfile
        self.room = room
        self.onConfirm = onConfirm
        
        // Initialize state from action and profile
        let initialDate: Date
        if let dateStr = action.requestedDate {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            initialDate = formatter.date(from: dateStr) ?? Date()
        } else {
            initialDate = Date()
        }
        
        self._selectedDate = State(initialValue: initialDate)
        self._covers = State(initialValue: action.requestedCovers ?? 2)
        self._firstName = State(initialValue: userProfile.firstName ?? "")
        self._lastName = State(initialValue: userProfile.lastName ?? "")
        self._email = State(initialValue: userProfile.email ?? "")
        self._phone = State(initialValue: userProfile.phoneNumber ?? "")
        
        // Pre-select first available time
        self._selectedTime = State(initialValue: action.availableTimes?.first)
    }
    
    // Group times by date
    private var timesByDate: [String: [ReservationTimeSlot]] {
        guard let times = action.availableTimes else { return [:] }
        return Dictionary(grouping: times) { $0.date }
    }
    
    // Get times for the selected date
    private var timesForSelectedDate: [ReservationTimeSlot] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateStr = formatter.string(from: selectedDate)
        return timesByDate[dateStr] ?? []
    }
    
    // Available dates (unique dates from time slots)
    private var availableDates: [Date] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        
        let dateStrings = Set(action.availableTimes?.map { $0.date } ?? [])
        return dateStrings.compactMap { formatter.date(from: $0) }.sorted()
    }
    
    var body: some View {
        NavigationView {
            if showSuccessState, let response = reservationResponse {
                // Success state - show confirmation
                successView(response: response)
            } else {
                // Booking form
                ScrollView {
                    VStack(spacing: 24) {
                        // Restaurant header
                        restaurantHeader
                        
                        // Date picker
                        dateSection
                        
                        // Time slots
                        timeSection
                        
                        // Party size
                        partySizeSection
                        
                        // Contact info
                        contactSection
                        
                        // Special requests
                        notesSection
                        
                        // Error message
                        if let error = errorMessage {
                            Text(error)
                                .font(.subheadline)
                                .foregroundStyle(.red)
                                .padding()
                                .background(Color.red.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        
                        // Confirm button
                        confirmButton
                    }
                    .padding()
                }
                .background(Color(uiColor: .systemGroupedBackground))
                .navigationTitle("Book a Table")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
        }
    }
    
    // MARK: - Success View
    
    private func successView(response: ReserveResponse) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                // Success header
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color(red: 0.2, green: 0.7, blue: 0.4))
                            .frame(width: 80, height: 80)
                        
                        Image(systemName: "checkmark")
                            .font(.system(size: 40, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .padding(.top, 20)
                    
                    Text("Reservation Confirmed!")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text(action.businessName)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 20)
                
                // Confirmation details card
                VStack(spacing: 16) {
                    if let details = confirmedBookingDetails {
                        let slot = ReservationTimeSlot(date: details.date, time: details.time)
                        DetailRow(icon: "calendar", label: "Date", value: slot.formattedDate)
                        DetailRow(icon: "clock", label: "Time", value: slot.formattedTime)
                        DetailRow(icon: "person.2", label: "Party size", value: "\(details.covers) guests")
                    } else if let selectedTime = selectedTime {
                        DetailRow(icon: "calendar", label: "Date", value: selectedTime.formattedDate)
                        DetailRow(icon: "clock", label: "Time", value: selectedTime.formattedTime)
                        DetailRow(icon: "person.2", label: "Party size", value: "\(covers) guests")
                    } else if let time = action.availableTimes?.first {
                        DetailRow(icon: "calendar", label: "Date", value: time.formattedDate)
                        DetailRow(icon: "clock", label: "Time", value: time.formattedTime)
                        DetailRow(icon: "person.2", label: "Party size", value: "\(covers) guests")
                    }
                    
                    if let reservationId = response.reservation_id {
                        DetailRow(icon: "number", label: "Confirmation", value: String(reservationId.prefix(12)).uppercased())
                    }
                    
                    if let address = action.businessAddress {
                        DetailRow(icon: "mappin.circle", label: "Address", value: address)
                    }
                    
                    if let phone = action.businessPhone {
                        DetailRow(icon: "phone", label: "Phone", value: phone)
                    }
                }
                .padding(20)
                .background(Color(uiColor: .systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
                
                // Action buttons
                if let confirmationUrl = response.confirmation_url, let url = URL(string: confirmationUrl) {
                    Link(destination: url) {
                        HStack {
                            Image(systemName: "arrow.up.right.square")
                            Text("View on Yelp")
                                .fontWeight(.semibold)
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(red: 0.85, green: 0.11, blue: 0.09))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(.horizontal)
                }
            }
            .padding()
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Reservation Confirmed")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    if let details = confirmedBookingDetails {
                        onConfirm(details, response)
                    }
                    dismiss()
                }
            }
        }
    }
    
    // MARK: - Sections
    
    private var restaurantHeader: some View {
        HStack(spacing: 12) {
            if let imageUrl = action.businessImageUrl, let url = URL(string: imageUrl) {
                AsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle().fill(Color(uiColor: .systemGray5))
                }
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(accentColor.opacity(0.1))
                        .frame(width: 60, height: 60)
                    Image(systemName: "fork.knife")
                        .font(.title2)
                        .foregroundStyle(accentColor)
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(action.businessName)
                    .font(.headline)
                    .fontWeight(.semibold)
                
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                    Text("Yelp Reservations")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
        }
        .padding()
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    private var dateSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Date", systemImage: "calendar")
                .font(.headline)
            
            // Horizontal scrolling date picker
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(availableDates, id: \.self) { date in
                        DateChip(
                            date: date,
                            isSelected: Calendar.current.isDate(date, inSameDayAs: selectedDate)
                        ) {
                            selectedDate = date
                            // Update selected time to first available for this date
                            let formatter = DateFormatter()
                            formatter.dateFormat = "yyyy-MM-dd"
                            let dateStr = formatter.string(from: date)
                            selectedTime = timesByDate[dateStr]?.first
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .padding()
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    private var timeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Time", systemImage: "clock")
                .font(.headline)
            
            if timesForSelectedDate.isEmpty {
                HStack {
                    Image(systemName: "exclamationmark.circle")
                        .foregroundStyle(.orange)
                    Text("No times available for this date")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            } else {
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 8) {
                    ForEach(timesForSelectedDate) { slot in
                        TimeChip(
                            slot: slot,
                            isSelected: selectedTime?.id == slot.id
                        ) {
                            selectedTime = slot
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    private var partySizeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Party Size", systemImage: "person.2")
                .font(.headline)
            
            HStack {
                ForEach(1...min(8, action.coversRange?.maxPartySize ?? 8), id: \.self) { size in
                    Button(action: { covers = size }) {
                        Text("\(size)")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 40, height: 40)
                            .background(covers == size ? accentColor : Color(uiColor: .systemGray6))
                            .foregroundStyle(covers == size ? .white : .primary)
                            .clipShape(Circle())
                    }
                }
                
                Spacer()
            }
        }
        .padding()
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    private var contactSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Contact Information", systemImage: "person.crop.circle")
                .font(.headline)
            
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    TextField("First Name", text: $firstName)
                        .textFieldStyle(ReservationTextFieldStyle())
                    
                    TextField("Last Name", text: $lastName)
                        .textFieldStyle(ReservationTextFieldStyle())
                }
                
                TextField("Email", text: $email)
                    .textFieldStyle(ReservationTextFieldStyle())
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .autocapitalization(.none)
                
                TextField("Phone", text: $phone)
                    .textFieldStyle(ReservationTextFieldStyle())
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
            }
        }
        .padding()
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Special Requests", systemImage: "text.bubble")
                .font(.headline)
            
            TextField("Any dietary restrictions or special occasions?", text: $notes, axis: .vertical)
                .textFieldStyle(ReservationTextFieldStyle())
                .lineLimit(3...5)
        }
        .padding()
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    private var confirmButton: some View {
        VStack(spacing: 12) {
            // Show warning if user is not room owner
            if !isRoomOwner && room != nil {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Only the room owner can make reservations")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(Color.orange.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            
            Button(action: handleConfirm) {
                HStack {
                    if isLoading {
                        ProgressView()
                            .tint(.white)
                        Text("Booking...")
                            .fontWeight(.semibold)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Confirm Reservation")
                            .fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(canConfirm ? accentColor : Color.gray)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(!canConfirm || isLoading)
        }
    }
    
    // MARK: - Logic
    
    private var canConfirm: Bool {
        // Must be room owner (if room exists) and have all required fields
        let hasRequiredFields = selectedTime != nil &&
            !firstName.isEmpty &&
            !lastName.isEmpty &&
            !email.isEmpty &&
            !phone.isEmpty
        
        // If room exists, must be owner
        if room != nil {
            return hasRequiredFields && isRoomOwner
        }
        
        return hasRequiredFields
    }
    
    private func handleConfirm() {
        guard let time = selectedTime else { return }
        guard let room = room else {
            // No room - just call onConfirm with details (legacy behavior)
            let details = ReservationBookingDetails(
                businessId: action.businessId,
                businessName: action.businessName,
                date: time.date,
                time: time.time,
                covers: covers,
                firstName: firstName,
                lastName: lastName,
                email: email,
                phone: phone,
                notes: notes.isEmpty ? nil : notes
            )
            onConfirm(details, nil)
            return
        }
        
        // Make the actual API call
        isLoading = true
        errorMessage = nil
        
        reservationCancellable = APIService.shared.makeReservation(
            roomId: room.id,
            businessId: action.businessId,
            businessName: action.businessName,
            date: time.date,
            time: time.time,
            covers: covers,
            firstName: firstName,
            lastName: lastName,
            email: email,
            phone: phone,
            notes: notes.isEmpty ? nil : notes
        )
        .receive(on: DispatchQueue.main)
        .sink(
            receiveCompletion: { [self] completion in
                isLoading = false
                if case .failure(let error) = completion {
                    if let apiError = error as? APIError {
                        errorMessage = apiError.localizedDescription
                    } else {
                        errorMessage = error.localizedDescription
                    }
                }
            },
            receiveValue: { [self] response in
                isLoading = false
                
                if response.success {
                    // Success! Store details and show confirmation state
                    let details = ReservationBookingDetails(
                        businessId: action.businessId,
                        businessName: action.businessName,
                        date: time.date,
                        time: time.time,
                        covers: covers,
                        firstName: firstName,
                        lastName: lastName,
                        email: email,
                        phone: phone,
                        notes: notes.isEmpty ? nil : notes
                    )
                    confirmedBookingDetails = details
                    reservationResponse = response
                    withAnimation {
                        showSuccessState = true
                    }
                } else {
                    // API returned error
                    errorMessage = response.error ?? "Failed to make reservation"
                }
            }
        )
    }
}

// MARK: - Supporting Views

struct DateChip: View {
    let date: Date
    let isSelected: Bool
    let onTap: () -> Void
    
    private var dayName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }
    
    private var dayNumber: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: date)
    }
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                Text(dayName)
                    .font(.caption)
                    .fontWeight(.medium)
                Text(dayNumber)
                    .font(.title3)
                    .fontWeight(.bold)
            }
            .frame(width: 56, height: 64)
            .background(isSelected ? Color(red: 0.4, green: 0.3, blue: 0.9) : Color(uiColor: .systemGray6))
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
}

struct TimeChip: View {
    let slot: ReservationTimeSlot
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            Text(slot.formattedTime)
                .font(.subheadline)
                .fontWeight(.medium)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(isSelected ? Color(red: 0.4, green: 0.3, blue: 0.9) : Color(uiColor: .systemGray6))
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

struct ReservationTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(12)
            .background(Color(uiColor: .systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Booking Details Model

struct ReservationBookingDetails {
    let businessId: String
    let businessName: String
    let date: String
    let time: String
    let covers: Int
    let firstName: String
    let lastName: String
    let email: String
    let phone: String
    let notes: String?
}

#Preview {
    let sampleAction = ReservationAction(
        type: .reservationPrompt,
        businessId: "test-restaurant",
        businessName: "Victor's French Bistro",
        businessImageUrl: nil,
        availableTimes: [
            ReservationTimeSlot(date: "2025-11-30", time: "18:00"),
            ReservationTimeSlot(date: "2025-11-30", time: "18:30"),
            ReservationTimeSlot(date: "2025-11-30", time: "19:00"),
            ReservationTimeSlot(date: "2025-12-01", time: "18:00"),
            ReservationTimeSlot(date: "2025-12-01", time: "19:00"),
        ],
        coversRange: ReservationCoversRange(minPartySize: 1, maxPartySize: 8),
        requestedDate: "2025-11-30",
        requestedTime: "19:00",
        requestedCovers: 2
    )
    
    let sampleUser = User(id: "test-owner", name: "John", isCurrentUser: true, firstName: "John", lastName: "Doe", email: "john@example.com")
    
    let sampleRoom = Room(
        id: "test-room",
        name: "Test Room",
        members: [sampleUser],
        messages: [],
        itinerary: [],
        isPublic: false,
        joinCode: "ABC123",
        ownerId: "test-owner"  // Same as sampleUser.id
    )
    
    return ReservationSheet(
        action: sampleAction,
        userProfile: sampleUser,
        room: sampleRoom,
        onConfirm: { _, _ in }
    )
}

