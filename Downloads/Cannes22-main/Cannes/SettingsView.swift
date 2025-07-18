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
    
    @State private var isChangingPassword = false
    @State private var isChangingUsername = false
    @State private var isCheckingUsername = false
    
    @State private var passwordErrorMessage: String?
    @State private var usernameErrorMessage: String?
    @State private var passwordSuccessMessage: String?
    @State private var usernameSuccessMessage: String?
    
    @State private var showingSignOutAlert = false
    
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
                        
                        HStack {
                            Text("Username")
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("@\(authService.username ?? "Unknown")")
                        }
                    }
                    .padding(.vertical, 4)
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
                        Text("⚠️ Running on Simulator")
                            .font(.caption)
                            .foregroundColor(.orange)
                        #else
                        Text("✅ Running on Real Device")
                            .font(.caption)
                            .foregroundColor(.green)
                        #endif
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
} 