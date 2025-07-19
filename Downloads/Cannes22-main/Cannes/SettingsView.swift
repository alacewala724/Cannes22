import SwiftUI
import FirebaseAuth
import FirebaseCore
import UIKit

// MARK: - Settings View
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authService: AuthenticationService
    
    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var newUsername = ""
    @State private var phoneNumber = ""
    @State private var verificationCode = ""
    @State private var selectedCountry = CountryCode.popular[0] // Default to US
    
    @State private var isChangingPassword = false
    @State private var isChangingUsername = false
    @State private var isCheckingUsername = false
    @State private var isLinkingPhone = false
    @State private var isUnlinkingPhone = false
    @State private var showingPhoneVerification = false
    @State private var showingCountryPicker = false
    
    @State private var passwordErrorMessage: String?
    @State private var usernameErrorMessage: String?
    @State private var phoneErrorMessage: String?
    @State private var passwordSuccessMessage: String?
    @State private var usernameSuccessMessage: String?
    @State private var phoneSuccessMessage: String?
    
    @State private var showingSignOutAlert = false
    @State private var showingUnlinkPhoneAlert = false
    
    var body: some View {
        NavigationView {
            List {
                // Account Section
                Section("Account") {
                    VStack(alignment: .leading, spacing: 8) {
                        if let email = authService.currentUser?.email {
                            HStack {
                                Text("Email")
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(email)
                            }
                        }
                        
                        if let phoneNumber = authService.getUserPhoneNumber() {
                            HStack {
                                Text("Phone")
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(phoneNumber)
                            }
                        }
                        
                        HStack {
                            Text("Username")
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("@\(authService.username ?? "Unknown")")
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                // Phone Number Management Section
                Section("Phone Number") {
                    if authService.hasPhoneNumberLinked() {
                        VStack(spacing: 12) {
                            HStack {
                                Text("Linked Phone Number")
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(authService.getUserPhoneNumber() ?? "")
                                    .foregroundColor(.primary)
                            }
                            
                            if let successMessage = phoneSuccessMessage {
                                Text(successMessage)
                                    .foregroundColor(.green)
                                    .font(.caption)
                            }
                            
                            Button(action: { showingUnlinkPhoneAlert = true }) {
                                HStack {
                                    if isUnlinkingPhone {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                    }
                                    Text("Unlink Phone Number")
                                }
                                .foregroundColor(.red)
                            }
                            .buttonStyle(.bordered)
                            .disabled(isUnlinkingPhone)
                        }
                        .padding(.vertical, 8)
                    } else {
                        VStack(spacing: 12) {
                            Text("No phone number linked to your account")
                                .foregroundColor(.secondary)
                                .font(.subheadline)
                            
                            if !showingPhoneVerification {
                                // Country code selector and phone input
                                HStack {
                                    Button(action: { showingCountryPicker = true }) {
                                        HStack(spacing: 8) {
                                            Text(selectedCountry.flag)
                                                .font(.title2)
                                            Text(selectedCountry.code)
                                                .font(.headline)
                                                .foregroundColor(.primary)
                                            Image(systemName: "chevron.down")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(Color(.systemGray6))
                                        .cornerRadius(8)
                                    }
                                    .buttonStyle(.plain)
                                    
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
                                }
                                
                                if let errorMessage = phoneErrorMessage {
                                    Text(errorMessage)
                                        .foregroundColor(.red)
                                        .font(.caption)
                                }
                                
                                Button(action: linkPhoneNumber) {
                                    HStack {
                                        if isLinkingPhone {
                                            ProgressView()
                                                .scaleEffect(0.8)
                                        }
                                        Text("Link Phone Number")
                                    }
                                }
                                .buttonStyle(.bordered)
                                .disabled(isLinkingPhone || phoneNumber.count < 5)
                            } else {
                                Text("Enter the verification code sent to \(phoneNumber)")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                
                                TextField("Verification Code", text: $verificationCode)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .textContentType(.oneTimeCode)
                                    .keyboardType(.numberPad)
                                    .multilineTextAlignment(.center)
                                
                                if let errorMessage = phoneErrorMessage {
                                    Text(errorMessage)
                                        .foregroundColor(.red)
                                        .font(.caption)
                                }
                                
                                if let successMessage = phoneSuccessMessage {
                                    Text(successMessage)
                                        .foregroundColor(.green)
                                        .font(.caption)
                                }
                                
                                HStack(spacing: 12) {
                                    Button(action: verifyPhoneLink) {
                                        HStack {
                                            if isLinkingPhone {
                                                ProgressView()
                                                    .scaleEffect(0.8)
                                            }
                                            Text("Verify")
                                        }
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(isLinkingPhone || verificationCode.isEmpty)
                                    
                                    Button("Cancel") {
                                        showingPhoneVerification = false
                                        phoneNumber = ""
                                        verificationCode = ""
                                        phoneErrorMessage = nil
                                        authService.cancelPhoneAuth()
                                    }
                                    .buttonStyle(.bordered)
                                }
                                
                                Button("Resend Code") {
                                    Task {
                                        await resendVerificationCode()
                                    }
                                }
                                .font(.caption)
                                .foregroundColor(.accentColor)
                                .disabled(isLinkingPhone)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
                
                // Change Password Section (only for email users)
                if authService.currentUser?.email != nil {
                    Section("Change Password") {
                        VStack(spacing: 12) {
                            SecureField("Current Password", text: $currentPassword)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                            
                            SecureField("New Password", text: $newPassword)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                            
                            SecureField("Confirm New Password", text: $confirmPassword)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                            
                            if let errorMessage = passwordErrorMessage {
                                Text(errorMessage)
                                    .foregroundColor(.red)
                                    .font(.caption)
                            }
                            
                            if let successMessage = passwordSuccessMessage {
                                Text(successMessage)
                                    .foregroundColor(.green)
                                    .font(.caption)
                            }
                            
                            Button(action: changePassword) {
                                HStack {
                                    if isChangingPassword {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                    }
                                    Text("Change Password")
                                }
                            }
                            .buttonStyle(.bordered)
                            .disabled(isChangingPassword || currentPassword.isEmpty || newPassword.isEmpty || confirmPassword.isEmpty)
                        }
                        .padding(.vertical, 8)
                    }
                }
                
                // Change Username Section
                Section("Change Username") {
                    VStack(spacing: 12) {
                        TextField("New Username", text: $newUsername)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                        
                        if let errorMessage = usernameErrorMessage {
                            Text(errorMessage)
                                .foregroundColor(.red)
                                .font(.caption)
                        }
                        
                        if let successMessage = usernameSuccessMessage {
                            Text(successMessage)
                                .foregroundColor(.green)
                                .font(.caption)
                        }
                        
                        Button(action: changeUsername) {
                            HStack {
                                if isChangingUsername || isCheckingUsername {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                }
                                Text("Change Username")
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(isChangingUsername || isCheckingUsername || newUsername.isEmpty || newUsername == authService.username)
                    }
                    .padding(.vertical, 8)
                }
                
                // Sign Out Section
                Section {
                    Button(action: { showingSignOutAlert = true }) {
                        HStack {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                            Text("Sign Out")
                        }
                        .foregroundColor(.red)
                    }
                }
                
                // Debug Section (only in debug builds)
                #if DEBUG
                Section("Debug Info") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Firebase Project: \(FirebaseApp.app()?.options.projectID ?? "Unknown")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("Bundle ID: \(Bundle.main.bundleIdentifier ?? "Unknown")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("Device: \(UIDevice.current.model)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        #if targetEnvironment(simulator)
                        Text("⚠️ Running on Simulator - Phone auth may not work")
                            .font(.caption)
                            .foregroundColor(.orange)
                        #else
                        Text("✅ Running on Real Device")
                            .font(.caption)
                            .foregroundColor(.green)
                        #endif
                        
                        Text("App Verification Disabled: \(Auth.auth().settings?.isAppVerificationDisabledForTesting ?? false ? "Yes" : "No")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                #endif
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Sign Out", isPresented: $showingSignOutAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Sign Out", role: .destructive) {
                    try? authService.signOut()
                    dismiss()
                }
            } message: {
                Text("Are you sure you want to sign out?")
            }
            .alert("Unlink Phone Number", isPresented: $showingUnlinkPhoneAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Unlink", role: .destructive) {
                    Task {
                        await unlinkPhoneNumber()
                    }
                }
            } message: {
                Text("Are you sure you want to unlink your phone number? You can always link it again later.")
            }
            .sheet(isPresented: $showingCountryPicker) {
                CountryCodePicker(selectedCountry: $selectedCountry)
            }
        }
    }
    
    private func changePassword() {
        // Clear previous messages
        passwordErrorMessage = nil
        passwordSuccessMessage = nil
        
        // Validate passwords match
        guard newPassword == confirmPassword else {
            passwordErrorMessage = "New passwords don't match"
            return
        }
        
        // Validate password strength
        guard newPassword.count >= 6 else {
            passwordErrorMessage = "Password must be at least 6 characters"
            return
        }
        
        isChangingPassword = true
        
        Task {
            do {
                try await authService.changePassword(currentPassword: currentPassword, newPassword: newPassword)
                
                await MainActor.run {
                    isChangingPassword = false
                    passwordSuccessMessage = "Password changed successfully"
                    
                    // Clear form
                    currentPassword = ""
                    newPassword = ""
                    confirmPassword = ""
                    
                    // Clear success message after 3 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        passwordSuccessMessage = nil
                    }
                }
            } catch {
                await MainActor.run {
                    isChangingPassword = false
                    passwordErrorMessage = error.localizedDescription
                }
            }
        }
    }
    
    private func changeUsername() {
        // Clear previous messages
        usernameErrorMessage = nil
        usernameSuccessMessage = nil
        
        // Validate username format
        let trimmedUsername = newUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUsername.isEmpty else {
            usernameErrorMessage = "Username cannot be empty"
            return
        }
        
        guard trimmedUsername.count >= 3 else {
            usernameErrorMessage = "Username must be at least 3 characters"
            return
        }
        
        guard trimmedUsername.count <= 20 else {
            usernameErrorMessage = "Username cannot be longer than 20 characters"
            return
        }
        
        // Check for valid characters (alphanumeric and underscore only)
        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
        guard trimmedUsername.rangeOfCharacter(from: allowedCharacters.inverted) == nil else {
            usernameErrorMessage = "Username can only contain letters, numbers, and underscores"
            return
        }
        
        isCheckingUsername = true
        
        Task {
            do {
                // First check if username is available
                let isAvailable = try await authService.isUsernameAvailable(trimmedUsername)
                
                guard isAvailable else {
                    await MainActor.run {
                        isCheckingUsername = false
                        usernameErrorMessage = "Username is already taken"
                    }
                    return
                }
                
                // Username is available, proceed with change
                await MainActor.run {
                    isCheckingUsername = false
                    isChangingUsername = true
                }
                
                try await authService.changeUsername(to: trimmedUsername)
                
                await MainActor.run {
                    isChangingUsername = false
                    usernameSuccessMessage = "Username changed successfully"
                    
                    // Clear form
                    newUsername = ""
                    
                    // Clear success message after 3 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        usernameSuccessMessage = nil
                    }
                }
            } catch {
                await MainActor.run {
                    isCheckingUsername = false
                    isChangingUsername = false
                    usernameErrorMessage = error.localizedDescription
                }
            }
        }
    }
    
    // MARK: - Phone Number Management
    
    private func linkPhoneNumber() {
        phoneErrorMessage = nil
        phoneSuccessMessage = nil
        isLinkingPhone = true
        
        Task {
            do {
                // Combine country code with phone number
                let fullPhoneNumber = selectedCountry.code + phoneNumber.filter { $0.isNumber }
                try await authService.verifyPhoneNumber(fullPhoneNumber)
                await MainActor.run {
                    showingPhoneVerification = true
                    isLinkingPhone = false
                }
            } catch {
                await MainActor.run {
                    isLinkingPhone = false
                    phoneErrorMessage = error.localizedDescription
                }
            }
        }
    }
    
    private func verifyPhoneLink() {
        phoneErrorMessage = nil
        phoneSuccessMessage = nil
        isLinkingPhone = true
        
        Task {
            do {
                try await authService.linkPhoneNumber(verificationCode: verificationCode)
                await MainActor.run {
                    isLinkingPhone = false
                    showingPhoneVerification = false
                    phoneSuccessMessage = "Phone number linked successfully"
                    phoneNumber = ""
                    verificationCode = ""
                    
                    // Clear success message after 3 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        phoneSuccessMessage = nil
                    }
                }
            } catch {
                await MainActor.run {
                    isLinkingPhone = false
                    phoneErrorMessage = error.localizedDescription
                }
            }
        }
    }
    
    private func unlinkPhoneNumber() {
        isUnlinkingPhone = true
        
        Task {
            do {
                try await authService.unlinkPhoneNumber()
                await MainActor.run {
                    isUnlinkingPhone = false
                    phoneSuccessMessage = "Phone number unlinked successfully"
                    
                    // Clear success message after 3 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        phoneSuccessMessage = nil
                    }
                }
            } catch {
                await MainActor.run {
                    isUnlinkingPhone = false
                    phoneErrorMessage = error.localizedDescription
                }
            }
        }
    }
    
    private func resendVerificationCode() async {
        do {
            try await authService.resendVerificationCode()
        } catch {
            await MainActor.run {
                phoneErrorMessage = error.localizedDescription
            }
        }
    }
} 