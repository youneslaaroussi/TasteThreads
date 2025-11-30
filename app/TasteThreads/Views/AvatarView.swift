//
//  AvatarView.swift
//  TasteThreads
//
//  Reusable avatar component for users and AI
//

import SwiftUI

struct AvatarView: View {
    let user: User?
    let size: CGFloat
    var showBorder: Bool = false
    
    // Accent colors
    private let aiGradient = LinearGradient(
        colors: [Color(red: 0.4, green: 0.3, blue: 0.9), Color(red: 0.2, green: 0.6, blue: 0.8)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    private let userGradient = LinearGradient(
        colors: [Color(red: 0.95, green: 0.3, blue: 0.3), Color(red: 0.95, green: 0.5, blue: 0.3)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    var body: some View {
        ZStack {
            if let user = user {
                if user.isAI {
                    // AI Avatar - Distinctive design
                    AIAvatarView(size: size)
                } else if let profileImageURL = user.profileImageURL {
                    // User has a profile picture
                    ProfileImageView(url: profileImageURL, size: size, fallbackInitial: String(user.name.prefix(1)))
                } else {
                    // Default user avatar with initials
                    InitialsAvatarView(
                        initial: String(user.name.prefix(1)),
                        size: size,
                        gradient: userGradient
                    )
                }
            } else {
                // Unknown user fallback - show generic user icon
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.gray.opacity(0.5), Color.gray.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: size, height: size)
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: size * 0.45, weight: .medium))
                            .foregroundStyle(.white)
                    )
            }
        }
        .overlay(
            showBorder ? Circle().stroke(Color.white, lineWidth: 2) : nil
        )
        .shadow(color: .black.opacity(showBorder ? 0.1 : 0), radius: 4, x: 0, y: 2)
    }
}

// MARK: - AI Avatar View
struct AIAvatarView: View {
    let size: CGFloat
    
    var body: some View {
        Image("AIAvatar")
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: size, height: size)
            .clipShape(Circle())
    }
}

// MARK: - Profile Image View (Remote URL)
struct ProfileImageView: View {
    let url: URL
    let size: CGFloat
    let fallbackInitial: String
    
    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            case .failure:
                // Fallback to initials on error
                InitialsAvatarView(
                    initial: fallbackInitial,
                    size: size,
                    gradient: LinearGradient(
                        colors: [Color(red: 0.95, green: 0.3, blue: 0.3), Color(red: 0.95, green: 0.5, blue: 0.3)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            case .empty:
                // Loading state
                Circle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: size, height: size)
                    .overlay(
                        ProgressView()
                            .tint(.gray)
                    )
            @unknown default:
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: size, height: size)
            }
        }
    }
}

// MARK: - Initials Avatar View
struct InitialsAvatarView: View {
    let initial: String
    let size: CGFloat
    let gradient: LinearGradient
    
    var body: some View {
        Circle()
            .fill(gradient)
            .frame(width: size, height: size)
            .overlay(
                Text(initial.uppercased())
                    .font(.system(size: size * 0.45, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            )
    }
}

#Preview {
    VStack(spacing: 20) {
        // AI Avatar
        AvatarView(user: User(id: User.aiUserId, name: "Tess (AI)", isCurrentUser: false), size: 64)
        
        // User with no profile pic
        AvatarView(user: User(id: "test", name: "John", isCurrentUser: true), size: 64)
        
        // Unknown user
        AvatarView(user: nil, size: 64)
        
        // AI Avatar small
        AvatarView(user: User(id: User.aiUserId, name: "Tess", isCurrentUser: false), size: 32)
    }
    .padding()
}

