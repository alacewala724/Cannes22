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
    
    private init() {
        auth.addStateDidChangeListener { [weak self] _, user in
            self?.currentUser = user
            self?.isAuthenticated = user != nil
            if let user = user {
                // When user signs in, ensure they have a username document
                Task {
                    await self?.ensureUserDocument(for: user)
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
            await ensureUserDocument(for: result.user)
            await MainActor.run {
                self.currentUser = result.user
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
            // Check if username already exists
            let usernameQuery = try await firestore.collection("users")
                .whereField("username", isEqualTo: username)
                .getDocuments()
            
            if !usernameQuery.documents.isEmpty {
                throw NSError(domain: "AuthenticationError", 
                             code: 1, 
                             userInfo: [NSLocalizedDescriptionKey: "Username already taken"])
            }
            
            // Create the auth user first
            let result = try await auth.createUser(withEmail: email, password: password)
            let user = result.user
            
            // Create user document with username
            let userData: [String: Any] = [
                "username": username,
                "email": email,
                "createdAt": FieldValue.serverTimestamp()
            ]
            
            do {
                try await firestore.collection("users").document(user.uid).setData(userData, merge: false)
            } catch {
                // If Firestore write fails, delete the created auth user
                try? await user.delete()
                throw NSError(domain: "AuthenticationError",
                             code: 2,
                             userInfo: [NSLocalizedDescriptionKey: "Failed to create user profile. Please try again."])
            }
            
            // Send verification email
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
    
    var isAuthenticated: Bool {
        if let user = Auth.auth().currentUser {
            return user.isEmailVerified
        }
        return false
    }
}

extension AuthErrorCode {
    static let networkError = AuthErrorCode(rawValue: -1009)
} 