import SwiftUI
import FirebaseAuth
import FirebaseCore

struct AuthView: View {
    @StateObject private var authService = AuthenticationService.shared
    @State private var email = ""
    @State private var password = ""
    @State private var isSignUp = false
    @State private var isLoading = false
    @State private var showError = false
    @State private var showVerificationAlert = false
    @State private var showResetAlert = false
    
    var isFormValid: Bool {
        !email.isEmpty && !password.isEmpty && password.count >= 6
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
                try await authService.signUp(email: email, password: password)
                showVerificationAlert = true
            } else {
                try await authService.signIn(email: email, password: password)
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