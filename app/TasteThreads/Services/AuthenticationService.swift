import Foundation
import FirebaseAuth
import FirebaseFirestore
import Combine
import AuthenticationServices

class AuthenticationService: ObservableObject {
    static let shared = AuthenticationService()
    
    @Published var user: FirebaseAuth.User?
    @Published var isAuthenticated = false
    @Published var errorMessage: String?
    
    private var handle: AuthStateDidChangeListenerHandle?
    
    init() {
        setupAuthListener()
    }
    
    private func setupAuthListener() {
        handle = Auth.auth().addStateDidChangeListener { [weak self] auth, user in
            DispatchQueue.main.async {
                self?.user = user
                self?.isAuthenticated = user != nil
                
                if let user = user {
                    // Refresh token to ensure we have a valid one for API calls
                    user.getIDToken { token, error in
                        if let error = error {
                            print("Error getting ID token: \(error)")
                        } else {
                            print("Got ID token for user: \(user.uid)")
                        }
                    }
                }
            }
        }
    }
    
    func signIn(email: String, password: String) async throws {
        do {
            let result = try await Auth.auth().signIn(withEmail: email, password: password)
            print("Signed in: \(result.user.uid)")
        } catch {
            print("Sign in error: \(error)")
            throw error
        }
    }
    
    func signUp(email: String, password: String) async throws {
        do {
            let result = try await Auth.auth().createUser(withEmail: email, password: password)
            print("Created user: \(result.user.uid)")
            
            // Create user profile in Firestore
            try await createFirestoreProfile(user: result.user)
        } catch {
            print("Sign up error: \(error)")
            throw error
        }
    }
    
    func signInWithApple(authorization: ASAuthorizationAppleIDCredential) async throws {
        guard let nonce = currentNonce else {
            throw NSError(domain: "AuthenticationService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid state: A login callback was received, but no login request was sent."])
        }
        
        guard let appleIDToken = authorization.identityToken,
              let idTokenString = String(data: appleIDToken, encoding: .utf8) else {
            throw NSError(domain: "AuthenticationService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unable to fetch identity token"])
        }
        
        let credential = OAuthProvider.appleCredential(withIDToken: idTokenString,
                                                       rawNonce: nonce,
                                                       fullName: authorization.fullName)
        
        let result = try await Auth.auth().signIn(with: credential)
        print("Signed in with Apple: \(result.user.uid)")
        
        // Update display name if provided (only available on first sign in)
        if let fullName = authorization.fullName {
            let displayName = [fullName.givenName, fullName.familyName]
                .compactMap { $0 }
                .joined(separator: " ")
            
            if !displayName.isEmpty {
                let changeRequest = result.user.createProfileChangeRequest()
                changeRequest.displayName = displayName
                try await changeRequest.commitChanges()
            }
        }
        
        // Create user profile in Firestore if it doesn't exist
        try await createFirestoreProfile(user: result.user)
        
        // Clear nonce after successful sign in
        currentNonce = nil
    }
    
    // Nonce for Sign in with Apple
    private var currentNonce: String?
    
    func startSignInWithAppleFlow() -> String {
        let nonce = randomNonceString()
        currentNonce = nonce
        return nonce
    }
    
    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] =
        Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length
        
        while remainingLength > 0 {
            var random: UInt8 = 0
            let errorCode = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
            if errorCode != errSecSuccess {
                fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(errorCode)")
            }
            
            if random < UInt8(charset.count) {
                result.append(charset[Int(random)])
                remainingLength -= 1
            }
        }
        
        return result
    }
    
    func signOut() throws {
        try Auth.auth().signOut()
    }
    
    func getIDToken() async throws -> String {
        guard let user = Auth.auth().currentUser else {
            throw NSError(domain: "AuthenticationService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not logged in"])
        }
        return try await user.getIDToken()
    }
    
    private func createFirestoreProfile(user: FirebaseAuth.User) async throws {
        let db = Firestore.firestore()
        let userRef = db.collection("users").document(user.uid)
        
        // Check if user document already exists
        let document = try await userRef.getDocument()
        
        if !document.exists {
            // Only create if it doesn't exist
            var data: [String: Any] = [
                "uid": user.uid,
                "createdAt": FieldValue.serverTimestamp()
            ]
            
            if let email = user.email {
                data["email"] = email
            }
            
            if let displayName = user.displayName {
                data["displayName"] = displayName
            }
            
            try await userRef.setData(data)
        } else {
            // Update existing document with any new information
            var updateData: [String: Any] = [:]
            
            if let email = user.email, email.isEmpty == false {
                updateData["email"] = email
            }
            
            if let displayName = user.displayName, displayName.isEmpty == false {
                updateData["displayName"] = displayName
            }
            
            if !updateData.isEmpty {
                try await userRef.updateData(updateData)
            }
        }
    }
    
    deinit {
        if let handle = handle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }
}
