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
        // Debug: Check if fonts are available
        let availableFonts = UIFont.familyNames
        let hasPlayfairDisplay = availableFonts.contains("Playfair Display")
        
        #if DEBUG
        print("Available font families: \(availableFonts)")
        print("Has Playfair Display: \(hasPlayfairDisplay)")
        if hasPlayfairDisplay {
            print("Playfair Display fonts: \(UIFont.fontNames(forFamilyName: "Playfair Display"))")
        }
        #endif
        
        if hasPlayfairDisplay {
            switch weight {
            case .bold:
                return .custom("PlayfairDisplay-Bold", size: fontSize(for: style))
            case .medium:
                return .custom("PlayfairDisplay-Medium", size: fontSize(for: style))
            default:
                return .custom("PlayfairDisplay-Regular", size: fontSize(for: style))
            }
        } else {
            // Fallback to system serif font
            print("Playfair Display not available, using system serif font")
            return .system(style, design: .serif).weight(weight)
        }
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