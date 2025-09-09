import SwiftUI
import FirebaseAuth
import FirebaseCore
import UIKit

// MARK: - Settings View
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authService: AuthenticationService
    @EnvironmentObject var notificationService: NotificationService
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var firestoreService = FirestoreService()
    
    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var newUsername = ""
    
    @State private var isChangingPassword = false
    @State private var isChangingUsername = false
    @State private var isCheckingUsername = false
    @State private var isLinkingEmail = false
    @State private var isUnlinkingEmail = false
    @State private var isLinkingPhone = false
    @State private var isUnlinkingPhone = false
    
    @State private var passwordErrorMessage: String?
    @State private var usernameErrorMessage: String?
    @State private var passwordSuccessMessage: String?
    @State private var usernameSuccessMessage: String?
    @State private var emailLinkErrorMessage: String?
    @State private var emailLinkSuccessMessage: String?
    @State private var phoneLinkErrorMessage: String?
    @State private var phoneLinkSuccessMessage: String?
    
    @State private var showingSignOutAlert = false
    @State private var showingUnlinkEmailAlert = false
    @State private var showingUnlinkPhoneAlert = false
    @State private var showingDeleteAccountAlert = false
    @State private var showingDeleteAccountConfirmation = false
    @State private var isDeletingAccount = false
    @State private var deleteAccountErrorMessage: String?
    
    // Email linking states
    @State private var emailToLink = ""
    @State private var emailPassword = ""
    
    // Phone linking states
    @State private var phoneNumberToLink = ""
    @State private var phoneVerificationCode = ""
    @State private var selectedCountry = CountryCode.popular[0]
    @State private var showingCountryPicker = false
    @State private var isWaitingForPhoneSMS = false
    
    @State private var isUpdatingMyPoster = false
    @State private var posterUpdateMessage: String?
    @State private var showingAttribution = false
    
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
                        
                        if let phoneNumber = authService.currentUser?.phoneNumber {
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
                
                // Email Linking Section (only for phone users)
                if authService.isPhoneUser {
                    Section("Email Linking") {
                        if authService.canLinkEmail {
                            // User can link an email
                            VStack(spacing: 12) {
                                Text("Link Email Address")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                
                                Text("Add an email address to your account for easier sign-in and account recovery.")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.leading)
                                
                                TextField("Email Address", text: $emailToLink)
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
                                
                                SecureField("Password for Email", text: $emailPassword)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .textContentType(.password)
                                    .toolbar {
                                        ToolbarItemGroup(placement: .keyboard) {
                                            Spacer()
                                            Button("Done") {
                                                hideKeyboard()
                                            }
                                            .foregroundColor(.accentColor)
                                        }
                                    }
                                
                                if let errorMessage = emailLinkErrorMessage {
                                    Text(errorMessage)
                                        .foregroundColor(.red)
                                        .font(.caption)
                                }
                                
                                if let successMessage = emailLinkSuccessMessage {
                                    Text(successMessage)
                                        .foregroundColor(Color.adaptiveSentiment(for: 8.0, colorScheme: colorScheme))
                                        .font(.caption)
                                }
                                
                                Button(action: linkEmail) {
                                    HStack {
                                        if isLinkingEmail {
                                            ProgressView()
                                                .scaleEffect(0.8)
                                        }
                                        Text("Link Email")
                                    }
                                }
                                .buttonStyle(.bordered)
                                .disabled(isLinkingEmail || emailToLink.isEmpty || emailPassword.isEmpty)
                            }
                            .padding(.vertical, 8)
                        } else if authService.canUnlinkEmail {
                            // User can unlink their email
                            VStack(spacing: 12) {
                                Text("Linked Email Address")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                
                                Text("Your email address is linked to your account. You can unlink it if needed.")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.leading)
                                
                                if let errorMessage = emailLinkErrorMessage {
                                    Text(errorMessage)
                                        .foregroundColor(.red)
                                        .font(.caption)
                                }
                                
                                if let successMessage = emailLinkSuccessMessage {
                                    Text(successMessage)
                                        .foregroundColor(Color.adaptiveSentiment(for: 8.0, colorScheme: colorScheme))
                                        .font(.caption)
                                }
                                
                                Button(action: { showingUnlinkEmailAlert = true }) {
                                    HStack {
                                        if isUnlinkingEmail {
                                            ProgressView()
                                                .scaleEffect(0.8)
                                        }
                                        Text("Unlink Email")
                                    }
                                    .foregroundColor(.red)
                                }
                                .buttonStyle(.bordered)
                                .disabled(isUnlinkingEmail)
                            }
                            .padding(.vertical, 8)
                        }
                    }
                }
                
                // Phone Linking Section (only for email users)
                if authService.isEmailUser {
                    Section("Phone Linking") {
                        if authService.canLinkPhone {
                            // User can link a phone number
                            VStack(spacing: 12) {
                                Text("Link Phone Number")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                
                                Text("Add a phone number to your account for easier sign-in and account recovery.")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.leading)
                                
                                if !isWaitingForPhoneSMS {
                                    // Phone number input
                                    VStack(spacing: 8) {
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
                                            
                                            TextField("Phone Number", text: $phoneNumberToLink)
                                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                                .textContentType(.telephoneNumber)
                                                .keyboardType(.phonePad)
                                                .placeholder(when: phoneNumberToLink.isEmpty) {
                                                    Text(selectedCountry.placeholder)
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
                                    
                                    if let errorMessage = phoneLinkErrorMessage {
                                        Text(errorMessage)
                                            .foregroundColor(.red)
                                            .font(.caption)
                                    }
                                    
                                    Button(action: sendPhoneVerification) {
                                        HStack {
                                            if isLinkingPhone {
                                                ProgressView()
                                                    .scaleEffect(0.8)
                                            }
                                            Text("Send Verification Code")
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(isLinkingPhone || phoneNumberToLink.isEmpty)
                                } else {
                                    // Verification code input
                                    VStack(spacing: 8) {
                                        Text("We sent a 6-digit code to \(selectedCountry.code + phoneNumberToLink)")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                            .multilineTextAlignment(.center)
                                        
                                        TextField("Verification Code", text: $phoneVerificationCode)
                                            .textFieldStyle(RoundedBorderTextFieldStyle())
                                            .textContentType(.oneTimeCode)
                                            .keyboardType(.numberPad)
                                            .multilineTextAlignment(.center)
                                            .font(.title3)
                                        
                                        if let errorMessage = phoneLinkErrorMessage {
                                            Text(errorMessage)
                                                .foregroundColor(.red)
                                                .font(.caption)
                                        }
                                        
                                        if let successMessage = phoneLinkSuccessMessage {
                                            Text(successMessage)
                                                .foregroundColor(Color.adaptiveSentiment(for: 8.0, colorScheme: colorScheme))
                                                .font(.caption)
                                        }
                                        
                                        HStack(spacing: 20) {
                                            Button("Resend Code") {
                                                sendPhoneVerification()
                                            }
                                            .font(.subheadline)
                                            .foregroundColor(.accentColor)
                                            .disabled(isLinkingPhone)
                                            
                                            Button("Change Number") {
                                                isWaitingForPhoneSMS = false
                                                phoneNumberToLink = ""
                                                phoneVerificationCode = ""
                                                phoneLinkErrorMessage = nil
                                                phoneLinkSuccessMessage = nil
                                            }
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                        }
                                        
                                        Button(action: verifyPhoneCode) {
                                            HStack {
                                                if isLinkingPhone {
                                                    ProgressView()
                                                        .scaleEffect(0.8)
                                                }
                                                Text("Link Phone Number")
                                            }
                                        }
                                        .buttonStyle(.bordered)
                                        .disabled(isLinkingPhone || phoneVerificationCode.isEmpty)
                                    }
                                }
                            }
                            .padding(.vertical, 8)
                        } else if authService.canUnlinkPhone {
                            // User can unlink their phone number
                            VStack(spacing: 12) {
                                Text("Linked Phone Number")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                
                                Text("Your phone number is linked to your account. You can unlink it if needed.")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.leading)
                                
                                if let phoneNumber = authService.getUserPhoneNumber() {
                                    HStack {
                                        Text("Phone")
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        Text(phoneNumber)
                                    }
                                }
                                
                                if let errorMessage = phoneLinkErrorMessage {
                                    Text(errorMessage)
                                        .foregroundColor(.red)
                                        .font(.caption)
                                }
                                
                                if let successMessage = phoneLinkSuccessMessage {
                                    Text(successMessage)
                                        .foregroundColor(Color.adaptiveSentiment(for: 8.0, colorScheme: colorScheme))
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
                        }
                    }
                }
                
                // Password Change Section (only for email users with passwords)
                if authService.isEmailUser && authService.currentUser?.email != nil {
                    Section("Security") {
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
                                    .foregroundColor(Color.adaptiveSentiment(for: 8.0, colorScheme: colorScheme))
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
                
                // Username Change Section
                Section("Profile") {
                    VStack(spacing: 12) {
                        TextField("New Username", text: $newUsername)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .autocapitalization(.none)
                            .onChange(of: newUsername) { _, _ in
                                checkUsernameAvailability()
                            }
                        
                        if let errorMessage = usernameErrorMessage {
                            Text(errorMessage)
                                .foregroundColor(.red)
                                .font(.caption)
                        }
                        
                        if let successMessage = usernameSuccessMessage {
                            Text(successMessage)
                                .foregroundColor(Color.adaptiveSentiment(for: 8.0, colorScheme: colorScheme))
                                .font(.caption)
                        }
                        
                        Button(action: changeUsername) {
                            HStack {
                                if isChangingUsername {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                }
                                Text("Change Username")
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(isChangingUsername || newUsername.isEmpty || isCheckingUsername)
                        
                        Divider()
                        
                        // Update current user's movie poster
                        VStack(spacing: 8) {
                            Text("Update My Movie Poster")
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            Text("Refresh your profile's movie poster based on your current top movie")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.leading)
                            
                            Button(action: updateMyMoviePoster) {
                                HStack {
                                    if isUpdatingMyPoster {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                    }
                                    Text("Update Poster")
                                }
                            }
                            .buttonStyle(.bordered)
                            .disabled(isUpdatingMyPoster)
                            
                            if let posterUpdateMessage = posterUpdateMessage {
                                Text(posterUpdateMessage)
                                    .font(.caption)
                                    .foregroundColor(posterUpdateMessage.contains("Error") ? .red : .green)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
                
                // Notification Settings Section
                Section("Notifications") {
                    VStack(spacing: 12) {
                        Text("Push Notifications")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        Text("Get notified when someone you follow rates a movie you've also rated")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.leading)
                        
                        HStack {
                            Text("Permission Status")
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(notificationService.notificationPermissionGranted ? "Granted" : "Not Granted")
                                .foregroundColor(notificationService.notificationPermissionGranted ? .green : .red)
                        }
                    }
                    .padding(.vertical, 8)
                }
                
                // Privacy Policy Section
                Section("Legal") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Privacy Policy")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        Text("Cannes respects your privacy. We collect only the data necessary to provide our movie ranking service:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("• Your email address for account creation")
                            Text("• Your username for social features")
                            Text("• Your movie ratings and preferences")
                            Text("• Basic usage analytics to improve the app")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                        
                        Text("We do not sell your data to third parties. Your ratings are shared with the community to enable the ranking system, but your personal information remains private.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                    }
                    .padding(.vertical, 4)
                    
                    // Attribution Section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Third-Party Services")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        Text("This app uses data and services from third-party providers. We comply with all attribution requirements and terms of service.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Button(action: { showingAttribution = true }) {
                            HStack {
                                Image(systemName: "info.circle")
                                    .foregroundColor(.accentColor)
                                Text("View Attributions")
                                    .foregroundColor(.accentColor)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 4)
                }
                
                // Account Deletion Section
                Section("Advanced Settings") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Delete Account")
                            .font(.headline)
                            .foregroundColor(.red)
                        
                        Text("Permanently delete your account and all associated data. This action cannot be undone.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.leading)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("This will delete:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("• All your movie ratings and rankings")
                            Text("• Your comments and takes")
                            Text("• Your following/followers relationships")
                            Text("• Your profile and personal data")
                            Text("• Your wishlist and preferences")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                        
                        if let errorMessage = deleteAccountErrorMessage {
                            Text(errorMessage)
                                .foregroundColor(.red)
                                .font(.caption)
                        }
                        
                        Button(action: { showingDeleteAccountAlert = true }) {
                            HStack {
                                if isDeletingAccount {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                }
                                Image(systemName: "trash")
                                Text("Delete My Account")
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.red)
                            .cornerRadius(10)
                        }
                        .disabled(isDeletingAccount)
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
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .sheet(isPresented: $showingAttribution) {
            AttributionView()
        }
        .alert("Sign Out", isPresented: $showingSignOutAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Sign Out", role: .destructive) {
                signOut()
            }
        } message: {
            Text("Are you sure you want to sign out?")
        }
        .alert("Unlink Email", isPresented: $showingUnlinkEmailAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Unlink", role: .destructive) {
                unlinkEmail()
            }
        } message: {
            Text("Are you sure you want to unlink your email address? You'll need to use your phone number to sign in.")
        }
        .alert("Unlink Phone Number", isPresented: $showingUnlinkPhoneAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Unlink", role: .destructive) {
                unlinkPhone()
            }
        } message: {
            Text("Are you sure you want to unlink your phone number? You'll need to use your email to sign in.")
        }
        .alert("Delete Account", isPresented: $showingDeleteAccountAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Continue", role: .destructive) {
                showingDeleteAccountConfirmation = true
            }
        } message: {
            Text("Are you sure you want to delete your account? This will permanently remove all your data and cannot be undone.")
        }
        .alert("Final Confirmation", isPresented: $showingDeleteAccountConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete Forever", role: .destructive) {
                deleteAccount()
            }
        } message: {
            Text("This is your final warning. Your account and all data will be permanently deleted. This action cannot be undone. Are you absolutely sure?")
        }
    }
    
    private func changePassword() {
        guard newPassword == confirmPassword else {
            passwordErrorMessage = "New passwords don't match"
            passwordSuccessMessage = nil
            return
        }
        
        // Validate new password
        if let passwordError = InputValidator.getPasswordValidationError(newPassword) {
            passwordErrorMessage = passwordError
            passwordSuccessMessage = nil
            return
        }
        
        // Validate current password is not empty
        if currentPassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            passwordErrorMessage = "Current password is required"
            passwordSuccessMessage = nil
            return
        }
        
        isChangingPassword = true
        passwordErrorMessage = nil
        passwordSuccessMessage = nil
        
        Task {
            do {
                try await authService.changePassword(currentPassword: currentPassword, newPassword: newPassword)
                await MainActor.run {
                    passwordSuccessMessage = "Password changed successfully"
                    currentPassword = ""
                    newPassword = ""
                    confirmPassword = ""
                    isChangingPassword = false
                }
            } catch {
                await MainActor.run {
                    passwordErrorMessage = error.localizedDescription
                    isChangingPassword = false
                }
            }
        }
    }
    
    private func changeUsername() {
        guard !newUsername.isEmpty else { return }
        
        // Validate username
        if let usernameError = InputValidator.getUsernameValidationError(newUsername) {
            usernameErrorMessage = usernameError
            usernameSuccessMessage = nil
            return
        }
        
        isChangingUsername = true
        usernameErrorMessage = nil
        usernameSuccessMessage = nil
        
        Task {
            do {
                try await authService.changeUsername(to: newUsername)
                await MainActor.run {
                    usernameSuccessMessage = "Username changed successfully"
                    newUsername = ""
                    isChangingUsername = false
                }
            } catch {
                await MainActor.run {
                    usernameErrorMessage = error.localizedDescription
                    isChangingUsername = false
                }
            }
        }
    }
    
    private func checkUsernameAvailability() {
        guard !newUsername.isEmpty else {
            usernameErrorMessage = nil
            return
        }
        
        // Validate username format first
        if let usernameError = InputValidator.getUsernameValidationError(newUsername) {
            usernameErrorMessage = usernameError
            isCheckingUsername = false
            return
        }
        
        isCheckingUsername = true
        usernameErrorMessage = nil
        
        Task {
            do {
                let isAvailable = try await authService.isUsernameAvailable(newUsername)
                await MainActor.run {
                    if !isAvailable {
                        usernameErrorMessage = "Username is already taken"
                    }
                    isCheckingUsername = false
                }
            } catch {
                await MainActor.run {
                    usernameErrorMessage = "Error checking username availability"
                    isCheckingUsername = false
                }
            }
        }
    }
    
    private func signOut() {
        do {
            try authService.signOut()
            dismiss()
        } catch {
            print("Error signing out: \(error)")
        }
    }
    
    // MARK: - Email Linking Functions
    
    private func linkEmail() {
        guard !emailToLink.isEmpty && !emailPassword.isEmpty else { return }
        
        isLinkingEmail = true
        emailLinkErrorMessage = nil
        emailLinkSuccessMessage = nil
        
        Task {
            do {
                try await authService.linkEmail(emailToLink, password: emailPassword)
                await MainActor.run {
                    emailLinkSuccessMessage = "Email linked successfully"
                    emailToLink = ""
                    emailPassword = ""
                    isLinkingEmail = false
                }
            } catch {
                await MainActor.run {
                    emailLinkErrorMessage = error.localizedDescription
                    isLinkingEmail = false
                }
            }
        }
    }
    
    private func unlinkEmail() {
        isUnlinkingEmail = true
        emailLinkErrorMessage = nil
        emailLinkSuccessMessage = nil
        
        Task {
            do {
                try await authService.unlinkEmail()
                await MainActor.run {
                    emailLinkSuccessMessage = "Email unlinked successfully"
                    isUnlinkingEmail = false
                }
            } catch {
                await MainActor.run {
                    emailLinkErrorMessage = error.localizedDescription
                    isUnlinkingEmail = false
                }
            }
        }
    }
    
    // MARK: - Phone Linking Functions
    
    private func sendPhoneVerification() {
        guard !phoneNumberToLink.isEmpty else { return }
        
        isLinkingPhone = true
        phoneLinkErrorMessage = nil
        phoneLinkSuccessMessage = nil
        
        Task {
            do {
                try await authService.sendPhoneVerificationCode(phoneNumber: phoneNumberToLink)
                await MainActor.run {
                    phoneLinkSuccessMessage = "Verification code sent"
                    isWaitingForPhoneSMS = true
                    isLinkingPhone = false
                }
            } catch {
                await MainActor.run {
                    phoneLinkErrorMessage = error.localizedDescription
                    isLinkingPhone = false
                }
            }
        }
    }
    
    private func verifyPhoneCode() {
        guard !phoneVerificationCode.isEmpty else { return }
        
        isLinkingPhone = true
        phoneLinkErrorMessage = nil
        phoneLinkSuccessMessage = nil
        
        Task {
            do {
                try await authService.verifyPhoneCode(verificationCode: phoneVerificationCode)
                await MainActor.run {
                    phoneLinkSuccessMessage = "Phone number linked successfully"
                    isLinkingPhone = false
                    isWaitingForPhoneSMS = false
                    phoneNumberToLink = ""
                    phoneVerificationCode = ""
                }
            } catch {
                await MainActor.run {
                    phoneLinkErrorMessage = error.localizedDescription
                    isLinkingPhone = false
                }
            }
        }
    }
    
    private func unlinkPhone() {
        isUnlinkingPhone = true
        phoneLinkErrorMessage = nil
        phoneLinkSuccessMessage = nil
        
        Task {
            do {
                try await authService.unlinkPhone()
                await MainActor.run {
                    phoneLinkSuccessMessage = "Phone number unlinked successfully"
                    isUnlinkingPhone = false
                }
            } catch {
                await MainActor.run {
                    phoneLinkErrorMessage = error.localizedDescription
                    isUnlinkingPhone = false
                }
            }
        }
    }
    
    // MARK: - Profile Functions
    
    private func updateMyMoviePoster() {
        isUpdatingMyPoster = true
        posterUpdateMessage = nil
        
        Task {
            do {
                try await firestoreService.updateCurrentUserTopMoviePoster()
                await MainActor.run {
                    posterUpdateMessage = "Your movie poster updated successfully!"
                    isUpdatingMyPoster = false
                    
                    // Force page reload by posting notification
                    NotificationCenter.default.post(name: .refreshFollowingList, object: nil)
                    
                    // Additional notification for profile refresh
                    NotificationCenter.default.post(name: .refreshProfile, object: nil)
                }
            } catch {
                await MainActor.run {
                    posterUpdateMessage = "Error updating poster: \(error.localizedDescription)"
                    isUpdatingMyPoster = false
                }
            }
        }
    }
    
    // MARK: - Account Deletion
    
    private func deleteAccount() {
        isDeletingAccount = true
        deleteAccountErrorMessage = nil
        
        Task {
            do {
                try await authService.deleteCurrentAccountForLegalReasons(reason: "User requested account deletion")
                await MainActor.run {
                    isDeletingAccount = false
                    // The user will be automatically signed out and the view will dismiss
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isDeletingAccount = false
                    deleteAccountErrorMessage = "Failed to delete account: \(error.localizedDescription)"
                }
            }
        }
    }
    
    // MARK: - Keyboard Dismissal
    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
} 