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
    
    // MARK: - FCM Token Management
    
    func refreshFCMToken() {
        print("📱 ===== REFRESHING FCM TOKEN =====")
        print("📱 Timestamp: \(Date())")
        print("📱 ===============================")
        
        Messaging.messaging().token { [weak self] token, error in
            if let error = error {
                print("❌ Error fetching FCM token: \(error)")
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
            .setData(tokenData) { error in
                if let error = error {
                    print("❌ Error saving FCM token: \(error)")
                    print("🔍 DEBUG: Error details: \(error.localizedDescription)")
                } else {
                    print("✅ FCM token saved to Firestore")
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
                } else {
                    print("❌ Failed to send notification to \(userId)")
                    print("📱 Error: \(resultData["message"] as? String ?? "unknown error")")
                }
            }
            
        } catch {
            print("❌ Error sending notification: \(error)")
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
                } else {
                    print("❌ Failed to send notifications for movie: \(movieTitle)")
                }
            }
            
        } catch {
            print("❌ Error checking followers for movie: \(error)")
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
                } else {
                    print("❌ Failed to send follow notification to \(userId)")
                    print("📱 Error: \(resultData["message"] as? String ?? "unknown error")")
                }
            }
            
        } catch {
            print("❌ Error sending follow notification: \(error)")
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
                } else {
                    print("❌ Failed to send comment notifications for movie: \(movieTitle)")
                }
            }
            
        } catch {
            print("❌ Error checking followers for movie comment: \(error)")
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