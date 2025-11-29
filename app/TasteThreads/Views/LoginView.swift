import SwiftUI
import AuthenticationServices
import CryptoKit

struct LoginView: View {
    @StateObject private var authService = AuthenticationService.shared
    @State private var email = ""
    @State private var password = ""
    @State private var isSignUp = false
    @State private var errorMessage: String?
    @State private var isLoading = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Logo or Title
                Text("TasteThreads")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundStyle(.red)
                    .padding(.bottom, 40)
                
                // Fields
                VStack(spacing: 16) {
                    TextField("Email", text: $email)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .textContentType(.emailAddress)
                        .autocapitalization(.none)
                        .keyboardType(.emailAddress)
                    
                    SecureField("Password", text: $password)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .textContentType(isSignUp ? .newPassword : .password)
                }
                .padding(.horizontal)
                
                if let error = errorMessage {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                }
                
                // Action Button
                Button(action: handleAction) {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Text(isSignUp ? "Sign Up" : "Sign In")
                            .fontWeight(.bold)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.red)
                .foregroundStyle(.white)
                .cornerRadius(10)
                .padding(.horizontal)
                .disabled(isLoading || email.isEmpty || password.isEmpty)
                
                // Toggle Mode
                Button(action: { isSignUp.toggle() }) {
                    Text(isSignUp ? "Already have an account? Sign In" : "Don't have an account? Sign Up")
                        .foregroundStyle(.secondary)
                }
                
                // Divider
                HStack {
                    Rectangle()
                        .frame(height: 1)
                        .foregroundStyle(.secondary.opacity(0.3))
                    Text("OR")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                        .padding(.horizontal, 8)
                    Rectangle()
                        .frame(height: 1)
                        .foregroundStyle(.secondary.opacity(0.3))
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                
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
                .frame(height: 50)
                .cornerRadius(10)
                .padding(.horizontal)
                
                Spacer()
            }
            .padding()
            .navigationBarHidden(true)
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
