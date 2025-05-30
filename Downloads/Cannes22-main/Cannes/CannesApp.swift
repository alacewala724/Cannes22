//
//  CannesApp.swift
//  Cannes
//
//  Created by Aamir Lacewala on 5/21/25.
//

import SwiftUI
import FirebaseCore
import FirebaseAuth

@main
struct CannesApp: App {
    @StateObject private var authService = AuthenticationService.shared
    @State private var showUsernamePrompt = false
    
    init() {
        // Configure Firebase before creating any Firebase-dependent services
        FirebaseApp.configure()
    }
    
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
