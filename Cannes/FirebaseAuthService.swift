import Firebase
import FirebaseAuth

class FirebaseAuthService: ObservableObject {
    @Published var user: User?
    @Published var isAuthenticated = false
    
    init() {
        Auth.auth().addStateDidChangeListener { [weak self] _, user in
            self?.user = user
            self?.isAuthenticated = user != nil
        }
    }
    
    func signIn(email: String, password: String) async throws {
        let result = try await Auth.auth().signIn(withEmail: email, password: password)
        await MainActor.run {
            self.user = result.user
            self.isAuthenticated = true
        }
    }
    
    func signUp(email: String, password: String) async throws {
        let result = try await Auth.auth().createUser(withEmail: email, password: password)
        await MainActor.run {
            self.user = result.user
            self.isAuthenticated = true
        }
    }
    
    func signOut() throws {
        try Auth.auth().signOut()
        self.user = nil
        self.isAuthenticated = false
    }
}
