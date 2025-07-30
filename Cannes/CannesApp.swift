//
//  CannesApp.swift
//  Cannes
//
//  Created by Aamir Lacewala on 5/21/25.
//

import SwiftUI
import Firebase
import FirebaseAuth
import FirebaseFirestore
import FirebaseMessaging
import UserNotifications

// MARK: - App Delegate for Firebase Push Notifications
class AppDelegate: NSObject, UIApplicationDelegate {
    // Static flag to track APNs token readiness
    static var isAPNsTokenSet = false
    
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        
        print("🚀 APP LAUNCH: Starting Firebase configuration...")
        
        // Enable Firebase debug logging for better visibility
        #if DEBUG
        FirebaseConfiguration.shared.setLoggerLevel(.debug)
        print("🔧 DEBUG: Firebase debug logging enabled")
        #endif
        
        // Configure Firebase
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
            print("✅ Firebase configured successfully")
        } else {
            print("ℹ️ Firebase already configured")
        }
        
        // Configure Firebase Auth settings for phone authentication
        // Remove the app verification disabled setting to allow proper APNs-based verification
        // Auth.auth().settings?.isAppVerificationDisabledForTesting = true  // REMOVED
        
        // Log Firebase project info
        if let app = FirebaseApp.app() {
            print("🔵 Firebase Project ID: \(app.options.projectID ?? "unknown")")
            print("🔵 Firebase Bundle ID: \(app.options.bundleID ?? "unknown")")
            print("🔵 Firebase GCM Sender ID: \(app.options.gcmSenderID ?? "unknown")")
        }
        
        // Request permission for push notifications (required for phone auth)
        UNUserNotificationCenter.current().delegate = self
        
        let authOptions: UNAuthorizationOptions = [.alert, .badge, .sound]
        UNUserNotificationCenter.current().requestAuthorization(
            options: authOptions,
            completionHandler: { granted, error in
                if let error = error {
                    print("❌ Push notification permission error: \(error)")
                } else {
                    print("✅ Push notification permission granted: \(granted)")
                    if granted {
                        DispatchQueue.main.async {
                            UIApplication.shared.registerForRemoteNotifications()
                            print("🔵 Registered for remote notifications after permission granted")
                        }
                    } else {
                        print("⚠️ WARNING: Push notifications denied. This may affect SMS delivery.")
                        print("⚠️ Phone authentication may not work without push notification permission.")
                    }
                }
            }
        )
        
        print("🔵 Registering for remote notifications...")
        application.registerForRemoteNotifications()
        
        return true
    }
    
    // MARK: - Push Notification Handling for Firebase Auth
    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        
        print("📱 Received remote notification: \(userInfo)")
        
        // Forward remote notifications to Firebase Auth
        if Auth.auth().canHandleNotification(userInfo) {
            print("✅ Firebase Auth handled the notification")
            completionHandler(.noData)
            return
        }
        
        print("ℹ️ Other remote notification processed")
        // Handle other remote notifications here
        completionHandler(.newData)
    }
    
    // MARK: - Silent Push Handling for Firebase Auth (iOS 10+)
    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any]) {
        
        print("📬 Received silent push notification: \(userInfo)")
        
        // Handle Firebase Auth silent push notifications
        if Auth.auth().canHandleNotification(userInfo) {
            print("✅ Firebase handled phone verification push")
            return
        }
        
        print("📬 Received other push: \(userInfo)")
    }
    
    // MARK: - URL Handling for reCAPTCHA (Required when swizzling is disabled)
    func application(_ application: UIApplication,
                     open url: URL,
                     options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
        
        print("🔗 URL opened: \(url)")
        
        // Handle Firebase Auth URL redirects (for reCAPTCHA)
        if Auth.auth().canHandle(url) {
            print("✅ Firebase Auth handled the URL")
            return true
        }
        
        // Handle other URL schemes here
        print("ℹ️ Other URL scheme processed")
        return false
    }
    
    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        print("✅ APNs device token received: \(tokenString)")
        
        // Enhanced APNs token handling
        #if DEBUG
        Auth.auth().setAPNSToken(deviceToken, type: .sandbox)
        print("🔧 DEBUG: Successfully set sandbox APNs token with Firebase Auth")
        #else
        Auth.auth().setAPNSToken(deviceToken, type: .prod)
        print("🚀 PRODUCTION: Successfully set production APNs token with Firebase Auth")
        #endif
        
        // Set the flag to indicate APNs token is ready
        AppDelegate.isAPNsTokenSet = true
        print("🔵 APNs token verification: Firebase Auth should now be ready for phone authentication")
        print("✅ APNs token flag set: Phone verification can now proceed")
        
        // Forward to FCM for push notifications
        Messaging.messaging().apnsToken = deviceToken
        print("📱 Forwarded APNs token to FCM")
    }
    
    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("❌ CRITICAL: Failed to register for remote notifications: \(error)")
        print("❌ This will prevent SMS authentication from working!")
        print("❌ Common causes:")
        print("   - Running on iOS Simulator (use real device)")
        print("   - Missing APNs certificate in Firebase Console")
        print("   - Incorrect provisioning profile")
        print("   - Network connectivity issues")
    }
}

// MARK: - UNUserNotificationCenter Delegate
extension AppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        
        let userInfo = notification.request.content.userInfo
        
        // Forward notification to Firebase Auth
        if Auth.auth().canHandleNotification(userInfo) {
            completionHandler([])
            return
        }
        
        // Handle other notifications
        completionHandler([.alert, .sound])
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        
        let userInfo = response.notification.request.content.userInfo
        
        // Forward notification to Firebase Auth
        if Auth.auth().canHandleNotification(userInfo) {
            completionHandler()
            return
        }
        
        // Handle other notifications
        completionHandler()
    }
}

@main
struct CannesApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var authService = AuthenticationService.shared
    @StateObject private var notificationService = NotificationService.shared
    @State private var showUsernamePrompt = false
    
    var body: some Scene {
        WindowGroup {
            if !authService.isReady {
                ProgressView("Loading...")
            } else if authService.isAuthenticated {
                if authService.isUsernameLoading {
                    // Show loading while username is being retrieved
                    ProgressView("Loading profile...")
                } else if authService.username == nil {
                    // Only show username creation if username loading is complete and username is nil
                    SetUsernameView()
                        .environmentObject(authService)
                } else {
                    ContentView()
                        .environmentObject(authService)
                        .environmentObject(notificationService)
                        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                            // Clear notification badges when app becomes active
                            clearNotificationBadges()
                        }
                }
            } else {
                AuthView()
                    .environmentObject(authService)
            }
        }
    }
    
    private func clearNotificationBadges() {
        // Clear the app badge count
        UIApplication.shared.applicationIconBadgeNumber = 0
        
        // Clear all delivered notifications from notification center
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        
        print("✅ Cleared notification badges and delivered notifications")
    }
}
