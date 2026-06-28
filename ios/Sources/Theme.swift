import SwiftUI
import UIKit

/// Colours ported from the web client's CSS variables (OLED black + mint neon).
enum Theme {
    static let bg = Color.black
    static let surface = Color(red: 0.051, green: 0.051, blue: 0.063)
    static let surface2 = Color(red: 0.039, green: 0.039, blue: 0.051)
    static let accent = Color(red: 0.0, green: 0.898, blue: 0.627)
    static let accentFaint = Color(red: 0.0, green: 0.898, blue: 0.627).opacity(0.12)
    static let red = Color(red: 1.0, green: 0.42, blue: 0.42)
    static let text = Color(red: 0.961, green: 0.961, blue: 0.969)
    static let textDim = Color(red: 0.541, green: 0.541, blue: 0.576)
    static let line = Color.white.opacity(0.09)
    static let lineSoft = Color.white.opacity(0.07)
}

enum Haptics {
    static func light() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }
}
