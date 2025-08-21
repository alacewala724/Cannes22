import Foundation
import Firebase
import FirebaseAuth
import FirebaseMessaging
import FirebaseFunctions
import UserNotifications
import FirebaseFirestore

class NotificationService: NSObject, ObservableObject {
    static let shared = NotificationService()
    private let db = Firestore.firestore()
    
    @Published var fcmToken: String?
    @Published var isTokenRefreshed = false
    @Published var notificationPermissionGranted = false
    
    // Simple toggle for testing - set to false to disable all notifications
    @Published var notificationsEnabled = true
    
    // Error handling state
    @Published var lastError: String?
    @Published var showError = false
    @Published var isOffline = false
    @Published var retryCount = 0
    @Published var lastErrorTime: Date?
    
    // Notification rate limiting
    @Published var notificationCounts: [String: Int] = [:] // Track notifications per user
    @Published var notificationTimestamps: [String: [Date]] = [:] // Track timestamps per user
    private let maxNotificationsPerHour = 5 // Maximum notifications per hour per user
    private let maxNotificationsPerDay = 20 // Maximum notifications per day per user
    private let maxNotificationsPerWeek = 50 // Maximum notifications per week per user
    
    private override init() {
        super.init()
        setupMessaging()
    }
    
    private func setupMessaging() {
        Messaging.messaging().delegate = self
        
        // Request permission for notifications
        UNUserNotificationCenter.current().delegate = self
        
        let authOptions: UNAuthorizationOptions = [.alert, .badge, .sound]
        UNUserNotificationCenter.current().requestAuthorization(
            options: authOptions,
            completionHandler: { [weak self] granted, error in
                DispatchQueue.main.async {
                    self?.notificationPermissionGranted = granted
                }
                if let error = error {
                    print("❌ Notification permission error: \(error)")
                    self?.handleError(error, context: "notificationPermission")
                } else {
                    print("📱 ===== NOTIFICATION PERMISSION STATUS =====")
                    print("📱 Permission granted: \(granted)")
                    print("📱 Timestamp: \(Date())")
                    print("📱 ==========================================")
                }
            }
        )
        
        // Register for remote notifications
        UIApplication.shared.registerForRemoteNotifications()
    }
    
    // MARK: - Error Handling
    
    private func handleError(_ error: Error, context: String) {
        let errorMessage = getErrorMessage(for: error, context: context)
        
        DispatchQueue.main.async {
            self.lastError = errorMessage
            self.showError = true
            self.lastErrorTime = Date()
            
            // Check if it's a network error
            if self.isNetworkError(error) {
                self.isOffline = true
            }
            
            print("❌ NotificationService Error [\(context)]: \(error.localizedDescription)")
        }
    }
    
    private func getErrorMessage(for error: Error, context: String) -> String {
        if isNetworkError(error) {
            return "No internet connection. Please check your network and try again."
        } else if isAuthError(error) {
            return "Authentication error. Please sign in again."
        } else if isRateLimitError(error) {
            return "Too many requests. Please wait a moment and try again."
        } else if isServerError(error) {
            return "Server error. Please try again later."
        } else {
            return "Failed to send notification. Please try again."
        }
    }
    
