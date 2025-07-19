import SwiftUI
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore

enum AuthMode {
    case signIn
    case signUp
}

struct AuthView: View {
    @EnvironmentObject var authService: AuthenticationService
    @State private var email = ""
    @State private var password = ""
    @State private var authMode: AuthMode = .signIn
    @State private var isLoading = false
    @State private var showError = false
    @State private var showVerificationAlert = false
    @State private var showResetAlert = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Logo and Title
                VStack(spacing: 16) {
                    Text("🎬")
                        .font(.system(size: 80))
                    
                    Text("Cannes")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("Your personal movie ranking")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 40)
                
                Spacer()
                
                // Authentication Form
                VStack(spacing: 20) {
                    emailAuthForm
                }
                .padding(.horizontal, 24)
                
                Spacer()
                
                // Mode switcher
                authModeSwitcher
            }
            .navigationBarHidden(true)
        }
        .alert("Verification Required", isPresented: $showVerificationAlert) {
            Button("OK") { }
        } message: {
            Text("Please check your email and click the verification link before signing in.")
        }
        .alert("Password Reset", isPresented: $showResetAlert) {
            Button("OK") { }
        } message: {
            Text("Password reset email sent. Check your inbox.")
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(authService.errorMessage ?? "An unknown error occurred")
        }
        .onChange(of: authService.errorMessage) { message in
            if message != nil {
                showError = true
            }
        }
    }
    
    private var emailAuthForm: some View {
        VStack(spacing: 16) {
            TextField("Email", text: $email)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .textContentType(.emailAddress)
                .autocapitalization(.none)
                .keyboardType(.emailAddress)
            
            SecureField("Password", text: $password)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .textContentType(authMode == .signUp ? .newPassword : .password)
            
            Button(action: {
                Task {
                    await handleAuthentication()
                }
            }) {
                HStack {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                    }
                    Text(authMode == .signUp ? "Sign Up" : "Sign In")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.accentColor)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .disabled(isLoading || email.isEmpty || password.isEmpty)
            
            if authMode == .signIn {
                Button("Forgot Password?") {
                    Task {
                        await handlePasswordReset()
                    }
                }
                .font(.subheadline)
                .foregroundColor(.accentColor)
            }
        }
    }
    
    private var authModeSwitcher: some View {
        HStack {
            Text(authMode == .signIn ? "Don't have an account?" : "Already have an account?")
                .foregroundColor(.secondary)
            
            Button(authMode == .signIn ? "Sign Up" : "Sign In") {
                authMode = authMode == .signIn ? .signUp : .signIn
                email = ""
                password = ""
                authService.errorMessage = nil
            }
            .foregroundColor(.accentColor)
        }
        .font(.subheadline)
        .padding(.bottom, 20)
    }
    
    private func handleAuthentication() async {
        isLoading = true
        authService.errorMessage = nil
        
        do {
            if authMode == .signUp {
                try await authService.signUp(email: email, password: password)
            } else {
                try await authService.signIn(email: email, password: password)
            }
        } catch {
            authService.errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    private func handlePasswordReset() async {
        isLoading = true
        authService.errorMessage = nil
        
        do {
            try await authService.sendPasswordReset(email: email)
            showResetAlert = true
        } catch {
            authService.errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
} 