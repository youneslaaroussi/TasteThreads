//
//  SignInPromptView.swift
//  TasteThreads
//
//  Shown in tabs when user is not authenticated
//

import SwiftUI

struct SignInPromptView: View {
    let title: String
    let subtitle: String
    let icon: String
    let onSignIn: () -> Void
    
    // Warm theme colors
    private let warmBackground = Color(red: 0.98, green: 0.96, blue: 0.93)
    private let warmAccent = Color(red: 0.76, green: 0.42, blue: 0.32)
    
    var body: some View {
        ZStack {
            warmBackground.ignoresSafeArea()
            
            VStack(spacing: 32) {
                Spacer()
                
                // Icon
                ZStack {
                    Circle()
                        .fill(warmAccent.opacity(0.12))
                        .frame(width: 100, height: 100)
                    
                    Image(systemName: icon)
                        .font(.system(size: 40, weight: .medium))
                        .foregroundColor(warmAccent)
                }
                
                VStack(spacing: 12) {
                    Text(title)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(.black)
                    
                    Text(subtitle)
                        .font(.system(size: 16))
                        .foregroundColor(.black.opacity(0.5))
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .padding(.horizontal, 32)
                }
                
                Button(action: onSignIn) {
                    HStack(spacing: 8) {
                        Image(systemName: "person.badge.key.fill")
                            .font(.system(size: 16, weight: .medium))
                        Text("Sign In")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(warmAccent)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(.horizontal, 48)
                
                // Legal Links
                VStack(spacing: 16) {
                    HStack(spacing: 24) {
                        Link("Privacy Policy", destination: URL(string: "https://raw.githubusercontent.com/youneslaaroussi/TasteThreads/main/PRIVACY.md")!)
                            .font(.system(size: 14))
                            .foregroundColor(warmAccent)
                        
                        Text("•")
                            .foregroundColor(.black.opacity(0.3))
                        
                        Link("Terms of Service", destination: URL(string: "https://raw.githubusercontent.com/youneslaaroussi/TasteThreads/main/TERMS.md")!)
                            .font(.system(size: 14))
                            .foregroundColor(warmAccent)
                    }
                    
                    // Powered by Yelp
                    HStack(spacing: 6) {
                        Text("Powered by")
                            .font(.system(size: 12))
                            .foregroundColor(.black.opacity(0.4))
                        
                        Image(systemName: "star.fill")
                            .font(.system(size: 10))
                            .foregroundColor(warmAccent)
                        
                        Text("Yelp")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(warmAccent)
                    }
                }
                .padding(.top, 32)
                .padding(.bottom, 40)
                
                Spacer()
            }
        }
    }
}

// MARK: - Specific Prompt Views

struct ChatSignInPromptView: View {
    let onSignIn: () -> Void
    
    var body: some View {
        SignInPromptView(
            title: "Chat with Tess",
            subtitle: "Sign in to chat with our AI assistant and get personalized restaurant recommendations",
            icon: "message.fill",
            onSignIn: onSignIn
        )
    }
}

struct ProfileSignInPromptView: View {
    let onSignIn: () -> Void
    
    var body: some View {
        SignInPromptView(
            title: "Your Taste Profile",
            subtitle: "Sign in to save your favorite places, track discoveries, and sync across devices",
            icon: "person.circle.fill",
            onSignIn: onSignIn
        )
    }
}

#Preview {
    SignInPromptView(
        title: "Sign In Required",
        subtitle: "Please sign in to access this feature",
        icon: "lock.fill",
        onSignIn: {}
    )
}