    private func isNetworkError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && 
               (nsError.code == NSURLErrorNotConnectedToInternet ||
                nsError.code == NSURLErrorNetworkConnectionLost ||
                nsError.code == NSURLErrorTimedOut)
    }
    
    private func isAuthError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == "FirebaseAuthErrorDomain" ||
               nsError.code == 401
    }
    
    private func isRateLimitError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.code == 429
    }
    
    private func isServerError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.code >= 500 && nsError.code < 600
    }
    
    private func shouldRetry() -> Bool {
        guard let lastError = lastErrorTime else { return true }
        let timeSinceLastError = Date().timeIntervalSince(lastError)
        
        // Allow retry if more than 30 seconds have passed or if retry count is low
        return timeSinceLastError > 30 || retryCount < 3
    }
    
    private func resetErrorState() {
        lastError = nil
        showError = false
        retryCount = 0
        lastErrorTime = nil
        isOffline = false
    }
    
    // MARK: - Rate Limiting
    
    private func shouldSendNotification(to userId: String, type: String) -> Bool {
        let now = Date()
        let key = "\(userId)_\(type)"
        
        // Get existing timestamps for this user and notification type
        var timestamps = notificationTimestamps[key] ?? []
        
        // Clean up old timestamps (older than 1 week)
        let oneWeekAgo = now.addingTimeInterval(-7 * 24 * 60 * 60)
        timestamps = timestamps.filter { $0 > oneWeekAgo }
        
        // Check hourly limit
        let oneHourAgo = now.addingTimeInterval(-60 * 60)
        let hourlyCount = timestamps.filter { $0 > oneHourAgo }.count
        if hourlyCount >= maxNotificationsPerHour {
            print("📱 Rate limit: Hourly limit reached for user \(userId) (\(hourlyCount)/\(maxNotificationsPerHour))")
            return false
        }
        
        // Check daily limit
        let oneDayAgo = now.addingTimeInterval(-24 * 60 * 60)
        let dailyCount = timestamps.filter { $0 > oneDayAgo }.count
        if dailyCount >= maxNotificationsPerDay {
            print("📱 Rate limit: Daily limit reached for user \(userId) (\(dailyCount)/\(maxNotificationsPerDay))")
            return false
        }
        
        // Check weekly limit
        let weeklyCount = timestamps.count
        if weeklyCount >= maxNotificationsPerWeek {
            print("📱 Rate limit: Weekly limit reached for user \(userId) (\(weeklyCount)/\(maxNotificationsPerWeek))")
            return false
        }
        
        // Log current status
        print("📱 Rate limit: Status for user \(userId) (\(type)) - Hourly: \(hourlyCount)/\(maxNotificationsPerHour), Daily: \(dailyCount)/\(maxNotificationsPerDay), Weekly: \(weeklyCount)/\(maxNotificationsPerWeek)")
        
        return true
    }
    
    private func trackNotificationSent(to userId: String, type: String) {
        let now = Date()
        let key = "\(userId)_\(type)"
        
        // Update on main thread to avoid publishing changes from background threads
        DispatchQueue.main.async {
            // Add current timestamp
            var timestamps = self.notificationTimestamps[key] ?? []
            timestamps.append(now)
            self.notificationTimestamps[key] = timestamps
            
            // Update count
            let currentCount = self.notificationCounts[key] ?? 0
            self.notificationCounts[key] = currentCount + 1
            
            print("📱 Rate limit: Tracked notification to user \(userId) (type: \(type), total: \(currentCount + 1))")
        }
    }
    
    private func getRateLimitStatus(for userId: String, type: String) -> (hourly: Int, daily: Int, weekly: Int) {
        let now = Date()
        let key = "\(userId)_\(type)"
        let timestamps = notificationTimestamps[key] ?? []
        
        let oneHourAgo = now.addingTimeInterval(-60 * 60)
        let oneDayAgo = now.addingTimeInterval(-24 * 60 * 60)
        let oneWeekAgo = now.addingTimeInterval(-7 * 24 * 60 * 60)
        
        let hourlyCount = timestamps.filter { $0 > oneHourAgo }.count
        let dailyCount = timestamps.filter { $0 > oneDayAgo }.count
        let weeklyCount = timestamps.filter { $0 > oneWeekAgo }.count
        
        return (hourly: hourlyCount, daily: dailyCount, weekly: weeklyCount)
    }
    
    // MARK: - Public Rate Limit Status
    
    func getRateLimitStatus(for userId: String) -> [String: (hourly: Int, daily: Int, weekly: Int)] {
        let types = ["movie_rating", "follow", "movie_comment"]
        var status: [String: (hourly: Int, daily: Int, weekly: Int)] = [:]
        
        for type in types {
            status[type] = getRateLimitStatus(for: userId, type: type)
        }
        
        return status
    }
    
    func clearRateLimitData(for userId: String? = nil) {
        // Update on main thread to avoid publishing changes from background threads
        DispatchQueue.main.async {
            if let userId = userId {
                // Clear data for specific user
                let keysToRemove = self.notificationTimestamps.keys.filter { $0.hasPrefix("\(userId)_") }
                for key in keysToRemove {
                    self.notificationTimestamps.removeValue(forKey: key)
                    self.notificationCounts.removeValue(forKey: key)
                }
                print("📱 Rate limit: Cleared data for user \(userId)")
            } else {
                // Clear all data
                self.notificationTimestamps.removeAll()
                self.notificationCounts.removeAll()
                print("📱 Rate limit: Cleared all rate limit data")
            }
        }
    }
    
    // MARK: - FCM Token Management
    
    func refreshFCMToken() {
        print("📱 ===== REFRESHING FCM TOKEN =====")
        print("📱 Timestamp: \(Date())")
        print("📱 ===============================")
        
        Messaging.messaging().token { [weak self] token, error in
            if let error = error {
                print("❌ Error fetching FCM token: \(error)")
                self?.handleError(error, context: "refreshFCMToken")
                return
            }
            
            if let token = token {
                DispatchQueue.main.async {
                    self?.fcmToken = token
                    self?.isTokenRefreshed = true
                }
                print("📱 ===== FCM TOKEN REFRESHED =====")
                print("📱 Token: \(token)")
                print("📱 Token length: \(token.count) characters")
                print("📱 Timestamp: \(Date())")
                print("📱 ==============================")
                
                // Save token to Firestore for the current user
                self?.saveFCMTokenToFirestore(token: token)
            }
        }
    }
    
    private func saveFCMTokenToFirestore(token: String) {
        guard let currentUser = Auth.auth().currentUser else {
            print("❌ No authenticated user to save FCM token")
            handleError(NSError(domain: "NotificationService", code: 5, userInfo: [NSLocalizedDescriptionKey: "No authenticated user"]), context: "saveFCMTokenToFirestore")
            return
        }
        
        print("🔍 DEBUG: Current user ID: \(currentUser.uid)")
        print("🔍 DEBUG: User is authenticated: \(currentUser.uid != nil)")
        
        let tokenData: [String: Any] = [
            "fcmToken": token,
            "updatedAt": FieldValue.serverTimestamp(),
            "platform": "ios"
        ]
        
        print("🔍 DEBUG: Attempting to save FCM token to path: users/\(currentUser.uid)/tokens/fcm")
        
        // First, ensure the user document exists
        let userDocRef = db.collection("users").document(currentUser.uid)
        
        userDocRef.getDocument { [weak self] document, error in
            if let error = error {
                print("❌ Error checking user document: \(error)")
                self?.handleError(error, context: "saveFCMTokenToFirestore")
                return
            }
            
            if document?.exists != true {
                // Create user document if it doesn't exist
                print("🔍 DEBUG: User document doesn't exist, creating it...")
                userDocRef.setData([
                    "uid": currentUser.uid,
                    "createdAt": FieldValue.serverTimestamp()
                ]) { error in
                    if let error = error {
                        print("❌ Error creating user document: \(error)")
                        self?.handleError(error, context: "saveFCMTokenToFirestore")
                        return
                    }
                    print("✅ User document created")
                    self?.saveTokenToUserDocument(token: token, tokenData: tokenData, userId: currentUser.uid)
                }
            } else {
                print("✅ User document exists")
                self?.saveTokenToUserDocument(token: token, tokenData: tokenData, userId: currentUser.uid)
            }
        }
    }
    
    private func saveTokenToUserDocument(token: String, tokenData: [String: Any], userId: String) {
        db.collection("users")
            .document(userId)
            .collection("tokens")
            .document("fcm")
            .setData(tokenData) { [weak self] error in
                if let error = error {
                    print("❌ Error saving FCM token: \(error)")
                    print("🔍 DEBUG: Error details: \(error.localizedDescription)")
                    self?.handleError(error, context: "saveTokenToUserDocument")
                } else {
                    print("✅ FCM token saved to Firestore")
                    self?.resetErrorState()
                }
            }
    }
    
    // MARK: - Notification Sending
    
    func sendMovieRatingNotification(
        to userId: String,
        from username: String,
        movieTitle: String,
        score: Double,
        tmdbId: Int
    ) async {
        // Check if notifications are enabled
        guard notificationsEnabled else {
            print("🔕 Notifications disabled - skipping notification to \(userId)")
            return
        }
        
        // Check rate limiting
        guard shouldSendNotification(to: userId, type: "movie_rating") else {
            print("📱 Rate limit: Skipping movie rating notification to \(userId)")
            return
        }
        
        print("📱 ===== DIRECT MOVIE RATING NOTIFICATION =====")
        print("📱 To User ID: \(userId)")
        print("📱 From Username: \(username)")
        print("📱 Movie: \(movieTitle)")
        print("📱 Score: \(score)")
        print("📱 TMDB ID: \(tmdbId)")
        print("📱 Timestamp: \(Date())")
        print("📱 ============================================")
        
        do {
            // Call Firebase Function to send notification
            let functions = Functions.functions()
            
            let data: [String: Any] = [
                "targetUserId": userId,
                "username": username,
                "movieTitle": movieTitle,
                "score": score,
                "tmdbId": tmdbId
            ]
            
            print("📱 Calling Firebase function with data: \(data)")
            
            let result = try await functions.httpsCallable("sendMovieRatingNotification").call(data)
            
            print("📱 Firebase function result: \(result.data ?? "nil")")
            
            if let resultData = result.data as? [String: Any],
               let success = resultData["success"] as? Bool {
                if success {
                    print("✅ Successfully sent notification to \(userId)")
                    print("📱 Message ID: \(resultData["messageId"] as? String ?? "unknown")")
                    resetErrorState()
                    
                    // Track successful notification
                    trackNotificationSent(to: userId, type: "movie_rating")
                } else {
                    let errorMessage = resultData["message"] as? String ?? "Unknown error"
                    print("❌ Failed to send notification to \(userId)")
                    print("📱 Error: \(errorMessage)")
                    handleError(NSError(domain: "NotificationService", code: 1, userInfo: [NSLocalizedDescriptionKey: errorMessage]), context: "sendMovieRatingNotification")
                }
            }
            
        } catch {
            handleError(error, context: "sendMovieRatingNotification")
        }
    }
    
    // MARK: - Check for Common Movies
    
    func checkAndNotifyFollowersForMovie(
        movieTitle: String,
        score: Double,
        tmdbId: Int
    ) async {
        // Check if notifications are enabled
        guard notificationsEnabled else {
            print("🔕 Notifications disabled - skipping follower notifications for \(movieTitle)")
            return
        }
        
        print("📱 ===== MOVIE RATING NOTIFICATION TRIGGERED =====")
        print("📱 Movie: \(movieTitle)")
        print("📱 Score: \(score)")
        print("📱 TMDB ID: \(tmdbId)")
        print("📱 Timestamp: \(Date())")
        print("📱 ==============================================")
        
        do {
            // Call Firebase Function to check and notify followers
            let functions = Functions.functions()
            
            let data: [String: Any] = [
                "movieTitle": movieTitle,
                "score": score,
                "tmdbId": tmdbId
            ]
            
            print("📱 Calling Firebase function with data: \(data)")
            
            let result = try await functions.httpsCallable("checkAndNotifyFollowersForMovie").call(data)
            
            print("📱 Firebase function result: \(result.data ?? "nil")")
            
            if let resultData = result.data as? [String: Any],
               let success = resultData["success"] as? Bool,
               let notificationsSent = resultData["notificationsSent"] as? Int {
                if success {
                    print("✅ Successfully sent \(notificationsSent) notifications for movie: \(movieTitle)")
                    print("📱 Notification recipients: \(resultData["recipients"] as? [String] ?? [])")
                    resetErrorState()
                    
                    // Track successful notifications for each recipient
                    if let recipients = resultData["recipients"] as? [String] {
                        for recipient in recipients {
                            trackNotificationSent(to: recipient, type: "movie_rating")
                        }
                    }
                } else {
                    let errorMessage = resultData["message"] as? String ?? "Unknown error"
                    print("❌ Failed to send notifications for movie: \(movieTitle)")
                    print("📱 Error: \(errorMessage)")
                    handleError(NSError(domain: "NotificationService", code: 2, userInfo: [NSLocalizedDescriptionKey: errorMessage]), context: "checkAndNotifyFollowersForMovie")
                }
            }
            
        } catch {
            handleError(error, context: "checkAndNotifyFollowersForMovie")
        }
    }
    
    // MARK: - Follow Notifications
    
    func sendFollowNotification(
        to userId: String,
        from username: String
    ) async {
        // Check if notifications are enabled
        guard notificationsEnabled else {
            print("🔕 Notifications disabled - skipping follow notification to \(userId)")
            return
        }
        
        // Check rate limiting
        guard shouldSendNotification(to: userId, type: "follow") else {
            print("📱 Rate limit: Skipping follow notification to \(userId)")
            return
        }
        
        print("📱 ===== FOLLOW NOTIFICATION TRIGGERED =====")
        print("📱 To User ID: \(userId)")
        print("📱 From Username: \(username)")
        print("📱 Timestamp: \(Date())")
        print("📱 ========================================")
        
        do {
            // Call Firebase Function to send follow notification
            let functions = Functions.functions()
            
            let data: [String: Any] = [
                "targetUserId": userId,
                "username": username
            ]
            
            print("📱 Calling Firebase function with data: \(data)")
            
            let result = try await functions.httpsCallable("sendFollowNotification").call(data)
            
            print("📱 Firebase function result: \(result.data ?? "nil")")
            
            if let resultData = result.data as? [String: Any],
               let success = resultData["success"] as? Bool {
                if success {
                    print("✅ Successfully sent follow notification to \(userId)")
                    print("📱 Message ID: \(resultData["messageId"] as? String ?? "unknown")")
                    resetErrorState()
                    
                    // Track successful notification
                    trackNotificationSent(to: userId, type: "follow")
                } else {
                    let errorMessage = resultData["message"] as? String ?? "Unknown error"
                    print("❌ Failed to send follow notification to \(userId)")
                    print("📱 Error: \(errorMessage)")
                    handleError(NSError(domain: "NotificationService", code: 3, userInfo: [NSLocalizedDescriptionKey: errorMessage]), context: "sendFollowNotification")
                }
            }
            
        } catch {
            handleError(error, context: "sendFollowNotification")
        }
    }
    
    // MARK: - Movie Comment Notifications
    
    func checkAndNotifyFollowersForMovieComment(
        movieTitle: String,
        comment: String,
        tmdbId: Int
    ) async {
        // Check if notifications are enabled
        guard notificationsEnabled else {
            print("🔕 Notifications disabled - skipping comment notifications for \(movieTitle)")
            return
        }
        
        print("📱 ===== MOVIE COMMENT NOTIFICATION TRIGGERED =====")
        print("📱 Movie: \(movieTitle)")
        print("📱 Comment: \(comment)")
        print("📱 TMDB ID: \(tmdbId)")
        print("📱 Timestamp: \(Date())")
        print("📱 ================================================")
        
        do {
            // Call Firebase Function to check and notify followers about movie comment
            let functions = Functions.functions()
            
            let data: [String: Any] = [
                "movieTitle": movieTitle,
                "comment": comment,
                "tmdbId": tmdbId
            ]
            
            print("📱 Calling Firebase function with data: \(data)")
            
            let result = try await functions.httpsCallable("checkAndNotifyFollowersForMovieComment").call(data)
            
            print("📱 Firebase function result: \(result.data ?? "nil")")
            
            if let resultData = result.data as? [String: Any],
               let success = resultData["success"] as? Bool,
               let notificationsSent = resultData["notificationsSent"] as? Int {
                if success {
                    print("✅ Successfully sent \(notificationsSent) comment notifications for movie: \(movieTitle)")
                    print("📱 Notification recipients: \(resultData["recipients"] as? [String] ?? [])")
                    resetErrorState()
                    
                    // Track successful notifications for each recipient
                    if let recipients = resultData["recipients"] as? [String] {
                        for recipient in recipients {
                            trackNotificationSent(to: recipient, type: "movie_comment")
                        }
                    }
                } else {
                    let errorMessage = resultData["message"] as? String ?? "Unknown error"
                    print("❌ Failed to send comment notifications for movie: \(movieTitle)")
                    print("📱 Error: \(errorMessage)")
                    handleError(NSError(domain: "NotificationService", code: 4, userInfo: [NSLocalizedDescriptionKey: errorMessage]), context: "checkAndNotifyFollowersForMovieComment")
                }
            }
            
        } catch {
            handleError(error, context: "checkAndNotifyFollowersForMovieComment")
        }
    }
    
    // MARK: - Badge Management
    
    func clearAllNotifications() {
        // Clear app badge
        UIApplication.shared.applicationIconBadgeNumber = 0
        
        // Remove all delivered notifications
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        
        // Remove all pending notifications
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        
        print("✅ Cleared all notifications and badges")
    }
    
    func setBadgeCount(_ count: Int) {
        UIApplication.shared.applicationIconBadgeNumber = count
        print("📱 Set badge count to: \(count)")
    }
    
    func incrementBadgeCount() {
        let currentCount = UIApplication.shared.applicationIconBadgeNumber
        UIApplication.shared.applicationIconBadgeNumber = currentCount + 1
        print("📱 Incremented badge count to: \(currentCount + 1)")
    }
}

