//
//  CannesApp.swift
//  Cannes
//
//  Created by Aamir Lacewala on 5/21/25.
//

import SwiftUI
import FirebaseCore

@main
struct CannesApp: App {
    @StateObject private var authService = FirebaseAuthService()
    
    init() {
        FirebaseApp.configure()
    }
    
    var body: some Scene {
        WindowGroup {
            if authService.isAuthenticated {
                ContentView()
                    .environmentObject(authService)
            } else {
                AuthView()
                    .environmentObject(authService)
            }
        }
    }
}
