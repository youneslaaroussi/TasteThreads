import SwiftUI
import AuthenticationServices
import CryptoKit

struct LoginView: View {
    @StateObject private var authService = AuthenticationService.shared
    @Environment(\.dismiss) var dismiss
    @State private var email = ""
    @State private var password = ""
    @State private var isSignUp = false
    @State private var errorMessage: String?
    @State private var isLoading = false
    
    // Warm theme colors
    private let warmBackground = Color(red: 0.98, green: 0.96, blue: 0.93)
    private let warmAccent = Color(red: 0.76, green: 0.42, blue: 0.32)
    
    var body: some View {
        ZStack {
            warmBackground.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    Spacer()
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.black.opacity(0.4))
                            .frame(width: 32, height: 32)
                            .background(Color.black.opacity(0.05))
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 32) {
                        // Logo
                        VStack(spacing: 16) {
                            Image("AIAvatar")
                                .resizable()
                                .scaledToFill()
                                .frame(width: 72, height: 72)
                                .clipShape(RoundedRectangle(cornerRadius: 18))
                            
                            Text("TasteThreads")
                                .font(.system(size: 28, weight: .semibold))
                                .foregroundColor(.black)
                        }
                        .padding(.top, 24)
                        
                        // Form
                        VStack(spacing: 16) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Email")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.black.opacity(0.5))
                                
                                TextField("you@example.com", text: $email)
                                    .font(.system(size: 16))
                                    .textContentType(.emailAddress)
                                    .autocapitalization(.none)
                                    .keyboardType(.emailAddress)
                                    .padding(16)
                                    .background(Color.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
                            }
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Password")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.black.opacity(0.5))
                                
                                SecureField("••••••••", text: $password)
                                    .font(.system(size: 16))
                                    .textContentType(isSignUp ? .newPassword : .password)
                                    .padding(16)
                                    .background(Color.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
                            }
                        }
                        .padding(.horizontal, 24)
                        
                        // Error message
                        if let error = errorMessage {
                            Text(error)
                                .font(.system(size: 14))
                                .foregroundColor(Color(red: 0.9, green: 0.3, blue: 0.3))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                        }
                        
                        // Action Button
                        VStack(spacing: 16) {
                            Button(action: handleAction) {
                                if isLoading {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                } else {
                                    Text(isSignUp ? "Create Account" : "Sign In")
                                        .font(.system(size: 17, weight: .semibold))
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(email.isEmpty || password.isEmpty ? Color.black.opacity(0.08) : warmAccent)
                            .foregroundColor(email.isEmpty || password.isEmpty ? .black.opacity(0.4) : .white)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .disabled(isLoading || email.isEmpty || password.isEmpty)
                            
                            Button(action: { isSignUp.toggle() }) {
                                Text(isSignUp ? "Already have an account? **Sign In**" : "Don't have an account? **Sign Up**")
                                    .font(.system(size: 14))
                                    .foregroundColor(.black.opacity(0.5))
                            }
                        }
                        .padding(.horizontal, 24)
                        
                        // Divider
                        HStack(spacing: 16) {
                            Rectangle()
                                .frame(height: 1)
                                .foregroundColor(.black.opacity(0.08))
                            Text("or")
                                .font(.system(size: 13))
                                .foregroundColor(.black.opacity(0.4))
                            Rectangle()
                                .frame(height: 1)
                                .foregroundColor(.black.opacity(0.08))
                        }
                        .padding(.horizontal, 24)
                        
                        // Sign in with Apple
                        SignInWithAppleButton(
                            onRequest: { request in
                                let nonce = authService.startSignInWithAppleFlow()
                                request.requestedScopes = [.fullName, .email]
                                request.nonce = sha256(nonce)
                            },
                            onCompletion: { result in
                                switch result {
                                case .success(let authorization):
                                    if let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential {
                                        Task {
                                            isLoading = true
                                            errorMessage = nil
                                            do {
                                                try await authService.signInWithApple(authorization: appleIDCredential)
                                            } catch {
                                                errorMessage = error.localizedDescription
                                            }
                                            isLoading = false
                                        }
                                    }
                                case .failure(let error):
                                    errorMessage = error.localizedDescription
                                }
                            }
                        )
                        .signInWithAppleButtonStyle(.black)
                        .frame(height: 54)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .padding(.horizontal, 24)
                        
                        // Legal Links
                        VStack(spacing: 16) {
                            HStack(spacing: 24) {
                                Link("Privacy Policy", destination: URL(string: "https://github.com/youneslaaroussi/TasteThreads/blob/main/PRIVACY.md")!)
                                    .font(.system(size: 14))
                                    .foregroundColor(warmAccent)
                                
                                Text("•")
                                    .foregroundColor(.black.opacity(0.3))
                                
                                Link("Terms of Service", destination: URL(string: "https://github.com/youneslaaroussi/TasteThreads/blob/main/TERMS.md")!)
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
                        
                        Spacer(minLength: 20)
                    }
                }
            }
        }
        .navigationBarHidden(true)
        .onChange(of: authService.isAuthenticated) { _, isAuthenticated in
            if isAuthenticated {
                dismiss()
            }
        }
    }
    
    private func handleAction() {
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                if isSignUp {
                    try await authService.signUp(email: email, password: password)
                } else {
                    try await authService.signIn(email: email, password: password)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
    
    // Helper function to hash nonce for Sign in with Apple
    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        let hashString = hashedData.compactMap {
            String(format: "%02x", $0)
        }.joined()
        
        return hashString
    }
}

#Preview {
    LoginView()
}
