// audience: machine
// Plain AppKit colours, matching Sources/DesignSystem/Palette.swift exactly
// (same hexes and alphas) but without the SwiftUI/dark-light adaptive
// machinery — this notch is always pure black, on every appearance, per spec.
import AppKit

enum VPPalette {
    static let notchBlack   = NSColor.black
    static let ringTrack    = NSColor.white.withAlphaComponent(0.188)
    static let barTrack     = NSColor.white.withAlphaComponent(0.176)

    static let ample        = NSColor(srgbHex: 0x00FF88)
    static let watch        = NSColor(srgbHex: 0xF2FF00)
    static let critical     = NSColor(srgbHex: 0xFF3F00)

    static let textPrimary   = NSColor.white
    static let textSecondary = NSColor(srgbHex: 0x808080)
}

extension NSColor {
    convenience init(srgbHex hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green:   CGFloat((hex >> 8) & 0xFF) / 255,
            blue:    CGFloat(hex & 0xFF) / 255,
            alpha:   alpha
        )
    }
}
