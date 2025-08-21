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
    @Published var isUsernameLoading = false  // Add loading state for username
    
    // Phone authentication properties
    @Published var verificationID: String?
    @Published var isWaitingForSMS = false
    @Published var phoneNumber: String = ""
    
    // reCAPTCHA delegate
    private var recaptchaDelegate: PhoneAuthProviderDelegate?
    
    // UserDefaults keys for username caching
    private let usernameKey = "cached_username"
    private let userIdKey = "cached_user_id"
    
    private init() {
        // Firebase is now configured in AppDelegate
        
        // Remove the app verification disabled setting to allow proper APNs-based verification
        // Auth.auth().settings?.isAppVerificationDisabledForTesting = true  // REMOVED
        
        // Add more robust error handling and state management
        do {
            try auth.useUserAccessGroup(nil)
            print("Auth persistence configured successfully")
        } catch {
            print("Error configuring auth persistence: \(error)")
        }
        
        // Restore verification ID if app was terminated during phone auth
        restoreVerificationID()
        
        // Don't load cached username here - wait for user authentication
        // loadCachedUsername()  // REMOVED
        
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
                    // Clear any old cached data when a new user signs in
                    await self.clearOldUserCache(for: user)
                    
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
                } else {
                    // User signed out - clear all cached data
                    await MainActor.run {
                        self.clearCachedUsername()
                        self.username = nil
                        self.isUsernameLoading = false
                    }
                }

                await MainActor.run {
                    self.isReady = true
                }
            }
        }
    }
    
    // MARK: - Username Caching
    
    private func loadCachedUsername() {
        let userDefaults = UserDefaults.standard
        if let cachedUserId = userDefaults.string(forKey: userIdKey),
           let cachedUsername = userDefaults.string(forKey: usernameKey),
           let currentUser = auth.currentUser {
            
            print("🔵 USERNAME DEBUG: Found cached username: \(cachedUsername)")
            print("🔵 USERNAME DEBUG: Cached user ID: \(cachedUserId)")
            print("🔵 USERNAME DEBUG: Current user ID: \(currentUser.uid)")
            
            if cachedUserId == currentUser.uid {
                self.username = cachedUsername
                print("🔵 USERNAME DEBUG: User IDs match - loaded cached username: \(cachedUsername)")
            } else {
                print("🔵 USERNAME DEBUG: User ID mismatch - clearing cached username")
                clearCachedUsername()
            }
        } else {
            print("🔵 USERNAME DEBUG: No cached username found or missing data")
        }
    }
    
    private func cacheUsername(_ username: String, for userId: String) {
        let userDefaults = UserDefaults.standard
        userDefaults.set(username, forKey: usernameKey)
        userDefaults.set(userId, forKey: userIdKey)
        print("🔵 USERNAME DEBUG: Caching username: \(username) for user: \(userId)")
    }
    
    private func clearCachedUsername() {
        let userDefaults = UserDefaults.standard
        userDefaults.removeObject(forKey: usernameKey)
        userDefaults.removeObject(forKey: userIdKey)
        print("🔵 USERNAME DEBUG: Cleared cached username")
    }
    
    // Debug function to manually clear username cache
    func clearUsernameCache() {
        clearCachedUsername()
        self.username = nil
        self.isUsernameLoading = false
        print("🔵 USERNAME DEBUG: Manually cleared username cache")
    }
    
    // Clear old user cache when a new user signs in
    private func clearOldUserCache(for user: User) async {
        let userDefaults = UserDefaults.standard
        if let cachedUserId = userDefaults.string(forKey: userIdKey),
           cachedUserId != user.uid {
            print("🔵 USERNAME DEBUG: Different user signed in - clearing old cache")
            print("🔵 USERNAME DEBUG: Old cached user ID: \(cachedUserId)")
            print("🔵 USERNAME DEBUG: New user ID: \(user.uid)")
            
            await MainActor.run {
                self.clearCachedUsername()
                self.username = nil
                self.isUsernameLoading = false
            }
        } else {
            print("🔵 USERNAME DEBUG: Same user or no cached data")
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
        
        // Set username loading state only if we don't already have a username
        if self.username == nil {
            await MainActor.run {
                self.isUsernameLoading = true
                print("🔵 USERNAME DEBUG: Starting username loading for user: \(user.uid)")
            }
        } else {
            print("🔵 USERNAME DEBUG: Username already set, skipping loading for user: \(user.uid)")
        }
        
        do {
            let document = try await userDocRef.getDocument()
            
            if !document.exists {
                // Create user document with appropriate data
                var userData: [String: Any] = [
                    "createdAt": FieldValue.serverTimestamp(),
                    "movieCount": 0  // Initialize movie count for new users
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
                print("ensureUserDocument: Created new user document with movieCount: 0")
                
                // For new users, username will be nil (they need to set it)
                await MainActor.run {
                    self.username = nil
                    self.isUsernameLoading = false
                    print("🔵 USERNAME DEBUG: New user - no username set")
                }
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
                
                // Initialize movieCount if it doesn't exist (for existing users)
                if existingData["movieCount"] == nil {
                    updateData["movieCount"] = 0
                    print("ensureUserDocument: Initializing movieCount for existing user")
                }
                
                if !updateData.isEmpty {
                    updateData["updatedAt"] = FieldValue.serverTimestamp()
                    try await userDocRef.updateData(updateData)
                }
                
                // Sync movie count for existing users
                await syncMovieCount(for: user.uid)
                
                // Only retrieve username if we don't already have one
                if self.username == nil {
                    // Retrieve username from existing document
                    if let username = existingData["username"] as? String {
                        await MainActor.run {
                            self.username = username
                            self.isUsernameLoading = false
                            // Cache the username locally
                            self.cacheUsername(username, for: user.uid)
                        }
                        print("🔵 USERNAME DEBUG: Retrieved existing username: \(username)")
                        print("🔵 USERNAME DEBUG: Username source: Firestore document")
                    } else {
                        // If no username in Firestore, try to use cached username ONLY if it matches current user
                        let userDefaults = UserDefaults.standard
                        if let cachedUserId = userDefaults.string(forKey: userIdKey),
                           let cachedUsername = userDefaults.string(forKey: usernameKey),
                           cachedUserId == user.uid {
                            await MainActor.run {
                                self.username = cachedUsername
                                self.isUsernameLoading = false
                                print("🔵 USERNAME DEBUG: Using cached username: \(cachedUsername)")
                            }
                            print("🔵 USERNAME DEBUG: Username source: UserDefaults cache")
                        } else {
                            await MainActor.run {
                                self.username = nil
                                self.isUsernameLoading = false
                            }
                            print("🔵 USERNAME DEBUG: No username found for existing user")
                        }
                    }
                } else {
                    // Username already set from existing account check
                    await MainActor.run {
                        self.isUsernameLoading = false
                    }
                    print("🔵 USERNAME DEBUG: Username already set from existing account check")
                    print("🔵 USERNAME DEBUG: Current username value: \(self.username ?? "nil")")
                }
            }
        } catch {
            print("Error ensuring user document: \(error.localizedDescription)")
            // If Firestore fails, try to use cached username
            let userDefaults = UserDefaults.standard
            if let cachedUserId = userDefaults.string(forKey: userIdKey),
               let cachedUsername = userDefaults.string(forKey: usernameKey),
               cachedUserId == user.uid {
                await MainActor.run {
                    self.username = cachedUsername
                    self.isUsernameLoading = false
                    print("🔵 USERNAME DEBUG: Using cached username due to Firestore error")
                }
            } else {
                await MainActor.run {
                    self.username = nil
                    self.isUsernameLoading = false
                }
            }
        }
    }
    
    // Sync movie count for existing users
    private func syncMovieCount(for userId: String) async {
        do {
            let snapshot = try await firestore.collection("users")
                .document(userId)
                .collection("rankings")
                .getDocuments()
            
            let movieCount = snapshot.documents.count
            
            try await firestore.collection("users")
                .document(userId)
                .updateData([
                    "movieCount": movieCount
                ])
            
            print("syncMovieCount: Synced movie count to \(movieCount) for user \(userId)")
        } catch {
            print("syncMovieCount: Error syncing movie count: \(error.localizedDescription)")
        }
    }
    
    func signIn(email: String, password: String) async throws {
        // Validate input before making API call
        if let emailError = InputValidator.getEmailValidationError(email) {
            throw AuthError.custom(emailError)
        }
        
        if password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw AuthError.custom("Password is required")
        }
        
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
        // Validate input before making API call
        if let emailError = InputValidator.getEmailValidationError(email) {
            throw AuthError.custom(emailError)
        }
        
        if let passwordError = InputValidator.getPasswordValidationError(password) {
            throw AuthError.custom(passwordError)
        }
        
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
        self.username = nil  // Clear the username
        self.isUsernameLoading = false  // Reset loading state
        clearCachedUsername()  // Clear cached username
        print("🔵 USERNAME DEBUG: Cleared username on sign out")
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
        
        // Validate username before making API call
        if let usernameError = InputValidator.getUsernameValidationError(newUsername) {
            throw AuthError.custom(usernameError)
        }
        
        let sanitizedUsername = InputValidator.sanitizeUsername(newUsername)
        
        // Double-check username availability
        let isAvailable = try await isUsernameAvailable(sanitizedUsername)
        guard isAvailable else {
            throw AuthError.custom("Username is already taken")
        }
        
        // Update username in Firestore
        let userDocRef = firestore.collection("users").document(user.uid)
        
        do {
            try await userDocRef.updateData([
                "username": sanitizedUsername,
                "updatedAt": FieldValue.serverTimestamp()
            ])
            
            // Update local username
            await MainActor.run {
                self.username = sanitizedUsername
                self.isUsernameLoading = false
            }
        } catch {
            throw AuthError.custom("Failed to update username: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Phone Authentication
    
    // Helper method to check if APNs token is ready for phone authentication
    func isAPNsTokenReady() async -> Bool {
        let isAPNsTokenSet = await AppDelegate.isAPNsTokenSet
        let isRegisteredForRemoteNotifications = await UIApplication.shared.isRegisteredForRemoteNotifications
        
        print("🔵 APNs Token Check: Token set: \(isAPNsTokenSet), Registered: \(isRegisteredForRemoteNotifications)")
        
        return isAPNsTokenSet && isRegisteredForRemoteNotifications
    }
    
    // Helper method to wait for APNs token to be ready (with timeout)
    func waitForAPNsToken(timeout: TimeInterval = 10.0) async -> Bool {
        print("🔵 Waiting for APNs token to be ready...")
        
        let startTime = Date()
        while Date().timeIntervalSince(startTime) < timeout {
            if await isAPNsTokenReady() {
                print("✅ APNs token is ready!")
                return true
            }
            
            // Wait 100ms before checking again
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        
        print("❌ Timeout waiting for APNs token to be ready")
        return false
    }
    
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
        
        // Check if APNs token is ready (critical for phone auth)
        let isAPNsTokenSet = await AppDelegate.isAPNsTokenSet
        let isRegisteredForRemoteNotifications = await UIApplication.shared.isRegisteredForRemoteNotifications
        
        print("🔵 PHONE AUTH DEBUG: APNs token set: \(isAPNsTokenSet)")
        print("🔵 PHONE AUTH DEBUG: Registered for remote notifications: \(isRegisteredForRemoteNotifications)")
        
        if !isAPNsTokenSet {
            print("❌ CRITICAL: APNs token not set with Firebase Auth yet!")
            print("❌ This will cause phone authentication to fail with error 17093")
            print("💡 SOLUTION: Wait for APNs token to be set before attempting phone verification")
            
            // Try to wait for APNs token to be ready
            let tokenReady = await waitForAPNsToken(timeout: 5.0)
            
            if !tokenReady {
                // For development, we can still try with test numbers
                let testPhoneNumbers = ["+1234567890", "+1555123456", "+1999999999", "+16505551234", "+16505550000"]
                let isTestNumber = testPhoneNumbers.contains(formatPhoneNumber(phoneNumber))
                
                if !isTestNumber {
                    throw AuthError.custom("APNs token not ready. Please wait a moment and try again, or use a test number like +16505551234 for development.")
                } else {
                    print("🔧 DEBUG: Using test number - proceeding despite APNs token not being set")
                }
            } else {
                print("✅ APNs token became ready while waiting!")
            }
        }
        
        // Format phone number to E.164 format
        let formattedPhoneNumber = formatPhoneNumber(phoneNumber)
        print("🔵 PHONE AUTH DEBUG: Formatted phone number: \(formattedPhoneNumber)")
        
        // Validate phone number format
        guard formattedPhoneNumber.hasPrefix("+") && formattedPhoneNumber.count >= 10 else {
            throw AuthError.custom("Please enter a valid phone number (e.g., +1234567890)")
        }
        
        // Check if this is a test number
        let testPhoneNumbers = ["+1234567890", "+1555123456", "+1999999999", "+16505551234", "+16505550000"]
        let isTestNumber = testPhoneNumbers.contains(formattedPhoneNumber)
        
        if isTestNumber {
            print("🔵 PHONE AUTH DEBUG: Using test phone number: \(formattedPhoneNumber)")
            print("⚠️ NOTE: This is a test number. For production, configure APNs in Firebase Console.")
        } else {
            print("🔵 PHONE AUTH DEBUG: Using real phone number: \(formattedPhoneNumber)")
            print("💡 TIP: Using APNs-based verification for real phone numbers")
        }
        
        // Check if running on simulator and provide helpful guidance
        #if targetEnvironment(simulator)
        if !isTestNumber {
            print("⚠️ WARNING: Real phone numbers may not work properly on iOS Simulator.")
            print("💡 TIP: Test on a real device for best results with real phone numbers.")
        }
        #endif
        
        // Additional Firebase Auth debugging
        print("🔵 PHONE AUTH DEBUG: Firebase App: \(FirebaseApp.app()?.name ?? "nil")")
        print("🔵 PHONE AUTH DEBUG: Auth domain: \(auth.app?.options.projectID ?? "nil")")
        print("🔵 PHONE AUTH DEBUG: App verification enabled for APNs-based verification")
        print("🔵 PHONE AUTH DEBUG: APNs-based silent push verification enabled")
        
        // Check if phone authentication is enabled
        print("🔵 PHONE AUTH DEBUG: Checking if phone auth is enabled...")
        // Try to get current user to check auth state
        let currentUser = Auth.auth().currentUser
        print("🔵 PHONE AUTH DEBUG: Current user: \(currentUser?.uid ?? "nil")")
        print("🔵 PHONE AUTH DEBUG: Current user phone: \(currentUser?.phoneNumber ?? "nil")")
        
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
        
        print("🔵 PHONE AUTH DEBUG: Attempting to verify phone number: \(formattedPhoneNumber)")
        print("🔵 PHONE AUTH DEBUG: Starting PhoneAuthProvider.verifyPhoneNumber call...")
        
        // Create reCAPTCHA delegate for real phone numbers to bypass APNs requirement
        var delegate: PhoneAuthProviderDelegate? = nil
        
        // Check if APNs is properly configured for real phone numbers
        let shouldUseRecaptcha = !isTestNumber && !isAPNsTokenSet
        
        if shouldUseRecaptcha {
            delegate = PhoneAuthProviderDelegate()
            self.recaptchaDelegate = delegate
            print("🔵 PHONE AUTH DEBUG: Using reCAPTCHA delegate for real phone number (APNs not configured)")
            print("🔵 PHONE AUTH DEBUG: reCAPTCHA delegate created: \(String(describing: delegate))")
        } else if !isTestNumber {
            print("🔵 PHONE AUTH DEBUG: Using APNs-based verification for real phone number")
        } else {
            print("🔵 PHONE AUTH DEBUG: Using test number - no delegate needed")
        }
        
        // Use reCAPTCHA delegate only when APNs is not available
        let provider = PhoneAuthProvider.provider()
        
        do {
            print("🔵 PHONE AUTH DEBUG: Calling verifyPhoneNumber with uiDelegate: \(shouldUseRecaptcha ? "YES" : "NO")")
            let verificationID = try await provider.verifyPhoneNumber(
                formattedPhoneNumber,
                uiDelegate: shouldUseRecaptcha ? delegate : nil
            )
            
            print("✅ PHONE AUTH SUCCESS: Received verification ID: \(verificationID)")
            if isTestNumber {
                print("✅ Test SMS should be sent to: \(formattedPhoneNumber)")
                print("💡 Test numbers use Firebase's built-in verification system")
            } else if shouldUseRecaptcha {
                print("✅ Real SMS should be sent to: \(formattedPhoneNumber)")
                print("💡 Real numbers using reCAPTCHA verification (APNs not configured)")
            } else {
                print("✅ Real SMS should be sent to: \(formattedPhoneNumber)")
                print("💡 Real numbers using APNs-based verification")
            }
            
            await MainActor.run {
                self.verificationID = verificationID
                self.saveVerificationID(verificationID)
            }
        } catch {
            let nsError = error as NSError
            print("❌ PHONE AUTH ERROR: \(error.localizedDescription)")
            print("❌ PHONE AUTH ERROR CODE: \(nsError.code)")
            print("❌ PHONE AUTH ERROR DOMAIN: \(nsError.domain)")
            print("❌ PHONE AUTH ERROR USER INFO: \(nsError.userInfo)")
            
            // Additional specific error analysis
            switch nsError.code {
            case 17093: // FIRAuthErrorCodeMissingClientIdentifier
                print("❌ CRITICAL: Missing client identifier. This means APNs is not configured in Firebase Console.")
                print("❌ SOLUTION: Go to Firebase Console → Project Settings → Cloud Messaging → iOS app configuration")
                print("❌ You need to upload your APNs authentication key or certificate.")
                if !isTestNumber {
                    print("💡 For real phone numbers, you MUST configure APNs in Firebase Console for direct SMS delivery.")
                    print("💡 Without APNs, real numbers will use reCAPTCHA verification.")
                    print("💡 Test numbers like +16505551234 will work without APNs configuration.")
                    print("💡 Try using test numbers for development: +16505551234, +16505550000")
                }
            case 17032: // FIRAuthErrorCodeAppNotAuthorized
                print("❌ CRITICAL: App not authorized for phone authentication. Check Firebase Console APNs configuration.")
            case 17046: // FIRAuthErrorCodeCaptchaCheckFailed
                print("❌ CRITICAL: reCAPTCHA verification failed. This often indicates APNs issues.")
                if !isTestNumber {
                    print("💡 TIP: Configure APNs in Firebase Console to avoid reCAPTCHA for real phone numbers.")
                }
                print("🔵 reCAPTCHA DEBUG: This error suggests the reCAPTCHA web view didn't load properly")
                print("🔵 reCAPTCHA DEBUG: Check if the reCAPTCHA delegate was called")
            case 17052: // FIRAuthErrorCodeInvalidPhoneNumber
                print("❌ Phone number format issue: \(formattedPhoneNumber)")
            case 17054: // FIRAuthErrorCodeQuotaExceeded
                print("❌ SMS quota exceeded for project")
            case 17020: // FIRAuthErrorCodeNetworkError
                print("❌ Network error. Check internet connection.")
            case 17010: // FIRAuthErrorCodeTooManyRequests
                print("❌ Too many requests. Please wait before trying again.")
            case 17022: // FIRAuthErrorCodeAppNotVerified
                print("❌ App not verified. This might be a simulator issue.")
            default:
                print("❌ Other phone auth error: \(nsError.code)")
                print("❌ Full error details: \(nsError)")
            }
            
            await MainActor.run {
                self.isWaitingForSMS = false
                self.errorMessage = self.mapPhoneAuthError(error)
            }
            throw error
        }
    }
    
    // Check if a phone number is available for sign-up
    func isPhoneNumberAvailable(_ phoneNumber: String) async -> Bool {
        let formattedPhoneNumber = formatPhoneNumber(phoneNumber)
        return !(await checkIfPhoneNumberExists(formattedPhoneNumber))
    }
    
    func signInWithPhoneNumber(verificationCode: String) async throws {
        guard let verificationID = verificationID else {
            throw AuthError.custom("No verification ID available. Please request a new code.")
        }
        
        print("🔵 PHONE AUTH DEBUG: Starting signInWithPhoneNumber")
        print("🔵 PHONE AUTH DEBUG: Current phone number: \(phoneNumber)")
        
        let credential = PhoneAuthProvider.provider().credential(
            withVerificationID: verificationID,
            verificationCode: verificationCode
        )
        
        do {
            let result = try await auth.signIn(with: credential)
            let user = result.user
            let isNewUser = result.additionalUserInfo?.isNewUser ?? false
            
            print("🔵 PHONE AUTH DEBUG: Sign-in successful for user: \(user.uid)")
            print("🔵 PHONE AUTH DEBUG: User phone number from Firebase: \(user.phoneNumber ?? "nil")")
            print("🔵 PHONE AUTH DEBUG: Is new user: \(isNewUser)")
            
            if isNewUser {
                print("🔵 PHONE AUTH DEBUG: New user - will create Firestore doc and prompt for username")
                // First-time signup → create Firestore doc, ask for username, etc.
                await ensureUserDocument(for: user)  // will create brand-new doc
            } else {
                print("🔵 PHONE AUTH DEBUG: Existing user - will sync existing Firestore doc")
                // Returning user → Firestore doc already exists
                await ensureUserDocument(for: user)  // will just sync fields
            }
            
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
            let result = try await auth.signIn(with: credential)
            let user = result.user
            let isNewUser = result.additionalUserInfo?.isNewUser ?? false
            
            print("🔵 PHONE AUTH DEBUG: Sign-up attempt for user: \(user.uid)")
            print("🔵 PHONE AUTH DEBUG: Is new user: \(isNewUser)")
            
            if !isNewUser {
                throw AuthError.custom("An account already exists with this phone number. Please sign in instead.")
            }
            
            print("🔵 PHONE AUTH DEBUG: Creating new account for phone number")
            
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
    
    // Check if a phone number is already associated with an account
    private func checkIfPhoneNumberExists(_ phoneNumber: String) async -> Bool {
        let formattedPhoneNumber = formatPhoneNumber(phoneNumber)
        
        // Extract last 10 digits for matching
        let digits = formattedPhoneNumber.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
        let lastTenDigits = digits.suffix(10)
        
        print("🔵 PHONE AUTH DEBUG: Checking if phone number exists - last 10 digits: \(lastTenDigits)")
        
        // Query Firestore to check if any user document has this phone number
        do {
            let allUsersSnapshot = try await firestore.collection("users")
                .whereField("phoneNumber", isGreaterThan: "")
                .getDocuments()
            
            // Search through all users to find one with matching last 10 digits
            for document in allUsersSnapshot.documents {
                let storedPhoneNumber = document.data()["phoneNumber"] as? String ?? ""
                let storedDigits = storedPhoneNumber.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
                let storedLastTen = storedDigits.suffix(10)
                
                if storedLastTen == lastTenDigits {
                    print("🔵 PHONE AUTH DEBUG: Found existing phone number: \(storedPhoneNumber)")
                    return true
                }
            }
            
            print("🔵 PHONE AUTH DEBUG: No existing phone number found")
            return false
        } catch {
            print("Error checking if phone number exists: \(error)")
            // If we can't check, assume it exists to prevent potential security issues
            return true
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
        
        // Double-check that this phone number isn't already associated with another account
        let isExistingAccount = await checkIfPhoneNumberExists(phoneNumber)
        
        if isExistingAccount {
            throw AuthError.custom("This phone number is already associated with another account. Please use a different phone number.")
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
        } catch let error as NSError {
            await MainActor.run {
                self.isWaitingForSMS = false
                self.errorMessage = error.localizedDescription
            }
            
            // Handle specific phone linking errors
            switch error.code {
            case AuthErrorCode.credentialAlreadyInUse.rawValue:
                throw AuthError.custom("This phone number is already associated with another account. Please use a different phone number or contact support.")
            case AuthErrorCode.accountExistsWithDifferentCredential.rawValue:
                throw AuthError.custom("An account already exists with this phone number using a different sign-in method.")
            case AuthErrorCode.requiresRecentLogin.rawValue:
                throw AuthError.custom("This operation requires recent authentication. Please sign out and sign in again.")
            default:
                throw mapAuthError(error)
            }
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
            return "APNs not configured for real phone numbers. Use test numbers like +16505551234 for development, or configure APNs in Firebase Console for real numbers."
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
    
    // MARK: - Email Linking for Phone Users
    
    /// Link an email address to a phone-authenticated user
    func linkEmail(_ email: String, password: String) async throws {
        guard let currentUser = Auth.auth().currentUser else {
            throw AuthError.custom("No user is currently signed in")
        }
        
        // Check if user has phone number but no email
        guard currentUser.phoneNumber != nil && currentUser.email == nil else {
            throw AuthError.custom("Email linking is only available for phone-authenticated users without an email")
        }
        
        // Validate input before making API call
        if let emailError = InputValidator.getEmailValidationError(email) {
            throw AuthError.custom(emailError)
        }
        
        if let passwordError = InputValidator.getPasswordValidationError(password) {
            throw AuthError.custom(passwordError)
        }
        
        // Create email credential
        let credential = EmailAuthProvider.credential(withEmail: email, password: password)
        
        do {
            // Link the email credential to the current user
            let result = try await currentUser.link(with: credential)
            print("✅ Email linked successfully: \(result.user.email ?? "unknown")")
            
            // Update the current user info
            await MainActor.run {
                self.currentUser = result.user
            }
            
        } catch let error as NSError {
            print("❌ Email linking failed: \(error.localizedDescription)")
            
            switch error.code {
            case AuthErrorCode.emailAlreadyInUse.rawValue:
                throw AuthError.custom("This email is already associated with another account")
            case AuthErrorCode.invalidEmail.rawValue:
                throw AuthError.custom("Please enter a valid email address")
            case AuthErrorCode.weakPassword.rawValue:
                throw AuthError.custom("Password is too weak. Please choose a stronger password")
            case AuthErrorCode.wrongPassword.rawValue:
                throw AuthError.custom("Incorrect password for this email address")
            default:
                throw AuthError.custom("Failed to link email: \(error.localizedDescription)")
            }
        }
    }
    
    /// Unlink email from a phone-authenticated user
    func unlinkEmail() async throws {
        guard let currentUser = Auth.auth().currentUser else {
            throw AuthError.custom("No user is currently signed in")
        }
        
        // Check if user has both phone and email
        guard currentUser.phoneNumber != nil && currentUser.email != nil else {
            throw AuthError.custom("Can only unlink email from users with both phone and email")
        }
        
        do {
            // Unlink the email provider
            let result = try await currentUser.unlink(fromProvider: "password")
            print("✅ Email unlinked successfully")
            
            // Update the current user info
            await MainActor.run {
                self.currentUser = result
            }
            
        } catch let error as NSError {
            print("❌ Email unlinking failed: \(error.localizedDescription)")
            throw AuthError.custom("Failed to unlink email: \(error.localizedDescription)")
        }
    }
    
    /// Check if the current user can link an email
    var canLinkEmail: Bool {
        guard let currentUser = Auth.auth().currentUser else { return false }
        return currentUser.phoneNumber != nil && currentUser.email == nil
    }
    
    /// Check if the current user can unlink their email
    var canUnlinkEmail: Bool {
        guard let currentUser = Auth.auth().currentUser else { return false }
        return currentUser.phoneNumber != nil && currentUser.email != nil
    }
    
    /// Check if the current user signed up with phone
    var isPhoneUser: Bool {
        guard let currentUser = Auth.auth().currentUser else { return false }
        return currentUser.phoneNumber != nil
    }
    
    /// Check if the current user signed up with email
    var isEmailUser: Bool {
        guard let currentUser = Auth.auth().currentUser else { return false }
        return currentUser.email != nil
    }
    
    /// Check if the current user can link a phone number
    var canLinkPhone: Bool {
        guard let currentUser = Auth.auth().currentUser else { return false }
        return currentUser.email != nil && currentUser.phoneNumber == nil
    }
    
    /// Check if the current user can unlink their phone number
    var canUnlinkPhone: Bool {
        guard let currentUser = Auth.auth().currentUser else { return false }
        return currentUser.phoneNumber != nil && currentUser.email != nil
    }
    
    /// Send phone verification code for linking
    func sendPhoneVerificationCode(phoneNumber: String) async throws {
        // Format phone number with country code
        let formattedPhoneNumber = formatPhoneNumber(phoneNumber)
        
        // Check if this phone number is already associated with another account
        let isExistingAccount = await checkIfPhoneNumberExists(formattedPhoneNumber)
        
        if isExistingAccount {
            throw AuthError.custom("This phone number is already associated with another account. Please use a different phone number.")
        }
        
        // Use the existing verifyPhoneNumber method
        try await verifyPhoneNumber(formattedPhoneNumber)
    }
    
    /// Verify phone code for linking
    func verifyPhoneCode(verificationCode: String) async throws {
        try await linkPhoneNumber(verificationCode: verificationCode)
    }
    
    /// Unlink phone number (alias for existing method)
    func unlinkPhone() async throws {
        try await unlinkPhoneNumber()
    }
}

// MARK: - PhoneAuthProviderDelegate for reCAPTCHA
class PhoneAuthProviderDelegate: NSObject, AuthUIDelegate {
    
    private var currentViewController: UIViewController?
    
    func present(_ viewControllerToPresent: UIViewController, animated flag: Bool, completion: (() -> Void)?) {
        print("🔵 reCAPTCHA DEBUG: Presenting reCAPTCHA view controller")
        print("🔵 reCAPTCHA DEBUG: View controller type: \(type(of: viewControllerToPresent))")
        
        // Store reference to the view controller being presented
        currentViewController = viewControllerToPresent
        
        // Get the top view controller to present the reCAPTCHA view
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first,
              let rootViewController = window.rootViewController else {
            print("❌ reCAPTCHA ERROR: Could not find window or root view controller")
            completion?()
            return
        }
        
        // Find the topmost view controller
        var topViewController = rootViewController
        while let presentedViewController = topViewController.presentedViewController {
            topViewController = presentedViewController
        }
        
        print("🔵 reCAPTCHA DEBUG: Presenting to top view controller: \(type(of: topViewController))")
        
        // Ensure we're on the main thread
        DispatchQueue.main.async {
            // Present the reCAPTCHA view controller
            topViewController.present(viewControllerToPresent, animated: flag) {
                print("🔵 reCAPTCHA DEBUG: reCAPTCHA view controller presented successfully")
                completion?()
            }
        }
    }
    
    func dismiss(animated flag: Bool, completion: (() -> Void)?) {
        print("🔵 reCAPTCHA DEBUG: Dismissing reCAPTCHA view controller")
        
        // Get the top view controller to dismiss the reCAPTCHA view
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first,
              let rootViewController = window.rootViewController else {
            print("❌ reCAPTCHA ERROR: Could not find window or root view controller")
            completion?()
            return
        }
        
        // Find the topmost view controller
        var topViewController = rootViewController
        while let presentedViewController = topViewController.presentedViewController {
            topViewController = presentedViewController
        }
        
        print("🔵 reCAPTCHA DEBUG: Dismissing from top view controller: \(type(of: topViewController))")
        
        // Ensure we're on the main thread
        DispatchQueue.main.async {
            // Dismiss the reCAPTCHA view controller
            topViewController.dismiss(animated: flag) {
                print("🔵 reCAPTCHA DEBUG: reCAPTCHA view controller dismissed successfully")
                self.currentViewController = nil
                completion?()
            }
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