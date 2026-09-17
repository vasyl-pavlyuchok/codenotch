// audience: machine
// Every pixel constant the notch pill and cells use, quoted from the
// mockup's CSS (mockup-pestana-claude-codex.html) rather than invented.
import CoreGraphics

enum VPLayout {
    // Pill body
    static let pillDepth: CGFloat = 92        // .notch width
    static let curl: CGFloat = 22             // ::before/::after 22x22
    static let cornerRadius: CGFloat = 24     // border-radius 24px on the far side
    static let paddingTop: CGFloat = 26
    static let paddingBottom: CGFloat = 22
    static let cellGap: CGFloat = 26          // .notch gap between .prov cells

    // A provider cell
    static let ringDiameter: CGFloat = 56     // .ring 56x56
    static let ringStroke: CGFloat = 4
    static let ringRadius: CGFloat = 24       // circle r=24 inside a 56x56 box
    static let glyphSize: CGFloat = 22        // .ring .glyph svg 22x22
    static let ringToLabelGap: CGFloat = 10   // .prov gap:10
    static let labelFontSize: CGFloat = 16
    static let labelHeight: CGFloat = 20

    static var cellHeight: CGFloat { ringDiameter + ringToLabelGap + labelHeight }
    static var pillContentHeight: CGFloat { paddingTop + cellHeight * 2 + cellGap + paddingBottom }
    static var pillTotalHeight: CGFloat { pillContentHeight + curl * 2 }

    // Tooltip card
    static let cardWidth: CGFloat = 300
    static let cardCornerRadius: CGFloat = 18
    static let cardPaddingH: CGFloat = 16
    static let cardPaddingTop: CGFloat = 14
    static let cardPaddingBottom: CGFloat = 16
    static let cardGapToNotch: CGFloat = 24   // clears the pointer triangle
    static let cardTitleHeight: CGFloat = 24
    static let cardRowLabelHeight: CGFloat = 17
    static let cardBarHeight: CGFloat = 6
    static let cardBarGap: CGFloat = 6
    static let cardUsedHeight: CGFloat = 17
    static let cardRowSpacingTop: CGFloat = 8  // .lr margin-top on non-first rows
    static let cardSectionGap: CGFloat = 6
}
