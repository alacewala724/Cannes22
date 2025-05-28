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

    // Colours using custom assets
    static let tintGood     = Color("SentimentGood")
    static let tintNeutral  = Color("SentimentNeutral")
    static let tintBad      = Color("SentimentBad")
} 