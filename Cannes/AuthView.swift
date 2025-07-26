import SwiftUI
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import UserNotifications

enum AuthMode {
    case signIn
    case signUp
    case phoneAuth
    case phoneVerification
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
    
    // Validation states
    @State private var emailValidationError: String?
    @State private var passwordValidationError: String?
    @State private var passwordStrength: Int = 0
    @State private var passwordStrengthDescription: String = ""
    @State private var passwordStrengthColor: String = "gray"
    @State private var showPasswordStrength = false
    
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
                    case .phoneAuth:
                        phoneNumberForm
                    case .phoneVerification:
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
                    if authMode == .phoneAuth || authMode == .phoneVerification {
                        VStack {
                            HStack {
                                Spacer()
                                Button(action: {
                                    authMode = .signIn
                                    phoneNumber = ""
                                    authService.cancelPhoneAuth()
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
        .onChange(of: authService.errorMessage) { _, message in
            if message != nil {
                showError = true
            }
        }
        .onReceive(authService.$isWaitingForSMS) { isWaiting in
            if isWaiting {
                authMode = .phoneVerification
            }
        }
        // Real-time validation
        .onChange(of: email) { _, newEmail in
            validateEmail(newEmail)
        }
        .onChange(of: password) { _, newPassword in
            validatePassword(newPassword)
        }
    }
    
    private var emailAuthForm: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
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
                
                if let error = emailValidationError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .transition(.opacity)
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                SecureField("Password", text: $password)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .textContentType(authMode == .signUp ? .newPassword : .password)
                    .onTapGesture {
                        if authMode == .signUp {
                            showPasswordStrength = true
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
                
                if authMode == .signUp && showPasswordStrength {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Password Strength:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(passwordStrengthDescription)
                                .font(.caption)
                                .foregroundColor(Color(passwordStrengthColor))
                                .fontWeight(.medium)
                        }
                        
                        // Password strength bar
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                Rectangle()
                                    .fill(Color.gray.opacity(0.3))
                                    .frame(height: 4)
                                    .cornerRadius(2)
                                
                                Rectangle()
                                    .fill(Color(passwordStrengthColor))
                                    .frame(width: geometry.size.width * CGFloat(passwordStrength) / 4, height: 4)
                                    .cornerRadius(2)
                            }
                        }
                        .frame(height: 4)
                        
                        // Password requirements
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Requirements:")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            
                            RequirementRow(text: "At least 8 characters", isMet: password.count >= 8)
                            RequirementRow(text: "One lowercase letter", isMet: password.range(of: "[a-z]", options: .regularExpression) != nil)
                            RequirementRow(text: "One uppercase letter", isMet: password.range(of: "[A-Z]", options: .regularExpression) != nil)
                            RequirementRow(text: "One number", isMet: password.range(of: "\\d", options: .regularExpression) != nil)
                            RequirementRow(text: "One special character (@$!%*?&)", isMet: password.range(of: "[@$!%*?&]", options: .regularExpression) != nil)
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                }
                
                if let error = passwordValidationError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .transition(.opacity)
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
                .background(isFormValid ? Color.accentColor : Color.gray)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .disabled(isLoading || !isFormValid)
            
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
            Text("Continue with Phone Number")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Enter your phone number to receive a verification code. We'll sign you in or create a new account.")
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
                        .onChange(of: phoneNumber) { _, newValue in
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
                    Text("Continue")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.accentColor)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .disabled(isLoading || phoneNumber.isEmpty)
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
                    Text("Continue")
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
                    authMode = .phoneAuth
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
                authMode = .phoneAuth
                phoneNumber = authService.phoneNumber
            }) {
                HStack {
                    Image(systemName: "phone.fill")
                    Text("Continue with Phone Number")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(.systemGray6))
                .foregroundColor(.primary)
                .cornerRadius(12)
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
            case .phoneAuth:
                Text("Prefer email authentication?")
                    .foregroundColor(.secondary)
                Button("Use Email Instead") {
                    authMode = .signIn
                    phoneNumber = ""
                    verificationCode = ""
                }
                .foregroundColor(.accentColor)
            case .phoneVerification:
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
            try await authService.signInWithPhoneNumber(verificationCode: verificationCode)
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
    
    // MARK: - Validation
    private var isFormValid: Bool {
        let isEmailValid = emailValidationError == nil && !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let isPasswordValid = passwordValidationError == nil && !password.isEmpty
        
        if authMode == .signUp {
            return isEmailValid && isPasswordValid && InputValidator.isValidPassword(password)
        } else {
            return isEmailValid && isPasswordValid
        }
    }
    
    private func validateEmail(_ email: String) {
        emailValidationError = InputValidator.getEmailValidationError(email)
    }
    
    private func validatePassword(_ password: String) {
        if authMode == .signUp {
            passwordValidationError = InputValidator.getPasswordValidationError(password)
            passwordStrength = InputValidator.getPasswordStrength(password)
            passwordStrengthDescription = InputValidator.getPasswordStrengthDescription(password)
            passwordStrengthColor = InputValidator.getPasswordStrengthColor(password)
        } else {
            passwordValidationError = nil
        }
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

// MARK: - Requirement Row Component
struct RequirementRow: View {
    let text: String
    let isMet: Bool
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: isMet ? "checkmark.circle.fill" : "circle")
                .font(.caption2)
                .foregroundColor(isMet ? .green : .gray)
            
            Text(text)
                .font(.caption2)
                .foregroundColor(isMet ? .primary : .secondary)
        }
    }
} 