import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseCore

class AuthenticationService: ObservableObject {
    static let shared = AuthenticationService()
    private let auth = Auth.auth()
    private let firestore = Firestore.firestore()
    
    @Published var currentUser: User?
    @Published var isAuthenticated = false
    @Published var errorMessage: String?
    @Published var username: String?
    @Published var isReady = false
    
    private init() {
        // Firebase is now configured in AppDelegate
        
        // Add more robust error handling and state management
        do {
            try auth.useUserAccessGroup(nil)
            print("Auth persistence configured successfully")
        } catch {
            print("Error configuring auth persistence: \(error)")
        }
        
        // Add a timeout for the auth state listener
        _ = Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
            if !isReady {
                await MainActor.run {
                    self.isReady = true
                    self.errorMessage = "Authentication service timed out"
                }
            }
        }
        
        _ = auth.addStateDidChangeListener { [weak self] _, user in
            Task { [weak self] in
                guard let self = self else { return }
                await MainActor.run {
                    self.currentUser = user
                    // Update authentication logic to handle email users only
                    self.isAuthenticated = self.isUserAuthenticated(user: user)
                }

                if let user = user {
                    await self.ensureUserDocument(for: user)

                    // Only check email verification for email users
                    if !self.isUserAuthenticated(user: user) {
                        await MainActor.run {
                            self.isAuthenticated = false
                            if user.email != nil && !user.isEmailVerified {
                                self.errorMessage = "Please verify your email"
                            } else {
                                self.errorMessage = "Authentication required"
                            }
                        }
                    }
                }

                await MainActor.run {
                    self.isReady = true
                }
            }
        }
    }
    
    // Helper method to determine if user is properly authenticated
    private func isUserAuthenticated(user: User?) -> Bool {
        guard let user = user else { return false }
        
        // Email users: Check if email is verified
        if user.email != nil {
            return user.isEmailVerified
        }
        
        // Fallback: user exists but unclear type
        return false
    }
    
    private func ensureUserDocument(for user: User) async {
        let userDocRef = firestore.collection("users").document(user.uid)
        
        do {
            let document = try await userDocRef.getDocument()
            
            if !document.exists {
                // Create user document with appropriate data
                var userData: [String: Any] = [
                    "createdAt": FieldValue.serverTimestamp(),
                    "movieCount": 0  // Initialize movie count for new users
                ]
                
                // Add email if available
                if let email = user.email {
                    userData["email"] = email
                }
                
                try await userDocRef.setData(userData)
                print("ensureUserDocument: Created new user document with movieCount: 0")
            } else {
                // Update existing document with new auth methods if needed
                var updateData: [String: Any] = [:]
                let existingData = document.data() ?? [:]
                
                // Add email if user just linked it
                if let email = user.email, existingData["email"] == nil {
                    updateData["email"] = email
                }
                
                // Initialize movieCount if it doesn't exist (for existing users)
                if existingData["movieCount"] == nil {
                    updateData["movieCount"] = 0
                    print("ensureUserDocument: Initializing movieCount for existing user")
                }
                
                if !updateData.isEmpty {
                    updateData["updatedAt"] = FieldValue.serverTimestamp()
                    try await userDocRef.updateData(updateData)
                }
                
                // Sync movie count for existing users
                await syncMovieCount(for: user.uid)
            }

            if let username = document.data()?["username"] as? String {
                await MainActor.run {
                    self.username = username
                }
            } else {
                await MainActor.run {
                    self.username = nil
                }
            }
        } catch {
            print("Error ensuring user document: \(error.localizedDescription)")
        }
    }
    
    // Sync movie count for existing users
    private func syncMovieCount(for userId: String) async {
        do {
            let snapshot = try await firestore.collection("users")
                .document(userId)
                .collection("rankings")
                .getDocuments()
            
            let movieCount = snapshot.documents.count
            
            try await firestore.collection("users")
                .document(userId)
                .updateData([
                    "movieCount": movieCount
                ])
            
            print("syncMovieCount: Synced movie count to \(movieCount) for user \(userId)")
        } catch {
            print("syncMovieCount: Error syncing movie count: \(error.localizedDescription)")
        }
    }
    
    func signIn(email: String, password: String) async throws {
        do {
            let result = try await Auth.auth().signIn(withEmail: email, password: password)
            let user = result.user
            
            if !user.isEmailVerified {
                try await user.sendEmailVerification()
                throw AuthError.custom("Please verify your email. A new verification email has been sent.")
            }
            
            await ensureUserDocument(for: user)
            await MainActor.run {
                self.currentUser = user
                self.isAuthenticated = true
            }
        } catch {
            throw mapAuthError(error)
        }
    }
    
    func signUp(email: String, password: String) async throws {
        do {
            let result = try await auth.createUser(withEmail: email, password: password)
            let user = result.user

            try await user.sendEmailVerification()

            await MainActor.run {
                self.errorMessage = "Please verify your email. A verification link has been sent."
                self.isAuthenticated = false
                self.currentUser = nil
            }

            try auth.signOut()

        } catch {
            throw mapAuthError(error)
        }
    }
    
    func signOut() throws {
        try Auth.auth().signOut()
        self.currentUser = nil
        self.isAuthenticated = false
    }
    
    func sendPasswordReset(email: String) async throws {
        do {
            try await Auth.auth().sendPasswordReset(withEmail: email)
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
            }
            throw error
        }
    }
    
    func changePassword(currentPassword: String, newPassword: String) async throws {
        guard let user = currentUser else {
            throw AuthError.custom("No user is currently signed in")
        }
        
        guard let email = user.email else {
            throw AuthError.custom("Unable to get user email")
        }
        
        // Reauthenticate user with current password
        let credential = EmailAuthProvider.credential(withEmail: email, password: currentPassword)
        
        do {
            try await user.reauthenticate(with: credential)
            try await user.updatePassword(to: newPassword)
        } catch {
            throw mapAuthError(error)
        }
    }
    
    func isUsernameAvailable(_ username: String) async throws -> Bool {
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        // Query Firestore to check if username exists
        let snapshot = try await firestore.collection("users")
            .whereField("username", isEqualTo: trimmedUsername)
            .getDocuments()
        
        return snapshot.documents.isEmpty
    }
    
    func changeUsername(to newUsername: String) async throws {
        guard let user = currentUser else {
            throw AuthError.custom("No user is currently signed in")
        }
        
        let trimmedUsername = newUsername.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        // Double-check username availability
        let isAvailable = try await isUsernameAvailable(trimmedUsername)
        guard isAvailable else {
            throw AuthError.custom("Username is already taken")
        }
        
        // Update username in Firestore
        let userDocRef = firestore.collection("users").document(user.uid)
        
        do {
            try await userDocRef.updateData([
                "username": trimmedUsername,
                "updatedAt": FieldValue.serverTimestamp()
            ])
            
            // Update local username
            await MainActor.run {
                self.username = trimmedUsername
            }
        } catch {
            throw AuthError.custom("Failed to update username: \(error.localizedDescription)")
        }
    }
    
    private func mapAuthError(_ error: Error) -> Error {
        let nsError = error as NSError

        switch nsError.code {
        case 17009, 17004:
            return AuthError.custom("Incorrect email or password.")
        case 17011:
            return AuthError.custom("No user found with this email.")
        case 17008:
            return AuthError.custom("The email address is badly formatted.")
        case 17007:
            return AuthError.custom("An account already exists with this email.")
        case 17026:
            return AuthError.custom("Password must be at least 6 characters.")
        case 17010:
            return AuthError.custom("Too many login attempts. Try again later.")
        case 17014:
            return AuthError.custom("Current password is incorrect.")
        case 17025:
            return AuthError.custom("The password is invalid or the user does not have a password.")
        case 17012:
            return AuthError.custom("This operation is sensitive and requires recent authentication. Please sign in again.")
        default:
            return AuthError.custom("Something went wrong. Please try again.")
        }
    }
}

extension AuthErrorCode {
    static let networkError = AuthErrorCode(rawValue: -1009)
}

enum AuthError: LocalizedError {
    case custom(String)

    var errorDescription: String? {
        switch self {
        case .custom(let message):
            return message
        }
    }
} 