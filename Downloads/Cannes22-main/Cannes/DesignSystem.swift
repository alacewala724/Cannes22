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
    
    // Playfair Display for headers and titles
    static func playfairDisplay(_ style: Font.TextStyle,
                               weight: Font.Weight = .regular) -> Font {
        let fontName: String
        switch weight {
        case .bold:
            fontName = "PlayfairDisplay-Bold"
        case .medium, .semibold:
            fontName = "PlayfairDisplay-Medium"
        default:
            fontName = "PlayfairDisplay-Regular"
        }
        
        return .custom(fontName, size: fontSize(for: style))
    }
    
    // Helper function to get font size for different text styles
    private static func fontSize(for style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle:
            return 34
        case .title:
            return 28
        case .title2:
            return 22
        case .title3:
            return 20
        case .headline:
            return 17
        case .body:
            return 17
        case .callout:
            return 16
        case .subheadline:
            return 15
        case .footnote:
            return 13
        case .caption:
            return 12
        case .caption2:
            return 11
        @unknown default:
            return 17
        }
    }

    // Colours (add Asset-catalog "light + dark" variants for these)
    static let tintGood     = Color("SentimentGood")     // green variants
    static let tintNeutral  = Color("SentimentNeutral")  // gray variants
    static let tintBad      = Color("SentimentBad")      // red variants
} 