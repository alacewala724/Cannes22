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
    @State private var isFixingRatings = false
    @State private var ratingsFixMessage: String?
    
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
                
                // Password Change Section
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
                
                // Username Change Section
                Section("Profile") {
                    VStack(spacing: 12) {
                        TextField("New Username", text: $newUsername)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .autocapitalization(.none)
                            .onChange(of: newUsername) { _ in
                                checkUsernameAvailability()
                            }
                        
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
                                if isChangingUsername {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                }
                                Text("Change Username")
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(isChangingUsername || newUsername.isEmpty || isCheckingUsername)
                    }
                    .padding(.vertical, 8)
                }
                
                // Data Management Section
                Section("Data Management") {
                    VStack(spacing: 12) {
                        Text("Fix existing community ratings that have floating-point precision issues")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        
                        if let message = ratingsFixMessage {
                            Text(message)
                                .foregroundColor(.green)
                                .font(.caption)
                        }
                        
                        Button(action: fixCommunityRatings) {
                            HStack {
                                if isFixingRatings {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                }
                                Text("Fix Community Ratings")
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(isFixingRatings)
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
        .alert("Sign Out", isPresented: $showingSignOutAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Sign Out", role: .destructive) {
                signOut()
            }
        } message: {
            Text("Are you sure you want to sign out?")
        }
    }
    
    private func changePassword() {
        guard newPassword == confirmPassword else {
            passwordErrorMessage = "New passwords don't match"
            passwordSuccessMessage = nil
            return
        }
        
        guard newPassword.count >= 6 else {
            passwordErrorMessage = "Password must be at least 6 characters"
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
    
    private func fixCommunityRatings() {
        isFixingRatings = true
        ratingsFixMessage = nil
        
        Task {
            do {
                let firestoreService = FirestoreService()
                try await firestoreService.fixExistingCommunityRatings()
                await MainActor.run {
                    ratingsFixMessage = "Community ratings fixed successfully"
                    isFixingRatings = false
                }
            } catch {
                await MainActor.run {
                    ratingsFixMessage = "Error fixing ratings: \(error.localizedDescription)"
                    isFixingRatings = false
                }
            }
        }
    }
} 