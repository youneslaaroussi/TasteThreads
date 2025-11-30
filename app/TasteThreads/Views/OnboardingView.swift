//
//  OnboardingView.swift
//  TasteThreads
//

import SwiftUI
import PhotosUI

struct OnboardingView: View {
    @ObservedObject var onboardingManager = OnboardingManager.shared
    @State private var currentStep = 0
    @State private var userName = ""
    @State private var userBio = ""
    @State private var selectedPreferences: Set<String> = []
    @State private var selectedImage: UIImage?
    @State private var showImagePicker = false
    
    let onComplete: () -> Void
    
    private let totalSteps = 4
    
    // Warm color palette
    private let warmBackground = Color(red: 0.98, green: 0.96, blue: 0.93)
    private let warmAccent = Color(red: 0.76, green: 0.42, blue: 0.32) // Terracotta
    private let warmCardBg = Color.white
    
    var body: some View {
        ZStack {
            warmBackground.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Minimal header with step indicator
                HStack {
                    ForEach(0..<totalSteps, id: \.self) { index in
                        Circle()
                            .fill(index <= currentStep ? warmAccent : Color.black.opacity(0.1))
                            .frame(width: 8, height: 8)
                    }
                }
                .padding(.top, 20)
                .padding(.bottom, 8)
                
                // Content
                TabView(selection: $currentStep) {
                    WelcomeStep(accent: warmAccent, cardBg: warmCardBg, onNext: nextStep)
                        .tag(0)
                    
                    ProfileStep(
                        userName: $userName,
                        userBio: $userBio,
                        selectedImage: $selectedImage,
                        showImagePicker: $showImagePicker,
                        accent: warmAccent,
                        cardBg: warmCardBg,
                        onNext: nextStep
                    )
                    .tag(1)
                    
                    PreferencesStep(
                        selectedPreferences: $selectedPreferences,
                        accent: warmAccent,
                        cardBg: warmCardBg,
                        onNext: nextStep
                    )
                    .tag(2)
                    
                    CompleteStep(
                        userName: userName,
                        accent: warmAccent,
                        onComplete: finishOnboarding
                    )
                    .tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.3), value: currentStep)
            }
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(selectedImage: $selectedImage)
        }
    }
    
    private func nextStep() {
        withAnimation(.easeInOut(duration: 0.3)) {
            currentStep = min(currentStep + 1, totalSteps - 1)
        }
    }
    
    private func finishOnboarding() {
        onboardingManager.localUserName = userName
        onboardingManager.localBio = userBio
        onboardingManager.localPreferences = Array(selectedPreferences)
        
        if let image = selectedImage,
           let data = image.jpegData(compressionQuality: 0.7) {
            onboardingManager.localProfileImageData = data
        }
        
        onboardingManager.completeOnboarding()
        onComplete()
    }
}

// MARK: - Welcome Step
struct WelcomeStep: View {
    let accent: Color
    let cardBg: Color
    let onNext: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            
            // App icon / logo area
            VStack(spacing: 24) {
                Image("AIAvatar")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                
                VStack(spacing: 8) {
                    Text("TasteThreads")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundColor(.black)
                    
                    Text("Plan nights out with friends,\nwithout the group chat chaos.")
                        .font(.system(size: 16))
                        .foregroundColor(.black.opacity(0.5))
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }
            }
            
            Spacer()
            
            // Feature cards
            VStack(spacing: 12) {
                FeatureRow(icon: "sparkles", title: "Smart picks", description: "AI finds spots your whole group will love", accent: accent)
                FeatureRow(icon: "person.2", title: "Group-first", description: "Built for deciding together, not alone", accent: accent)
                FeatureRow(icon: "map", title: "Real plans", description: "Go from idea to itinerary in minutes", accent: accent)
            }
            .padding(.horizontal, 24)
            
            Spacer()
            
