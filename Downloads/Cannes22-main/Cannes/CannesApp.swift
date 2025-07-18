//
//  CannesApp.swift
//  Cannes
//
//  Created by Aamir Lacewala on 5/21/25.
//

import SwiftUI
import FirebaseCore
import FirebaseAuth
import UIKit
import UserNotifications

// MARK: - App Delegate for Firebase Push Notifications
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        
        print("🚀 APP LAUNCH: Starting Firebase configuration...")
        
        // Configure Firebase
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
            print("✅ Firebase configured successfully")
        } else {
            print("ℹ️ Firebase already configured")
        }
        
        // Configure Firebase Auth settings for phone authentication
        #if DEBUG
        // For testing - disable app verification (use only during development)
        Auth.auth().settings?.isAppVerificationDisabledForTesting = true
        print("🔧 DEBUG: App verification disabled for testing")
        #endif
        
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
                    if !granted {
                        print("⚠️ WARNING: Push notifications denied. This may affect SMS delivery.")
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
    
    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        print("✅ APNs device token received: \(tokenString)")
        
        // Forward device token to Firebase Auth
        #if DEBUG
        Auth.auth().setAPNSToken(deviceToken, type: .sandbox)
        print("🔧 DEBUG: Using sandbox APNs token")
        #else
        Auth.auth().setAPNSToken(deviceToken, type: .prod)
        print("🚀 PRODUCTION: Using production APNs token")
        #endif
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
    @State private var showUsernamePrompt = false
    
    var body: some Scene {
        WindowGroup {
            if !authService.isReady {
                ProgressView("Loading...")
            } else if authService.isAuthenticated {
                if authService.username == nil {
                    SetUsernameView()
                        .environmentObject(authService)
                } else {
                    ContentView()
                        .environmentObject(authService)
                }
            } else {
                AuthView()
                    .environmentObject(authService)
            }
        }
    }
}
