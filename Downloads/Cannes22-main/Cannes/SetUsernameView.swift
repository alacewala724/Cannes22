import SwiftUI
import FirebaseFirestore

struct SetUsernameView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var authService = AuthenticationService.shared
    @State private var username = ""
    @State private var isLoading = false
    @State private var showError = false
    @State private var errorMessage = ""
    
    // Validation states
    @State private var usernameValidationError: String?
    @State private var isCheckingAvailability = false
    @State private var isUsernameAvailable = false
    @State private var sanitizedUsername = ""
    
    var body: some View {
        VStack {
            Text("Welcome to Cannes!")
                .font(.title)
                .fontWeight(.bold)
            
            Text("Choose a Username")
                .font(.title2)
                .fontWeight(.semibold)
                .padding(.top, 8)
            
            Text("This will be your unique identifier in the app")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            VStack(alignment: .leading, spacing: 8) {
                TextField("Username", text: $username)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .textContentType(.username)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .padding(.horizontal)
                    .padding(.top, 20)
                    .onChange(of: username) { _, newUsername in
                        validateUsername(newUsername)
                    }
                
                if let error = usernameValidationError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.horizontal)
                }
                
                if !sanitizedUsername.isEmpty && sanitizedUsername != username {
                    HStack {
                        Text("Suggested: ")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(sanitizedUsername)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.accentColor)
                        Spacer()
                        Button("Use") {
                            username = sanitizedUsername
                        }
                        .font(.caption)
                        .foregroundColor(.accentColor)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 4)
                    .background(Color(.systemGray6))
                    .cornerRadius(6)
                }
                
                // Username requirements
                VStack(alignment: .leading, spacing: 4) {
                    Text("Requirements:")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                    
                    RequirementRow(text: "3-20 characters", isMet: username.count >= 3 && username.count <= 20)
                    RequirementRow(text: "Letters, numbers, and underscores only", isMet: username.replacingOccurrences(of: "[a-zA-Z0-9_]", with: "", options: .regularExpression).isEmpty)
                    RequirementRow(text: "No consecutive underscores", isMet: !username.contains("__"))
                    RequirementRow(text: "Cannot start or end with underscore", isMet: !username.hasPrefix("_") && !username.hasSuffix("_"))
                    RequirementRow(text: "Available username", isMet: isUsernameAvailable && !isCheckingAvailability)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color(.systemGray6))
                .cornerRadius(8)
            }
            
            Button(action: {
                Task {
                    await setUsername()
                }
            }) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Text("Set Username")
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(isFormValid ? Color.blue : Color.gray)
            .foregroundColor(.white)
            .cornerRadius(10)
            .disabled(!isFormValid || isLoading)
            .padding(.horizontal)
            .padding(.top, 16)
        }
        .padding()
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }
    
    private var isFormValid: Bool {
        usernameValidationError == nil && 
        !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        InputValidator.isValidUsername(username) &&
        isUsernameAvailable
    }
    
    private func validateUsername(_ username: String) {
        usernameValidationError = InputValidator.getUsernameValidationError(username)
        sanitizedUsername = InputValidator.sanitizeUsername(username)
        
        // Check availability if username is valid
        if InputValidator.isValidUsername(username) {
            checkUsernameAvailability()
        } else {
            isUsernameAvailable = false
        }
    }
    
    private func checkUsernameAvailability() {
        guard !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            isUsernameAvailable = false
            return
        }
        
        isCheckingAvailability = true
        
        Task {
            do {
                let isAvailable = try await authService.isUsernameAvailable(username)
                await MainActor.run {
                    isUsernameAvailable = isAvailable
                    isCheckingAvailability = false
                }
            } catch {
                await MainActor.run {
                    isUsernameAvailable = false
                    isCheckingAvailability = false
                }
            }
        }
    }
    
    private func setUsername() async {
        guard let userId = authService.currentUser?.uid else { return }
        isLoading = true
        
        // Use sanitized username if available
        let finalUsername = sanitizedUsername.isEmpty ? username : sanitizedUsername
        
        do {
            // Double-check username availability
            let isAvailable = try await authService.isUsernameAvailable(finalUsername)
            guard isAvailable else {
                errorMessage = "Username is already taken"
                showError = true
                isLoading = false
                return
            }
            
            // Save username
            try await Firestore.firestore().collection("users").document(userId).setData([
                "username": finalUsername
            ], merge: true)
            
            await MainActor.run {
                authService.username = finalUsername
                // Cache the username locally
                let userDefaults = UserDefaults.standard
                userDefaults.set(finalUsername, forKey: "cached_username")
                userDefaults.set(userId, forKey: "cached_user_id")
                dismiss()
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
        
        isLoading = false
    }
} 