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
        let timeoutTask = Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
            if !isReady {
                await MainActor.run {
                    self.isReady = true
                    self.errorMessage = "Authentication service timed out"
                }
            }
        }
        
        _ = auth.addStateDidChangeListener { [weak self] _, user in
            Task {
                await MainActor.run {
                    self?.currentUser = user
                    self?.isAuthenticated = user != nil
                }

                if let user = user {
                    await self?.ensureUserDocument(for: user)

                    if !user.isEmailVerified {
                        await MainActor.run {
                            self?.isAuthenticated = false
                            self?.errorMessage = "Please verify your email"
                            try? self?.signOut()
                        }
                    }
                }

                await MainActor.run {
                    self?.isReady = true
                }
            }
        }
    }
    
    private func ensureUserDocument(for user: User) async {
        let userDocRef = firestore.collection("users").document(user.uid)
        
        do {
            let document = try await userDocRef.getDocument()
            
            if !document.exists {
                // Create a default username using email prefix
                let emailPrefix = user.email?.components(separatedBy: "@").first ?? "user"
                let defaultUsername = "\(emailPrefix)\(Int.random(in: 1000...9999))"
                
                let userData: [String: Any] = [
                    "username": defaultUsername,
                    "email": user.email ?? "",
                    "createdAt": FieldValue.serverTimestamp()
                ]
                
                try await userDocRef.setData(userData)
                
                await MainActor.run {
                    self.username = defaultUsername
                }
            } else if let username = document.data()?["username"] as? String {
                await MainActor.run {
                    self.username = username
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
            
            // For existing accounts, send verification email if not verified
            if !user.isEmailVerified {
                try await user.sendEmailVerification()
                throw NSError(domain: "AuthenticationError",
                            code: 1,
                            userInfo: [NSLocalizedDescriptionKey: "Please verify your email. A new verification email has been sent."])
            }
            
            await ensureUserDocument(for: user)
            await MainActor.run {
                self.currentUser = user
                self.isAuthenticated = true
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
            }
            throw error
        }
    }
    
    func signUp(email: String, password: String, username: String) async throws {
        do {
            // 1. Create Firebase Auth user first
            let result = try await auth.createUser(withEmail: email, password: password)
            let user = result.user

            // 2. NOW check if the username is taken
            let usernameQuery = try await firestore.collection("users")
                .whereField("username", isEqualTo: username)
                .getDocuments()

            if !usernameQuery.documents.isEmpty {
                // Clean up the just-created auth user
                try? await user.delete()
                throw NSError(domain: "AuthenticationError",
                              code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "Username already taken"])
            }

            // 3. Save user document
            let userData: [String: Any] = [
                "username": username,
                "email": email,
                "createdAt": FieldValue.serverTimestamp()
            ]

            try await firestore.collection("users").document(user.uid).setData(userData)

            // 4. Send verification
            try await user.sendEmailVerification()

            await MainActor.run {
                self.currentUser = user
                self.isAuthenticated = true
                self.username = username
            }

        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
            }
            throw error
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
}

extension AuthErrorCode {
    static let networkError = AuthErrorCode(rawValue: -1009)
} 