// MARK: - MessagingDelegate
extension NotificationService: MessagingDelegate {
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        print("📱 FCM registration token: \(fcmToken ?? "nil")")
        
        if let token = fcmToken {
            DispatchQueue.main.async {
                self.fcmToken = token
                self.isTokenRefreshed = true
            }
            
            // Save token to Firestore
            saveFCMTokenToFirestore(token: token)
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate
extension NotificationService: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let userInfo = notification.request.content.userInfo
        
        // Handle the notification data
        if let type = userInfo["type"] as? String {
            switch type {
            case "movie_rating":
                print("📱 Received movie rating notification: \(userInfo)")
                // You can handle the notification data here
                // For example, navigate to the movie detail view
            case "movie_comment":
                print("📱 Received movie comment notification: \(userInfo)")
                // You can handle the notification data here
                // For example, navigate to the movie detail view or takes section
            case "user_followed":
                print("📱 Received follow notification: \(userInfo)")
                // You can handle the notification data here
                // For example, navigate to the user's profile
            default:
                print("📱 Received unknown notification type: \(type)")
            }
        }
        
        // Show the notification when app is in foreground, but don't increment badge
        completionHandler([.alert, .sound])
    }
    
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        
        // Handle notification tap
        if let type = userInfo["type"] as? String {
            switch type {
            case "movie_rating":
                print("📱 User tapped movie rating notification: \(userInfo)")
                // You can handle navigation here
                // For example, navigate to the movie detail view
            case "movie_comment":
                print("📱 User tapped movie comment notification: \(userInfo)")
                // You can handle navigation here
                // For example, navigate to the movie detail view or takes section
            case "user_followed":
                print("📱 User tapped follow notification: \(userInfo)")
                // You can handle navigation here
                // For example, navigate to the user's profile
            default:
                print("📱 User tapped unknown notification type: \(type)")
            }
        }
        
        // Clear the badge when user interacts with notification
        clearAllNotifications()
        
        completionHandler()
    }
} 