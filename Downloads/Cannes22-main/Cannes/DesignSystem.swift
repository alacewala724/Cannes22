// DesignSystem.swift
// Centralised look-and-feel values.  Add more as needed.

import SwiftUI

enum DS {
    // Spacing and corner radii
    static let corner: CGFloat = 12                // all cards / buttons
    static let gap:    CGFloat = 12                // default vertical gap
    static let hPad:   CGFloat = 16                // leading/trailing padding

    // Fonts
    static func font(_ style: Font.TextStyle,
                     weight: Font.Weight = .regular) -> Font {
        .system(style, design: .rounded).weight(weight)
    }

    // Colours (add Asset-catalog "light + dark" variants for these)
    static let tintGood     = Color("SentimentGood")     // green variants
    static let tintNeutral  = Color("SentimentNeutral")  // gray variants
    static let tintBad      = Color("SentimentBad")      // red variants
} 