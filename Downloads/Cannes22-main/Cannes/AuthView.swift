import SwiftUI
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import UserNotifications

enum AuthMode {
    case signIn
    case signUp
    case phoneSignIn
    case phoneSignUp
    case phoneVerification
    case phoneVerificationSignUp
}

struct AuthView: View {
    @EnvironmentObject var authService: AuthenticationService
    @State private var email = ""
    @State private var password = ""
    @State private var phoneNumber = ""
    @State private var verificationCode = ""
    @State private var authMode: AuthMode = .signIn
    @State private var isLoading = false
    @State private var showError = false
    @State private var showVerificationAlert = false
    @State private var showResetAlert = false
    @State private var selectedCountry = CountryCode.popular[0] // Default to US
    @State private var showingCountryPicker = false
    
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
                    switch authMode {
                    case .signIn, .signUp:
                        emailAuthForm
                    case .phoneSignIn, .phoneSignUp:
                        phoneNumberForm
                    case .phoneVerification, .phoneVerificationSignUp:
                        verificationCodeForm
                    }
                }
                .padding(.horizontal, 24)
                
                Spacer()
                
                // Phone authentication options
                if authMode == .signIn || authMode == .signUp {
                    alternativeSignInOptions
                }
                
                // Mode switcher
                authModeSwitcher
            }
            .navigationBarHidden(true)
            .onTapGesture {
                // Dismiss keyboard when tapping outside
                hideKeyboard()
            }
            .overlay(
                // Back button overlay for phone auth screens
                Group {
                    if authMode == .phoneSignIn || authMode == .phoneSignUp || authMode == .phoneVerification || authMode == .phoneVerificationSignUp {
                        VStack {
                            HStack {
                                Spacer()
                                Button(action: {
                                    if authMode == .phoneSignIn || authMode == .phoneSignUp {
                                        authMode = authMode == .phoneSignUp ? .signUp : .signIn
                                        phoneNumber = ""
                                        authService.cancelPhoneAuth()
                                    } else {
                                        authMode = authMode == .phoneVerificationSignUp ? .phoneSignUp : .phoneSignIn
                                        verificationCode = ""
                                        authService.cancelPhoneAuth()
                                    }
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.title2)
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 10)
                            Spacer()
                        }
                    }
                }
            )
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
        .onReceive(authService.$isWaitingForSMS) { isWaiting in
            if isWaiting {
                if authMode == .phoneSignIn {
                    authMode = .phoneVerification
                } else if authMode == .phoneSignUp {
                    authMode = .phoneVerificationSignUp
                }
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
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") {
                            hideKeyboard()
                        }
                        .foregroundColor(.accentColor)
                    }
                }
            
            SecureField("Password", text: $password)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .textContentType(authMode == .signUp ? .newPassword : .password)
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") {
                            hideKeyboard()
                        }
                        .foregroundColor(.accentColor)
                    }
                }
            
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
    
    private var phoneNumberForm: some View {
        VStack(spacing: 16) {
            Text(authMode == .phoneSignUp ? "Sign up with Phone" : "Sign in with Phone")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text(authMode == .phoneSignUp ? 
                 "Enter your phone number to create a new account" :
                 "Enter your phone number to receive a verification code")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            VStack(spacing: 12) {
                HStack {
                    Button(action: { showingCountryPicker = true }) {
                        HStack {
                            Text(selectedCountry.flag)
                            Text(selectedCountry.code)
                                .font(.subheadline)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                    }
                    .sheet(isPresented: $showingCountryPicker) {
                        CountryCodePicker(selectedCountry: $selectedCountry)
                    }
                    
                    TextField("Phone Number", text: $phoneNumber)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .textContentType(.telephoneNumber)
                        .keyboardType(.phonePad)
                        .placeholder(when: phoneNumber.isEmpty) {
                            Text(selectedCountry.placeholder)
                                .foregroundColor(.secondary)
                        }
                        .onChange(of: phoneNumber) { newValue in
                            // Remove any non-numeric characters except spaces and dashes for display
                            let filtered = newValue.filter { $0.isNumber || $0 == " " || $0 == "-" || $0 == "(" || $0 == ")" }
                            if filtered != newValue {
                                phoneNumber = filtered
                            }
                        }
                        .toolbar {
                            ToolbarItemGroup(placement: .keyboard) {
                                Spacer()
                                Button("Done") {
                                    hideKeyboard()
                                }
                                .foregroundColor(.accentColor)
                            }
                        }
                }
                
                // Show warning for sign-up if phone number might be taken
                if authMode == .phoneSignUp && !phoneNumber.isEmpty {
                    HStack {
                        Image(systemName: "info.circle")
                            .foregroundColor(.orange)
                            .font(.caption)
                        Text("We'll check if this number is available before sending the code")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundColor(.blue)
                        .font(.caption)
                    Text("Enter your phone number without the country code")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Button(action: {
                Task {
                    await handlePhoneVerification()
                }
            }) {
                HStack {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                    }
                    Text("Send Verification Code")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.accentColor)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .disabled(isLoading || phoneNumber.isEmpty)
            
            VStack(spacing: 8) {
                Text("Legal Notice")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                
                Text("By using phone sign-in, you may receive an SMS message for verification. Standard rates apply.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 8)
        }
    }
    
    private var verificationCodeForm: some View {
        VStack(spacing: 16) {
            Text("Enter Verification Code")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("We sent a 6-digit code to \(authService.phoneNumber)")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            TextField("Verification Code", text: $verificationCode)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .textContentType(.oneTimeCode)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(.title3)
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") {
                            hideKeyboard()
                        }
                        .foregroundColor(.accentColor)
                    }
                }
            
            Button(action: {
                Task {
                    await handlePhoneAuthentication()
                }
            }) {
                HStack {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                    }
                    Text(authMode == .phoneVerificationSignUp ? "Verify & Create Account" : "Verify & Sign In")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.accentColor)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .disabled(isLoading || verificationCode.isEmpty)
            
            HStack(spacing: 20) {
                Button("Resend Code") {
                    Task {
                        await handleResendCode()
                    }
                }
                .font(.subheadline)
                .foregroundColor(.accentColor)
                .disabled(isLoading)
                
                Button("Change Number") {
                    authService.cancelPhoneAuth()
                    authMode = authMode == .phoneVerificationSignUp ? .phoneSignUp : .phoneSignIn
                    phoneNumber = ""
                    verificationCode = ""
                }
                .font(.subheadline)
                .foregroundColor(.secondary)
            }
        }
    }
    
    private var alternativeSignInOptions: some View {
        VStack(spacing: 12) {
            HStack {
                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(.secondary.opacity(0.3))
                Text("or")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(.secondary.opacity(0.3))
            }
            
            Button(action: {
                let targetMode: AuthMode = authMode == .signUp ? .phoneSignUp : .phoneSignIn
                authMode = targetMode
                phoneNumber = authService.phoneNumber
            }) {
                HStack {
                    Image(systemName: "phone.fill")
                        .foregroundColor(.accentColor)
                    Text(authMode == .signUp ? "Sign up with Phone" : "Sign in with Phone")
                        .fontWeight(.medium)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(.systemGray6))
                .foregroundColor(.primary)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
                )
            }
            
            Text("📱 Receive SMS verification code")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24)
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
            case .phoneSignIn:
                Text("Don't have an account?")
                    .foregroundColor(.secondary)
                Button("Sign Up with Phone") {
                    authMode = .phoneSignUp
                    phoneNumber = ""
                    verificationCode = ""
                }
                .foregroundColor(.accentColor)
            case .phoneSignUp:
                Text("Already have an account?")
                    .foregroundColor(.secondary)
                Button("Sign In with Phone") {
                    authMode = .phoneSignIn
                    phoneNumber = ""
                    verificationCode = ""
                }
                .foregroundColor(.accentColor)
            case .phoneVerification, .phoneVerificationSignUp:
                VStack(spacing: 8) {
                    HStack {
                        Text("Prefer email?")
                            .foregroundColor(.secondary)
                        Button("Use Email Instead") {
                            authMode = .signIn
                            authService.cancelPhoneAuth()
                            phoneNumber = ""
                            verificationCode = ""
                        }
                        .foregroundColor(.accentColor)
                    }
                    
                    HStack {
                        Text("Need help?")
                            .foregroundColor(.secondary)
                        Button("Contact Support") {
                            // You can add support contact action here
                        }
                        .foregroundColor(.accentColor)
                    }
                }
            }
        }
        .font(.subheadline)
        .padding(.bottom, 40)
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
    
    private func handlePhoneVerification() async {
        isLoading = true
        authService.errorMessage = nil
        do {
            // Clean and format phone number properly
            let cleanPhoneNumber = phoneNumber.filter { $0.isNumber }
            let fullPhoneNumber = selectedCountry.code + cleanPhoneNumber
            
            print("🔵 PHONE AUTH DEBUG: Country code: \(selectedCountry.code)")
            print("🔵 PHONE AUTH DEBUG: Clean phone: \(cleanPhoneNumber)")
            print("🔵 PHONE AUTH DEBUG: Full number: \(fullPhoneNumber)")
            
            // Check if this is a sign-up attempt and if the phone number is already taken
            if authMode == .phoneSignUp {
                let isAvailable = await authService.isPhoneNumberAvailable(fullPhoneNumber)
                if !isAvailable {
                    authService.errorMessage = "An account already exists with this phone number. Please sign in instead."
                    showError = true
                    isLoading = false
                    return
                }
            }
            
            try await authService.verifyPhoneNumber(fullPhoneNumber)
        } catch {
            print("❌ PHONE AUTH ERROR in AuthView: \(error.localizedDescription)")
            authService.errorMessage = error.localizedDescription
            showError = true
        }
        isLoading = false
    }
    
    private func handlePhoneAuthentication() async {
        isLoading = true
        authService.errorMessage = nil
        do {
            if authMode == .phoneVerificationSignUp {
                try await authService.signUpWithPhoneNumber(verificationCode: verificationCode)
            } else {
                try await authService.signInWithPhoneNumber(verificationCode: verificationCode)
            }
        } catch {
            print("❌ PHONE AUTH ERROR in AuthView: \(error.localizedDescription)")
            authService.errorMessage = error.localizedDescription
            showError = true
        }
        isLoading = false
    }
    
    private func handleResendCode() async {
        isLoading = true
        authService.errorMessage = nil
        do {
            try await authService.resendVerificationCode()
        } catch {
            print("❌ PHONE AUTH ERROR in AuthView: \(error.localizedDescription)")
            authService.errorMessage = error.localizedDescription
            showError = true
        }
        isLoading = false
    }
}

// MARK: - View Extensions
extension View {
    func placeholder<Content: View>(
        when shouldShow: Bool,
        alignment: Alignment = .leading,
        @ViewBuilder placeholder: () -> Content) -> some View {

        ZStack(alignment: alignment) {
            placeholder().opacity(shouldShow ? 1 : 0)
            self
        }
    }
}

// MARK: - Keyboard Dismissal
extension View {
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
} 