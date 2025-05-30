import SwiftUI
import FirebaseFirestore

struct SetUsernameView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var authService = AuthenticationService.shared
    @State private var username = ""
    @State private var isLoading = false
    @State private var showError = false
    @State private var errorMessage = ""
    
    var body: some View {
        VStack {
            Text("You've verified your email. Now set your username.")
            Text("Choose a Username")
                .font(.title)
                .fontWeight(.bold)
            
            Text("This will be your unique identifier in the app")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            TextField("Username", text: $username)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .textContentType(.username)
                .autocapitalization(.none)
                .padding(.horizontal)
            
            Button(action: {
                Task {
                    await setUsername()
                }
            }) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Text("Set Username")
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(10)
            .disabled(username.count < 3 || isLoading)
            .padding(.horizontal)
        }
        .padding()
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }
    
    private func setUsername() async {
        guard let userId = authService.currentUser?.uid else { return }
        isLoading = true
        
        do {
            // Check if username is already taken
            let snapshot = try await Firestore.firestore().collection("users")
                .whereField("username", isEqualTo: username)
                .getDocuments()
            
            if !snapshot.documents.isEmpty {
                errorMessage = "Username already taken"
                showError = true
                isLoading = false
                return
            }
            
            // Save username
            try await Firestore.firestore().collection("users").document(userId).setData([
                "username": username
            ], merge: true)
            
            await MainActor.run {
                authService.username = username
                dismiss()
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
        
        isLoading = false
    }
} 