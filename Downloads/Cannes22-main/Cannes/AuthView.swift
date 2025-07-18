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
            switch authMode {
            case .signIn:
                Text("Don't have an account?")
                    .foregroundColor(.secondary)
                Button("Sign Up") {
                    authMode = .signUp
                    password = ""
                }
                .foregroundColor(.accentColor)
            case .signUp:
                Text("Already have an account?")
                    .foregroundColor(.secondary)
                Button("Sign In") {
                    authMode = .signIn
                    password = ""
                }
                .foregroundColor(.accentColor)
            }
        }
        .font(.subheadline)
        .padding(.bottom, 40)
    }
    
    private func handleAuthentication() async {
        isLoading = true
        do {
            if authMode == .signUp {
                try await withTimeout(seconds: 10) {
                    try await authService.signUp(email: email, password: password)
                }
                showVerificationAlert = true
                try authService.signOut()
            } else {
                try await withTimeout(seconds: 10) {
                    try await authService.signIn(email: email, password: password)
                }
            }
        } catch {
            if let err = error as? LocalizedError {
                authService.errorMessage = err.errorDescription
            } else {
                authService.errorMessage = "Something went wrong. Please try again."
            }
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
    
    // Add timeout helper
    private func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw NSError(domain: "TimeoutError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Operation timed out"])
            }
            
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
} 