            // CTA
            VStack(spacing: 16) {
                Button(action: onNext) {
                    Text("Get Started")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(accent)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                
                Text("Takes about 1 minute")
                    .font(.system(size: 13))
                    .foregroundColor(.black.opacity(0.4))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    let accent: Color
    
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(accent)
                .frame(width: 44, height: 44)
                .background(accent.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.black)
                Text(description)
                    .font(.system(size: 14))
                    .foregroundColor(.black.opacity(0.5))
            }
            
            Spacer()
        }
        .padding(14)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
    }
}

// MARK: - Profile Step
struct ProfileStep: View {
    @Binding var userName: String
    @Binding var userBio: String
    @Binding var selectedImage: UIImage?
    @Binding var showImagePicker: Bool
    let accent: Color
    let cardBg: Color
    let onNext: () -> Void
    
    @FocusState private var focusedField: Field?
    
    enum Field { case name, bio }
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 32) {
                // Header
                VStack(spacing: 8) {
                    Text("Create your profile")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(.black)
                    Text("Help friends recognize you")
                        .font(.system(size: 16))
                        .foregroundColor(.black.opacity(0.5))
                }
                .padding(.top, 32)
                
                // Photo picker
                Button(action: { showImagePicker = true }) {
                    VStack(spacing: 12) {
                        if let image = selectedImage {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 100, height: 100)
                                .clipShape(Circle())
                        } else {
                            Circle()
                                .fill(Color.black.opacity(0.05))
                                .frame(width: 100, height: 100)
                                .overlay(
                                    Image(systemName: "camera")
                                        .font(.system(size: 28))
                                        .foregroundColor(.black.opacity(0.3))
                                )
                        }
                        
                        Text(selectedImage == nil ? "Add photo" : "Change photo")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(accent)
                    }
                }
                .buttonStyle(.plain)
                
                // Form fields
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Name")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.black.opacity(0.5))
                        
                        ZStack(alignment: .leading) {
                            if userName.isEmpty {
                                Text("What should we call you?")
                                    .font(.system(size: 16))
                                    .foregroundColor(.black.opacity(0.4))
                                    .padding(.horizontal, 16)
                            }
                            TextField("", text: $userName)
                                .font(.system(size: 16))
                                .foregroundColor(.black)
                                .padding(16)
                        }
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
                        .focused($focusedField, equals: .name)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Bio (optional)")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.black.opacity(0.5))
                        
                        ZStack(alignment: .leading) {
                            if userBio.isEmpty {
                                Text("Foodie? Coffee snob? Late-night eater?")
                                    .font(.system(size: 16))
                                    .foregroundColor(.black.opacity(0.4))
                                    .padding(.horizontal, 16)
                            }
                            TextField("", text: $userBio)
                                .font(.system(size: 16))
                                .foregroundColor(.black)
                                .padding(16)
                        }
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
                        .focused($focusedField, equals: .bio)
                    }
                }
                .padding(.horizontal, 24)
                
                Spacer(minLength: 60)
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                Divider().opacity(0.3)
                
                Button(action: onNext) {
                    Text(userName.isEmpty ? "Skip for now" : "Continue")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(userName.isEmpty ? .black.opacity(0.5) : .white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(userName.isEmpty ? Color.black.opacity(0.08) : accent)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(24)
            }
            .background(Color(red: 0.98, green: 0.96, blue: 0.93))
        }
        .onTapGesture { focusedField = nil }
    }
}

