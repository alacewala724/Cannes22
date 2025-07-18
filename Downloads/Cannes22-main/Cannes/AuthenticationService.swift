import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseCore

class AuthenticationService: ObservableObject {
    static let shared = AuthenticationService()
    private let auth = Auth.auth()
    private let firestore = Firestore.firestore()
    
    @Published var currentUser: User?
    @Published var isAuthenticated = false
    @Published var errorMessage: String?
    @Published var username: String?
    @Published var isReady = false
    
    // Phone authentication properties
    @Published var verificationID: String?
    @Published var isWaitingForSMS = false
    @Published var phoneNumber: String = ""
    
    private init() {
        // Firebase is now configured in AppDelegate
        
        // Add more robust error handling and state management
        do {
            try auth.useUserAccessGroup(nil)
            print("Auth persistence configured successfully")
        } catch {
            print("Error configuring auth persistence: \(error)")
        }
        
        // Restore verification ID if app was terminated during phone auth
        restoreVerificationID()
        
        // Add a timeout for the auth state listener
        _ = Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
            if !isReady {
                await MainActor.run {
                    self.isReady = true
                    self.errorMessage = "Authentication service timed out"
                }
            }
        }
        
        _ = auth.addStateDidChangeListener { [weak self] _, user in
            Task { [weak self] in
                guard let self = self else { return }
                await MainActor.run {
                    self.currentUser = user
                    // Update authentication logic to handle phone users
                    self.isAuthenticated = self.isUserAuthenticated(user: user)
                }

                if let user = user {
                    await self.ensureUserDocument(for: user)

                    // Only check email verification for email users
                    if !self.isUserAuthenticated(user: user) {
                        await MainActor.run {
                            self.isAuthenticated = false
                            if user.email != nil && !user.isEmailVerified {
                                self.errorMessage = "Please verify your email"
                            } else {
                                self.errorMessage = "Authentication required"
                            }
                        }
                    }
                }

                await MainActor.run {
                    self.isReady = true
                }
            }
        }
    }
    
    // Helper method to determine if user is properly authenticated
    private func isUserAuthenticated(user: User?) -> Bool {
        guard let user = user else { return false }
        
        // Phone users: Check if they have a phone number
        if user.phoneNumber != nil {
            return true
        }
        
        // Email users: Check if email is verified
        if user.email != nil {
            return user.isEmailVerified
        }
        
        // Fallback: user exists but unclear type
        return false
    }
    
    private func ensureUserDocument(for user: User) async {
        let userDocRef = firestore.collection("users").document(user.uid)
        
        do {
            let document = try await userDocRef.getDocument()
            
            if !document.exists {
                // Create user document with appropriate data
                var userData: [String: Any] = [
                    "createdAt": FieldValue.serverTimestamp()
                ]
                
                // Add email if available
                if let email = user.email {
                    userData["email"] = email
                }
                
                // Add phone number if available
                if let phoneNumber = user.phoneNumber {
                    userData["phoneNumber"] = phoneNumber
                }
                
                try await userDocRef.setData(userData)
            } else {
                // Update existing document with new auth methods if needed
                var updateData: [String: Any] = [:]
                let existingData = document.data() ?? [:]
                
                // Add phone number if user just linked it
                if let phoneNumber = user.phoneNumber, existingData["phoneNumber"] == nil {
                    updateData["phoneNumber"] = phoneNumber
                }
                
                // Add email if user just linked it
                if let email = user.email, existingData["email"] == nil {
                    updateData["email"] = email
                }
                
                if !updateData.isEmpty {
                    updateData["updatedAt"] = FieldValue.serverTimestamp()
                    try await userDocRef.updateData(updateData)
                }
            }

            if let username = document.data()?["username"] as? String {
                await MainActor.run {
                    self.username = username
                }
            } else {
                await MainActor.run {
                    self.username = nil
                }
            }
        } catch {
            print("Error ensuring user document: \(error.localizedDescription)")
        }
    }
    
    func signIn(email: String, password: String) async throws {
        do {
            let result = try await Auth.auth().signIn(withEmail: email, password: password)
            let user = result.user
            
            if !user.isEmailVerified {
                try await user.sendEmailVerification()
                throw AuthError.custom("Please verify your email. A new verification email has been sent.")
            }
            
            await ensureUserDocument(for: user)
            await MainActor.run {
                self.currentUser = user
                self.isAuthenticated = true
            }
        } catch {
            throw mapAuthError(error)
        }
    }
    
    func signUp(email: String, password: String) async throws {
        do {
            let result = try await auth.createUser(withEmail: email, password: password)
            let user = result.user

            try await user.sendEmailVerification()

            await MainActor.run {
                self.errorMessage = "Please verify your email. A verification link has been sent."
                self.isAuthenticated = false
                self.currentUser = nil
            }

            try auth.signOut()

        } catch {
            throw mapAuthError(error)
        }
    }
    
    func signOut() throws {
        try Auth.auth().signOut()
        self.currentUser = nil
        self.isAuthenticated = false
    }
    
    func sendPasswordReset(email: String) async throws {
        do {
            try await Auth.auth().sendPasswordReset(withEmail: email)
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
            }
            throw error
        }
    }
    
    func changePassword(currentPassword: String, newPassword: String) async throws {
        guard let user = currentUser else {
            throw AuthError.custom("No user is currently signed in")
        }
        
        guard let email = user.email else {
            throw AuthError.custom("Unable to get user email")
        }
        
        // Reauthenticate user with current password
        let credential = EmailAuthProvider.credential(withEmail: email, password: currentPassword)
        
        do {
            try await user.reauthenticate(with: credential)
            try await user.updatePassword(to: newPassword)
        } catch {
            throw mapAuthError(error)
        }
    }
    
    func isUsernameAvailable(_ username: String) async throws -> Bool {
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        // Query Firestore to check if username exists
        let snapshot = try await firestore.collection("users")
            .whereField("username", isEqualTo: trimmedUsername)
            .getDocuments()
        
        return snapshot.documents.isEmpty
    }
    
    func changeUsername(to newUsername: String) async throws {
        guard let user = currentUser else {
            throw AuthError.custom("No user is currently signed in")
        }
        
        let trimmedUsername = newUsername.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        // Double-check username availability
        let isAvailable = try await isUsernameAvailable(trimmedUsername)
        guard isAvailable else {
            throw AuthError.custom("Username is already taken")
        }
        
        // Update username in Firestore
        let userDocRef = firestore.collection("users").document(user.uid)
        
        do {
            try await userDocRef.updateData([
                "username": trimmedUsername,
                "updatedAt": FieldValue.serverTimestamp()
            ])
            
            // Update local username
            await MainActor.run {
                self.username = trimmedUsername
            }
        } catch {
            throw AuthError.custom("Failed to update username: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Phone Authentication
    
    // Helper function to format phone number to E.164 format
    private func formatPhoneNumber(_ phoneNumber: String) -> String {
        // Remove all non-digit characters
        let digits = phoneNumber.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
        
        // Handle different input formats
        if digits.hasPrefix("1") && digits.count == 11 {
            // US number with country code: 1234567890 -> +1234567890
            return "+\(digits)"
        } else if digits.count == 10 {
            // US number without country code: 2345678901 -> +12345678901
            return "+1\(digits)"
        } else if digits.hasPrefix("1") == false && digits.count > 10 {
            // International number: +33123456789 or 33123456789
            return "+\(digits)"
        } else {
            // Return as-is if it already starts with + or has correct format
            return phoneNumber.hasPrefix("+") ? phoneNumber : "+\(digits)"
        }
    }
    
    func verifyPhoneNumber(_ phoneNumber: String) async throws {
        // Ensure Firebase is configured
        guard FirebaseApp.app() != nil else {
            throw AuthError.custom("Firebase is not properly configured")
        }
        
        // Format phone number to E.164 format
        let formattedPhoneNumber = formatPhoneNumber(phoneNumber)
        print("🔵 PHONE AUTH DEBUG: Formatted phone number: \(formattedPhoneNumber)")
        
        // Validate phone number format
        guard formattedPhoneNumber.hasPrefix("+") && formattedPhoneNumber.count >= 10 else {
            throw AuthError.custom("Please enter a valid phone number (e.g., +1234567890)")
        }
        
        // Check if running on simulator and warn user
        #if targetEnvironment(simulator)
        print("⚠️ WARNING: Phone authentication may not work properly on iOS Simulator. Please test on a real device.")
        throw AuthError.custom("Phone authentication requires a real device. Please test on an iPhone, not the simulator.")
        #endif
        
        // Additional Firebase Auth debugging
        print("🔵 PHONE AUTH DEBUG: Firebase App: \(FirebaseApp.app()?.name ?? "nil")")
        print("🔵 PHONE AUTH DEBUG: Auth domain: \(auth.app?.options.projectID ?? "nil")")
        print("🔵 PHONE AUTH DEBUG: App verification disabled: \(auth.settings?.isAppVerificationDisabledForTesting ?? false)")
        
        // Check APNs configuration
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        print("🔵 PHONE AUTH DEBUG: Notification authorization status: \(settings.authorizationStatus.rawValue)")
        print("🔵 PHONE AUTH DEBUG: Alert setting: \(settings.alertSetting.rawValue)")
        print("🔵 PHONE AUTH DEBUG: Badge setting: \(settings.badgeSetting.rawValue)")
        print("🔵 PHONE AUTH DEBUG: Sound setting: \(settings.soundSetting.rawValue)")
        
        await MainActor.run {
            self.phoneNumber = formattedPhoneNumber
            self.isWaitingForSMS = true
            self.errorMessage = nil
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            print("🔵 PHONE AUTH DEBUG: Attempting to verify phone number: \(formattedPhoneNumber)")
            print("🔵 PHONE AUTH DEBUG: Starting PhoneAuthProvider.verifyPhoneNumber call...")
            
            PhoneAuthProvider.provider().verifyPhoneNumber(formattedPhoneNumber, uiDelegate: nil) { [weak self] verificationID, error in
                if let error = error {
                    let nsError = error as NSError
                    print("❌ PHONE AUTH ERROR: \(error.localizedDescription)")
                    print("❌ PHONE AUTH ERROR CODE: \(nsError.code)")
                    print("❌ PHONE AUTH ERROR DOMAIN: \(nsError.domain)")
                    print("❌ PHONE AUTH ERROR USER INFO: \(nsError.userInfo)")
                    
                    // Additional specific error analysis
                    switch nsError.code {
                    case 17093: // FIRAuthErrorCodeMissingClientIdentifier
                        print("❌ CRITICAL: Missing client identifier. This usually means APNs is not configured in Firebase Console.")
                        print("❌ SOLUTION: Go to Firebase Console → Project Settings → Cloud Messaging → iOS app configuration")
                        print("❌ You need to upload your APNs authentication key or certificate.")
                    case 17032: // FIRAuthErrorCodeAppNotAuthorized
                        print("❌ CRITICAL: App not authorized for phone authentication. Check Firebase Console APNs configuration.")
                    case 17046: // FIRAuthErrorCodeCaptchaCheckFailed
                        print("❌ CRITICAL: reCAPTCHA verification failed. This often indicates APNs issues.")
                    case 17052: // FIRAuthErrorCodeInvalidPhoneNumber
                        print("❌ Phone number format issue: \(formattedPhoneNumber)")
                    case 17054: // FIRAuthErrorCodeQuotaExceeded
                        print("❌ SMS quota exceeded for project")
                    default:
                        print("❌ Other phone auth error: \(nsError.code)")
                    }
                    
                    Task { @MainActor in
                        self?.isWaitingForSMS = false
                        self?.errorMessage = self?.mapPhoneAuthError(error) ?? error.localizedDescription
                    }
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let verificationID = verificationID else {
                    print("❌ PHONE AUTH ERROR: No verification ID received")
                    let customError = AuthError.custom("Failed to get verification ID")
                    Task { @MainActor in
                        self?.isWaitingForSMS = false
                        self?.errorMessage = customError.localizedDescription
                    }
                    continuation.resume(throwing: customError)
                    return
                }
                
                print("✅ PHONE AUTH SUCCESS: Received verification ID: \(verificationID)")
                print("✅ SMS should be sent to: \(formattedPhoneNumber)")
                
                Task { @MainActor in
                    self?.verificationID = verificationID
                    self?.saveVerificationID(verificationID)
                }
                
                continuation.resume()
            }
        }
    }
    
    func signInWithPhoneNumber(verificationCode: String) async throws {
        guard let verificationID = verificationID else {
            throw AuthError.custom("No verification ID available. Please request a new code.")
        }
        
        let credential = PhoneAuthProvider.provider().credential(
            withVerificationID: verificationID,
            verificationCode: verificationCode
        )
        
        do {
            let result = try await auth.signIn(with: credential)
            let user = result.user
            
            await ensureUserDocument(for: user)
            await MainActor.run {
                self.currentUser = user
                self.isAuthenticated = true
                self.isWaitingForSMS = false
                self.verificationID = nil
                self.clearVerificationID()
            }
        } catch {
            await MainActor.run {
                self.isWaitingForSMS = false
                self.errorMessage = error.localizedDescription
            }
            throw mapAuthError(error)
        }
    }
    
    // New method for phone sign-up (creates new account)
    func signUpWithPhoneNumber(verificationCode: String) async throws {
        guard let verificationID = verificationID else {
            throw AuthError.custom("No verification ID available. Please request a new code.")
        }
        
        let credential = PhoneAuthProvider.provider().credential(
            withVerificationID: verificationID,
            verificationCode: verificationCode
        )
        
        do {
            // For phone authentication, Firebase will either sign in to existing account or create new one
            // We can't easily distinguish between sign-up and sign-in with phone numbers
            let result = try await auth.signIn(with: credential)
            let user = result.user
            
            await ensureUserDocument(for: user)
            await MainActor.run {
                self.currentUser = user
                self.isAuthenticated = true
                self.isWaitingForSMS = false
                self.verificationID = nil
                self.clearVerificationID()
            }
        } catch {
            await MainActor.run {
                self.isWaitingForSMS = false
                self.errorMessage = error.localizedDescription
            }
            throw mapAuthError(error)
        }
    }
    
    // New method to link phone number to existing account
    func linkPhoneNumber(verificationCode: String) async throws {
        guard let currentUser = currentUser else {
            throw AuthError.custom("No user is currently signed in")
        }
        
        guard let verificationID = verificationID else {
            throw AuthError.custom("No verification ID available. Please request a new code.")
        }
        
        let credential = PhoneAuthProvider.provider().credential(
            withVerificationID: verificationID,
            verificationCode: verificationCode
        )
        
        do {
            let result = try await currentUser.link(with: credential)
            let user = result.user
            
            await ensureUserDocument(for: user)
            await MainActor.run {
                self.currentUser = user
                self.isWaitingForSMS = false
                self.verificationID = nil
                self.clearVerificationID()
            }
        } catch {
            await MainActor.run {
                self.isWaitingForSMS = false
                self.errorMessage = error.localizedDescription
            }
            throw mapAuthError(error)
        }
    }
    
    // Check if current user has phone number linked
    func hasPhoneNumberLinked() -> Bool {
        return currentUser?.phoneNumber != nil
    }
    
    // Get current user's phone number
    func getUserPhoneNumber() -> String? {
        return currentUser?.phoneNumber
    }
    
    // Unlink phone number from account
    func unlinkPhoneNumber() async throws {
        guard let currentUser = currentUser else {
            throw AuthError.custom("No user is currently signed in")
        }
        
        guard currentUser.phoneNumber != nil else {
            throw AuthError.custom("No phone number is linked to this account")
        }
        
        do {
            let user = try await currentUser.unlink(fromProvider: PhoneAuthProviderID)
            
            // Update Firestore to remove phone number
            let userDocRef = firestore.collection("users").document(user.uid)
            try await userDocRef.updateData([
                "phoneNumber": FieldValue.delete(),
                "updatedAt": FieldValue.serverTimestamp()
            ])
            
            await MainActor.run {
                self.currentUser = user
            }
        } catch {
            throw mapAuthError(error)
        }
    }
    
    func resendVerificationCode() async throws {
        guard !phoneNumber.isEmpty else {
            throw AuthError.custom("No phone number available. Please start over.")
        }
        
        try await verifyPhoneNumber(phoneNumber)
    }
    
    private func saveVerificationID(_ verificationID: String) {
        UserDefaults.standard.set(verificationID, forKey: "authVerificationID")
        UserDefaults.standard.set(phoneNumber, forKey: "authPhoneNumber")
    }
    
    private func restoreVerificationID() {
        if let savedVerificationID = UserDefaults.standard.string(forKey: "authVerificationID"),
           let savedPhoneNumber = UserDefaults.standard.string(forKey: "authPhoneNumber") {
            self.verificationID = savedVerificationID
            self.phoneNumber = savedPhoneNumber
            self.isWaitingForSMS = true
        }
    }
    
    private func clearVerificationID() {
        UserDefaults.standard.removeObject(forKey: "authVerificationID")
        UserDefaults.standard.removeObject(forKey: "authPhoneNumber")
    }
    
    func cancelPhoneAuth() {
        Task { @MainActor in
            self.isWaitingForSMS = false
            self.verificationID = nil
            self.phoneNumber = ""
            self.clearVerificationID()
        }
    }
    
    private func mapAuthError(_ error: Error) -> Error {
        let nsError = error as NSError

        switch nsError.code {
        case 17009, 17004:
            return AuthError.custom("Incorrect email or password.")
        case 17011:
            return AuthError.custom("No user found with this email.")
        case 17008:
            return AuthError.custom("The email address is badly formatted.")
        case 17007:
            return AuthError.custom("An account already exists with this email.")
        case 17026:
            return AuthError.custom("Password must be at least 6 characters.")
        case 17010:
            return AuthError.custom("Too many login attempts. Try again later.")
        case 17014:
            return AuthError.custom("Current password is incorrect.")
        case 17025:
            return AuthError.custom("The password is invalid or the user does not have a password.")
        case 17012:
            return AuthError.custom("This operation is sensitive and requires recent authentication. Please sign in again.")
        default:
            return AuthError.custom("Something went wrong. Please try again.")
        }
    }
    
    private func mapPhoneAuthError(_ error: Error) -> String {
        let nsError = error as NSError
        
        switch nsError.code {
        case 17093: // FIRAuthErrorCodeMissingClientIdentifier
            return "Phone authentication is not properly configured. Please contact support to enable SMS verification."
        case 17010: // FIRAuthErrorCodeTooManyRequests
            return "Too many SMS requests. Please wait before trying again."
        case 17052: // FIRAuthErrorCodeInvalidPhoneNumber
            return "Invalid phone number. Please check the format and try again."
        case 17054: // FIRAuthErrorCodeQuotaExceeded
            return "SMS quota exceeded. Please try again later."
        case 17046: // FIRAuthErrorCodeCaptchaCheckFailed
            return "reCAPTCHA verification failed. Please try again."
        case 17032: // FIRAuthErrorCodeAppNotAuthorized
            return "App not authorized for phone authentication. Please contact support."
        case 17053: // FIRAuthErrorCodeMissingPhoneNumber
            return "Phone number is required."
        case 17045: // FIRAuthErrorCodeInvalidVerificationCode
            return "Invalid verification code. Please check and try again."
        case 17044: // FIRAuthErrorCodeInvalidVerificationID
            return "Invalid verification session. Please request a new code."
        case 17051: // FIRAuthErrorCodeSessionExpired
            return "Verification session expired. Please request a new code."
        default:
            return error.localizedDescription
        }
    }
}

extension AuthErrorCode {
    static let networkError = AuthErrorCode(rawValue: -1009)
}

enum AuthError: LocalizedError {
    case custom(String)

    var errorDescription: String? {
        switch self {
        case .custom(let message):
            return message
        }
    }
} 