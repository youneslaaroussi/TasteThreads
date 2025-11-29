import SwiftUI

struct ItineraryView: View {
    @StateObject private var viewModel = ItineraryViewModel()
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(viewModel.itinerary) { item in
                    ItineraryCard(item: item)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }
                .onMove(perform: viewModel.moveItem)
                .onDelete(perform: viewModel.deleteItem)
            }
            .listStyle(.plain)
            .navigationTitle("Itinerary")
            .toolbar {
                EditButton()
            }
        }
    }
}

struct ItineraryCard: View {
    let item: ItineraryItem
    
    var body: some View {
        HStack(spacing: 12) {
            // Image / Map Placeholder
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.2))
                .frame(width: 80, height: 80)
                .overlay(
                    Image(systemName: iconForType(item.type))
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                )
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(item.type.rawValue.uppercased())
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    if let time = item.time {
                        Text(time, style: .time)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Text(item.location.name)
                    .font(.headline)
                
                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                        .font(.caption)
                    Text(String(format: "%.1f", item.location.rating))
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Text("•")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    if let details = item.location.yelpDetails {
                        Text(details.price)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("•")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(details.categories.first ?? "")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(item.location.address)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                
                if let notes = item.notes {
                    Text(notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .italic()
                        .lineLimit(1)
                        .padding(.top, 2)
                }
            }
        }
        .padding(12)
        .background(Color(uiColor: .systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.gray.opacity(0.1), lineWidth: 1)
        )
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
}

#Preview {
    ItineraryView()
}
