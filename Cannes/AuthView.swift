import SwiftUI
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore

struct AuthView: View {
    @StateObject private var authService = AuthenticationService.shared
    @State private var email = ""
    @State private var password = ""
    @State private var username = ""
    @State private var isSignUp = false
    @State private var isLoading = false
    @State private var showError = false
    @State private var showVerificationAlert = false
    @State private var showResetAlert = false
    
    var isFormValid: Bool {
        if isSignUp {
            return !email.isEmpty && !password.isEmpty && !username.isEmpty && 
                   password.count >= 6 && username.count >= 3
        }
        return !email.isEmpty && !password.isEmpty && password.count >= 6
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text(isSignUp ? "Create Account" : "Welcome Back")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                VStack(spacing: 15) {
                    TextField("Email", text: $email)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .textContentType(.emailAddress)
                        .autocapitalization(.none)
                    
                    if isSignUp {
                        TextField("Username", text: $username)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .textContentType(.username)
                            .autocapitalization(.none)
                    }
                    
                    SecureField("Password", text: $password)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .textContentType(isSignUp ? .newPassword : .password)
                    
                    if !isSignUp {
                        Button("Forgot Password?") {
                            Task {
                                await handlePasswordReset()
                            }
                        }
                        .font(.footnote)
                        .foregroundColor(.blue)
                    }
                }
                .padding(.horizontal)
                
                Button(action: {
                    Task {
                        await handleAuthentication()
                    }
                }) {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Text(isSignUp ? "Sign Up" : "Sign In")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(isFormValid ? Color.blue : Color.gray)
                .foregroundColor(.white)
                .cornerRadius(10)
                .disabled(!isFormValid || isLoading)
                .padding(.horizontal)
                
                Button(action: { isSignUp.toggle() }) {
                    Text(isSignUp ? "Already have an account? Sign In" : "Don't have an account? Sign Up")
                        .foregroundColor(.blue)
                }
            }
            .padding()
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(authService.errorMessage ?? "An error occurred")
            }
            .alert("Verification Email Sent", isPresented: $showVerificationAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Please check your inbox before signing in.")
            }
            .alert("Password Reset", isPresented: $showResetAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Password reset email sent. Please check your inbox.")
            }
        }
    }
    
    private func handleAuthentication() async {
        isLoading = true
        do {
            if isSignUp {
                // First create the auth user
                try await authService.signUp(email: email, password: password, username: username)
                
                // Then create the user document using the UID
                if let user = Auth.auth().currentUser {
                    let db = Firestore.firestore()
                    try await db.collection("users").document(user.uid).setData([
                        "username": username,
                        "email": email,
                        "createdAt": FieldValue.serverTimestamp()
                    ])
                }
                showVerificationAlert = true
                // Sign out the user until they verify their email
                try await authService.signOut()
            } else {
                // Check if email is verified before signing in
                let user = try await authService.signIn(email: email, password: password)
                if !user.isEmailVerified {
                    try await authService.signOut()
                    throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Please verify your email before signing in."])
                }
            }
        } catch {
            showError = true
        }
        isLoading = false
    }
    
    private func handlePasswordReset() async {
        isLoading = true
        do {
            try await authService.sendPasswordReset(email: email)
            showResetAlert = true
        } catch {
            showError = true
        }
        isLoading = false
    }
} 