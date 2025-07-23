// DesignSystem.swift
// Centralised look-and-feel values.  Add more as needed.

import SwiftUI

// MARK: - Design Tokens
enum Design {
    static let gutter:   CGFloat = 16        // inset from the safe-area edge
    static let cardPad:  CGFloat = 16        // inner padding of every card
    static let cardRadius: CGFloat = 18
    
    // Adaptive card background for light/dark mode
    static func cardBG(for colorScheme: ColorScheme) -> Color {
        switch colorScheme {
        case .light:
            return Color(.systemGray6)  // More visible in light mode
        case .dark:
            return Color(.systemGray5)  // Subtle but visible in dark mode
        @unknown default:
            return Color(.systemGray5)
        }
    }
    
    // Adaptive shadows for light/dark mode
    static func cardShadow(for colorScheme: ColorScheme) -> Color {
        switch colorScheme {
        case .light:
            return Color.black.opacity(0.15)  // Dark shadow on light background
        case .dark:
            return Color.black.opacity(0.5)   // Stronger black shadow on dark background
        @unknown default:
            return Color.black.opacity(0.15)
        }
    }
}

// A one-liner you can attach to every section
struct CardStyle: ViewModifier {
    @Environment(\.colorScheme) var colorScheme
    
    func body(content: Content) -> some View {
        content
            .padding(Design.cardPad)
            .background(Design.cardBG(for: colorScheme))
            .clipShape(RoundedRectangle(cornerRadius: Design.cardRadius, style: .continuous))
            .shadow(color: Design.cardShadow(for: colorScheme),
                    radius: 8, x: 0, y: 4)
    }
}

// List item style with adaptive shadows
struct ListItemStyle: ViewModifier {
    @Environment(\.colorScheme) var colorScheme
    
    func body(content: Content) -> some View {
        content
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(Design.cardBG(for: colorScheme))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: Design.cardShadow(for: colorScheme),
                    radius: 4, x: 0, y: 2)
    }
}

extension View {
    func card() -> some View { modifier(CardStyle()) }
    func listItem() -> some View { modifier(ListItemStyle()) }
}

// MARK: - Adaptive Sentiment Colors
extension Color {
    static func adaptiveSentiment(for score: Double, colorScheme: ColorScheme) -> Color {
        switch score {
        case 6.9...10.0:
            return colorScheme == .light ? Color(red: 34/255, green: 139/255, blue: 34/255) : .green
        case 4.0..<6.9:
            return .gray
        case 0.0..<4.0:
            return .red
        default:
            return .gray
        }
    }
    
    static func adaptiveGolden(for colorScheme: ColorScheme) -> Color {
        return colorScheme == .light ? Color(red: 239/255, green: 191/255, blue: 4/255) : .yellow
    }
} 