// MARK: - Preferences Step
struct PreferencesStep: View {
    @Binding var selectedPreferences: Set<String>
    let accent: Color
    let cardBg: Color
    let onNext: () -> Void
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 28) {
                // Header
                VStack(spacing: 8) {
                    Text("What do you like?")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(.black)
                    Text("Pick a few to help us personalize")
                        .font(.system(size: 16))
                        .foregroundColor(.black.opacity(0.5))
                }
                .padding(.top, 32)
                
                // Preference sections
                VStack(spacing: 24) {
                    PreferenceSection(
                        title: "Cuisines",
                        options: OnboardingManager.availableCuisines,
                        selected: $selectedPreferences,
                        accent: accent
                    )
                    
                    PreferenceSection(
                        title: "Dietary",
                        options: OnboardingManager.availableDietary,
                        selected: $selectedPreferences,
                        accent: accent
                    )
                    
                    PreferenceSection(
                        title: "Vibe",
                        options: OnboardingManager.availableVibes,
                        selected: $selectedPreferences,
                        accent: accent
                    )
                    
                    PreferenceSection(
                        title: "Budget",
                        options: OnboardingManager.availablePriceRanges,
                        selected: $selectedPreferences,
                        accent: accent
                    )
                }
                .padding(.horizontal, 24)
                
                Spacer(minLength: 100)
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                Divider().opacity(0.3)
                
                Button(action: onNext) {
                    Text(selectedPreferences.isEmpty ? "Skip" : "Continue")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(selectedPreferences.isEmpty ? .black.opacity(0.5) : .white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(selectedPreferences.isEmpty ? Color.black.opacity(0.08) : accent)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(24)
            }
            .background(Color(red: 0.98, green: 0.96, blue: 0.93))
        }
    }
}

struct PreferenceSection: View {
    let title: String
    let options: [String]
    @Binding var selected: Set<String>
    let accent: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.black.opacity(0.4))
                .textCase(.uppercase)
                .tracking(0.5)
            
            FlowLayout(spacing: 8) {
                ForEach(options, id: \.self) { option in
                    PreferenceChip(
                        text: option,
                        isSelected: selected.contains(option),
                        accent: accent,
                        onTap: {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                if selected.contains(option) {
                                    selected.remove(option)
                                } else {
                                    selected.insert(option)
                                }
                            }
                        }
                    )
                }
            }
        }
    }
}

struct PreferenceChip: View {
    let text: String
    let isSelected: Bool
    let accent: Color
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            Text(text)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(isSelected ? .white : .black.opacity(0.7))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(isSelected ? accent : Color.white)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(isSelected ? Color.clear : Color.black.opacity(0.08), lineWidth: 1)
                )
                .shadow(color: .black.opacity(isSelected ? 0.1 : 0.03), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Flow Layout
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x, y: bounds.minY + result.positions[index].y), proposal: .unspecified)
        }
    }
    
    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []
        
        init(in width: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var maxHeight: CGFloat = 0
            
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                
                if x + size.width > width && x > 0 {
                    x = 0
                    y += maxHeight + spacing
                    maxHeight = 0
                }
                
                positions.append(CGPoint(x: x, y: y))
                maxHeight = max(maxHeight, size.height)
                x += size.width + spacing
            }
            
            self.size = CGSize(width: width, height: y + maxHeight)
        }
    }
}

// MARK: - Complete Step
struct CompleteStep: View {
    let userName: String
    let accent: Color
    let onComplete: () -> Void
    
    @State private var showCheck = false
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            
            VStack(spacing: 32) {
                // Checkmark with animation
                ZStack {
                    Circle()
                        .fill(accent.opacity(0.12))
                        .frame(width: 120, height: 120)
                    
                    Circle()
                        .fill(accent)
                        .frame(width: 80, height: 80)
                    
                    Image(systemName: "checkmark")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundColor(.white)
                        .scaleEffect(showCheck ? 1 : 0.5)
                        .opacity(showCheck ? 1 : 0)
                }
                
                VStack(spacing: 12) {
                    Text("You're all set!")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundColor(.black)
                    
                    Text(userName.isEmpty
                         ? "Your preferences are saved.\nLet's find your next spot."
                         : "Nice to meet you, \(userName).\nLet's find your next spot.")
                        .font(.system(size: 16))
                        .foregroundColor(.black.opacity(0.5))
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }
            }
            
            Spacer()
            
            Button(action: onComplete) {
                Text("Start Exploring")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(accent)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6).delay(0.2)) {
                showCheck = true
            }
        }
    }
}

#Preview {
    OnboardingView(onComplete: {})
}
