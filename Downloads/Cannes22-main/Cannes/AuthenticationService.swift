import Foundation
import FirebaseAuth
import FirebaseFirestore

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
                    self.isAuthenticated = user != nil && user?.isEmailVerified == true
                }

                if let user = user {
                    await self.ensureUserDocument(for: user)

                    if !user.isEmailVerified {
                        await MainActor.run {
                            self.isAuthenticated = false
                            self.errorMessage = "Please verify your email"
                        }
                    }
                }

                await MainActor.run {
                    self.isReady = true
                }
            }
        }
    }
    
    private func ensureUserDocument(for user: User) async {
        let userDocRef = firestore.collection("users").document(user.uid)
        
        do {
            let document = try await userDocRef.getDocument()
            
            if !document.exists {
                // Only save email for now — username will be added later
                let userData: [String: Any] = [
                    "email": user.email ?? "",
                    "createdAt": FieldValue.serverTimestamp()
                ]
                try await userDocRef.setData(userData)
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