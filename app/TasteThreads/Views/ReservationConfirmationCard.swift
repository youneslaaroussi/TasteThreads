//
//  ReservationConfirmationCard.swift
//  TasteThreads
//
//  Confirmation card shown after successful reservation
//

import SwiftUI
import EventKit

struct ReservationConfirmationCard: View {
    let action: ReservationAction
    
    @State private var showCalendarAlert = false
    @State private var calendarMessage = ""
    @State private var showSuccessAnimation = true
    
    private let successGreen = Color(red: 0.2, green: 0.7, blue: 0.4)
    private let warmAccent = Color(red: 0.76, green: 0.42, blue: 0.32)
    
    var body: some View {
        VStack(spacing: 0) {
            // Business image header
            if let imageUrl = action.businessImageUrl, let url = URL(string: imageUrl) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure:
                        businessPlaceholderImage
                    case .empty:
                        ZStack {
                            Rectangle().fill(Color(uiColor: .systemGray5))
                            ProgressView().tint(.secondary)
                        }
                    @unknown default:
                        businessPlaceholderImage
                    }
                }
                .frame(height: 120)
                .clipped()
                .overlay(alignment: .topTrailing) {
                    // Success badge
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                        Text("Confirmed")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(successGreen)
                    .clipShape(Capsule())
                    .padding(12)
                }
            } else {
                // No image - show compact header
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(successGreen)
                            .frame(width: 48, height: 48)
                        
                        Image(systemName: "checkmark")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(.white)
                            .scaleEffect(showSuccessAnimation ? 1.0 : 0.5)
                            .opacity(showSuccessAnimation ? 1.0 : 0)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Reservation Confirmed!")
                            .font(.headline)
                            .fontWeight(.bold)
                        
                        Text(action.businessName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                }
                .padding(16)
            }
            
            // Content section
            VStack(spacing: 16) {
                // Restaurant info (when image is shown)
                if action.businessImageUrl != nil {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(action.businessName)
                                .font(.headline)
                                .fontWeight(.bold)
                                .lineLimit(1)
                            
                            if let rating = action.businessRating {
                                HStack(spacing: 4) {
                                    Image(systemName: "star.fill")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.orange)
                                    Text(String(format: "%.1f", rating))
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                }
                            }
                        }
                        
                        Spacer()
                        
                        // Success indicator for image variant
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(successGreen)
                    }
                }
                
                Divider()
                
                // Reservation details
                VStack(spacing: 12) {
                    DetailRow(icon: "calendar", label: "Date", value: formattedDate)
                    DetailRow(icon: "clock", label: "Time", value: formattedTime)
                    DetailRow(icon: "person.2", label: "Party size", value: "\(action.confirmedCovers ?? 2) guests")
                    
                    if let reservationId = action.reservationId {
                        DetailRow(icon: "number", label: "Confirmation", value: String(reservationId.prefix(12)).uppercased())
                    }
                    
                    if let address = action.businessAddress {
                        DetailRow(icon: "mappin.circle", label: "Address", value: address)
                    }
                    
                    if let phone = action.businessPhone {
                        DetailRow(icon: "phone", label: "Phone", value: phone)
                    }
                }
                
                Divider()
                
                // Action buttons
                VStack(spacing: 10) {
                    // Add to Calendar - full width
                    Button(action: addToCalendar) {
                        HStack {
                            Image(systemName: "calendar.badge.plus")
                                .font(.system(size: 14))
                            Text("Add to Calendar")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(warmAccent)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    
                    HStack(spacing: 10) {
                        // Call restaurant
                        if let phone = action.businessPhone, let url = URL(string: "tel:\(phone.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "-", with: ""))") {
                            Link(destination: url) {
                                HStack {
                                    Image(systemName: "phone.fill")
                                        .font(.system(size: 14))
                                    Text("Call")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                }
                                .foregroundStyle(warmAccent)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(warmAccent.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                        
                        // View on Yelp
                        if let urlString = action.confirmationUrl ?? action.businessUrl, let url = URL(string: urlString) {
                            Link(destination: url) {
                                HStack {
                                    Image(systemName: "arrow.up.right.square")
                                        .font(.system(size: 14))
                                    Text("View on Yelp")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                }
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color(red: 0.85, green: 0.11, blue: 0.09))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 2)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(successGreen.opacity(0.3), lineWidth: 2)
        )
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6).delay(0.1)) {
                showSuccessAnimation = true
            }
        }
        .alert("Calendar", isPresented: $showCalendarAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(calendarMessage)
        }
    }
    
    private var businessPlaceholderImage: some View {
        ZStack {
            Rectangle().fill(warmAccent.opacity(0.1))
            Image(systemName: "fork.knife")
                .font(.system(size: 40))
                .foregroundStyle(warmAccent.opacity(0.4))
        }
        .frame(height: 120)
    }
    
    // MARK: - Formatted Values
    
    private var formattedDate: String {
        guard let date = action.confirmedDate else { return "N/A" }
        let slot = ReservationTimeSlot(date: date, time: action.confirmedTime ?? "19:00")
        return slot.formattedDate
    }
    
    private var formattedTime: String {
        guard let time = action.confirmedTime else { return "N/A" }
        let slot = ReservationTimeSlot(date: action.confirmedDate ?? "", time: time)
        return slot.formattedTime
    }
    
    // MARK: - Calendar Integration
    
    private func addToCalendar() {
        let eventStore = EKEventStore()
        
        eventStore.requestFullAccessToEvents { granted, error in
            DispatchQueue.main.async {
                if granted {
                    createCalendarEvent(eventStore: eventStore)
                } else {
                    calendarMessage = "Please enable calendar access in Settings to add this reservation."
                    showCalendarAlert = true
                }
            }
        }
    }
    
    private func createCalendarEvent(eventStore: EKEventStore) {
        guard let dateStr = action.confirmedDate,
              let timeStr = action.confirmedTime else {
            calendarMessage = "Could not create event - missing date/time information."
            showCalendarAlert = true
            return
        }
        
        // Parse date and time
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        guard let startDate = formatter.date(from: "\(dateStr) \(timeStr)") else {
            calendarMessage = "Could not parse reservation date/time."
            showCalendarAlert = true
            return
        }
        
        let event = EKEvent(eventStore: eventStore)
        event.title = "Dinner at \(action.businessName)"
        event.startDate = startDate
        event.endDate = startDate.addingTimeInterval(2 * 60 * 60) // 2 hours
        event.notes = """
        Reservation for \(action.confirmedCovers ?? 2) guests
        Confirmation: \(action.reservationId ?? "N/A")
        
        Booked via TasteThreads
        """
        
        // Add reminder 2 hours before
        let alarm = EKAlarm(relativeOffset: -2 * 60 * 60)
        event.addAlarm(alarm)
        
        event.calendar = eventStore.defaultCalendarForNewEvents
        
        do {
            try eventStore.save(event, span: .thisEvent)
            calendarMessage = "Reservation added to your calendar!"
            showCalendarAlert = true
        } catch {
            calendarMessage = "Could not save to calendar: \(error.localizedDescription)"
            showCalendarAlert = true
        }
    }
}

// MARK: - Detail Row

struct DetailRow: View {
    let icon: String
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 24)
            
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Spacer()
            
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
        }
    }
}

