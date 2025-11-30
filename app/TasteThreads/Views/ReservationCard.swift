//
//  ReservationCard.swift
//  TasteThreads
//
//  Inline chat card showing reservation options
//

import SwiftUI

struct ReservationCard: View {
    let action: ReservationAction
    let onSelectTime: (ReservationTimeSlot) -> Void
    let onMoreOptions: () -> Void
    
    @State private var selectedCovers: Int
    
    private let accentGradient = LinearGradient(
        colors: [Color(red: 0.4, green: 0.3, blue: 0.9), Color(red: 0.2, green: 0.6, blue: 0.8)],
        startPoint: .leading,
        endPoint: .trailing
    )
    
    init(action: ReservationAction, onSelectTime: @escaping (ReservationTimeSlot) -> Void, onMoreOptions: @escaping () -> Void) {
        self.action = action
        self.onSelectTime = onSelectTime
        self.onMoreOptions = onMoreOptions
        self._selectedCovers = State(initialValue: action.requestedCovers ?? 2)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with restaurant info
            HStack(spacing: 12) {
                // Restaurant image
                if let imageUrl = action.businessImageUrl, let url = URL(string: imageUrl) {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Rectangle()
                            .fill(Color(uiColor: .systemGray5))
                            .overlay(ProgressView().tint(.secondary))
                    }
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(accentGradient.opacity(0.2))
                            .frame(width: 56, height: 56)
                        Image(systemName: "fork.knife")
                            .font(.title2)
                            .foregroundStyle(Color(red: 0.4, green: 0.3, blue: 0.9))
                    }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(action.businessName)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                    
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let date = action.requestedDate {
                            let slot = ReservationTimeSlot(date: date, time: action.requestedTime ?? "19:00")
                            Text(slot.formattedDate)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                Spacer()
                
                // Reservation badge
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                    Text("Book")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(red: 0.2, green: 0.7, blue: 0.4))
                .clipShape(Capsule())
            }
            
            Divider()
            
            // Party size selector
            HStack {
                Text("Party size")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                HStack(spacing: 0) {
                    Button(action: {
                        if selectedCovers > (action.coversRange?.minPartySize ?? 1) {
                            selectedCovers -= 1
                        }
                    }) {
                        Image(systemName: "minus")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(selectedCovers > (action.coversRange?.minPartySize ?? 1) ? .primary : .secondary)
                            .frame(width: 32, height: 32)
                            .background(Color(uiColor: .systemGray6))
                    }
                    .disabled(selectedCovers <= (action.coversRange?.minPartySize ?? 1))
                    
                    Text("\(selectedCovers)")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 40)
                    
                    Button(action: {
                        if selectedCovers < (action.coversRange?.maxPartySize ?? 10) {
                            selectedCovers += 1
                        }
                    }) {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(selectedCovers < (action.coversRange?.maxPartySize ?? 10) ? .primary : .secondary)
                            .frame(width: 32, height: 32)
                            .background(Color(uiColor: .systemGray6))
                    }
                    .disabled(selectedCovers >= (action.coversRange?.maxPartySize ?? 10))
                }
                .background(Color(uiColor: .systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            
            // Available time slots
            if let times = action.availableTimes, !times.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Available times")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    // Time slot buttons (show first 4)
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 8) {
                        ForEach(action.topTimeSlots(4)) { slot in
                            TimeSlotButton(slot: slot) {
                                // Create a modified action with the selected covers
                                onSelectTime(slot)
                            }
                        }
                    }
                }
            } else {
                // No times available
                HStack {
                    Image(systemName: "exclamationmark.circle")
                        .foregroundStyle(.orange)
                    Text("No times available for this date")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            }
            
            // More options button
            Button(action: onMoreOptions) {
                HStack {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 14))
                    Text("More dates & times")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                .foregroundStyle(Color(red: 0.4, green: 0.3, blue: 0.9))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color(red: 0.4, green: 0.3, blue: 0.9).opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(16)
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 2)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(red: 0.4, green: 0.3, blue: 0.9).opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Time Slot Button
struct TimeSlotButton: View {
    let slot: ReservationTimeSlot
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 2) {
                Text(slot.formattedTime)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                
                if slot.creditCardRequired {
                    HStack(spacing: 2) {
                        Image(systemName: "creditcard")
                            .font(.system(size: 8))
                        Text("Required")
                            .font(.system(size: 9))
                    }
                    .foregroundStyle(.orange)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color(uiColor: .systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(red: 0.4, green: 0.3, blue: 0.9).opacity(0.3), lineWidth: 1)
            )
        }
    }
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
            ReservationTimeSlot(date: "2025-11-30", time: "19:30"),
        ],
        coversRange: ReservationCoversRange(minPartySize: 1, maxPartySize: 8),
        requestedDate: "2025-11-30",
        requestedTime: "19:00",
        requestedCovers: 2
    )
    
    return ReservationCard(
        action: sampleAction,
        onSelectTime: { _ in },
        onMoreOptions: { }
    )
    .padding()
    .background(Color(uiColor: .systemGroupedBackground))
}

