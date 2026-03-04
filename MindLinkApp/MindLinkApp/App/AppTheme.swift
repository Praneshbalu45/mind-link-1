import SwiftUI

// MARK: - App Theme (single accent color used everywhere)

enum AppTheme {
    /// One accent color for the entire app — change this to retheme everything
    static let accent     = Color(red: 0.22, green: 0.45, blue: 1.0)   // vivid blue
    static let accentUI   = UIColor(red: 0.22, green: 0.45, blue: 1.0, alpha: 1)

    /// Semantic shades derived from the single accent
    static let accentDim  = accent.opacity(0.15)
    static let accentMid  = accent.opacity(0.45)
    static let accentFull = accent

    /// Status colors (still needed for pass/fail rows)
    static let good   = Color(.systemGreen)
    static let warn   = Color(.systemOrange)
    static let danger = Color(.systemRed)
    static let neutral = Color(.systemGray)

    /// Card background
    static let cardBG = Color(.secondarySystemBackground)
    static let fill   = Color(.systemFill)
}