#Preview("With Image") {
    let sampleAction = ReservationAction(
        type: .reservationConfirmed,
        businessId: "allora-fifth-ave-new-york",
        businessName: "Allora Fifth Ave",
        businessImageUrl: "https://s3-media0.fl.yelpcdn.com/bphoto/abc123/o.jpg",
        businessAddress: "292 5th Ave, New York, NY 10001",
        businessPhone: "+1 646-928-5198",
        businessRating: 4.3,
        businessUrl: "https://www.yelp.com/biz/allora-fifth-ave-new-york",
        reservationId: "TEST-RES-ABC123DEF",
        confirmationUrl: "https://www.yelp.com/reservations/confirmed/abc123",
        confirmedDate: "2025-12-01",
        confirmedTime: "19:00",
        confirmedCovers: 2
    )
    
    return ReservationConfirmationCard(action: sampleAction)
        .padding()
        .background(Color(uiColor: .systemGroupedBackground))
}

#Preview("Without Image") {
    let sampleAction = ReservationAction(
        type: .reservationConfirmed,
        businessId: "test-restaurant",
        businessName: "Victor's French Bistro",
        businessAddress: "123 Main St, San Francisco, CA",
        businessPhone: "+1 415-555-1234",
        businessRating: 4.5,
        reservationId: "abc123def456",
        confirmationUrl: "https://www.yelp.com/reservations/confirmed/abc123",
        confirmedDate: "2025-11-30",
        confirmedTime: "19:00",
        confirmedCovers: 4
    )
    
    return ReservationConfirmationCard(action: sampleAction)
        .padding()
        .background(Color(uiColor: .systemGroupedBackground))
}

