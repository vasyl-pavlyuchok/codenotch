// audience: machine
// The black hover card: title with glyph, then one row per LimitRow (label +
// reset time, a thin bar, "N % usado"). Height is computed from the row
// count so both the one-row Codex card and the three-row Claude card size
// correctly. Drawn in a flipped (y-down) NSView, matching the mockup's own
// top-to-bottom CSS layout.
import AppKit

final class TooltipCardView: NSView {
    var title: String = ""
    var glyph: ProviderGlyphKind = .claude
    var rows: [LimitRow] = [] { didSet { needsDisplay = true } }
    var emptyMessage: String?   // shown instead of rows, e.g. "Codex no está instalado"
    /// Y (in this view's own flipped coordinates) where the pointer triangle
    /// on the right edge should be centred — set to the hovered ring's centre.
    var pointerY: CGFloat?

    override var isFlipped: Bool { true }

    static func height(forRowCount count: Int, hasEmptyMessage: Bool) -> CGFloat {
        let top = VPLayout.cardPaddingTop
        let title = VPLayout.cardTitleHeight
        if hasEmptyMessage {
            return top + title + 8 + VPLayout.cardRowLabelHeight + VPLayout.cardPaddingBottom
        }
        let rowBlock = VPLayout.cardRowLabelHeight + VPLayout.cardBarGap + VPLayout.cardBarHeight
                     + VPLayout.cardBarGap + VPLayout.cardUsedHeight + VPLayout.cardRowSpacingTop
        return top + title + CGFloat(count) * rowBlock + VPLayout.cardPaddingBottom
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }

    /// How far the pointer triangle reaches past the card's own right edge.
    /// The view's frame is `cardWidth + Self.pointerReach` wide so the
    /// triangle has room to draw without being clipped.
    static let pointerReach: CGFloat = 14

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let cardBox = CGRect(x: 0, y: 0, width: VPLayout.cardWidth, height: bounds.height)

        // Card body.
        ctx.saveGState()
        ctx.addPath(NotchPillPath.roundedRect(size: cardBox.size, radius: VPLayout.cardCornerRadius))
        ctx.setFillColor(VPPalette.notchBlack.cgColor)
        ctx.fillPath()
        ctx.restoreGState()

        if let pointerY {
            let triangle = CGMutablePath()
            let tipX = cardBox.width + Self.pointerReach
            triangle.move(to: CGPoint(x: cardBox.width, y: pointerY - 9))
            triangle.addLine(to: CGPoint(x: tipX, y: pointerY))
            triangle.addLine(to: CGPoint(x: cardBox.width, y: pointerY + 9))
            triangle.closeSubpath()
            ctx.saveGState()
            ctx.addPath(triangle)
            ctx.setFillColor(VPPalette.notchBlack.cgColor)
            ctx.fillPath()
            ctx.restoreGState()
        }

        var y = VPLayout.cardPaddingTop
        let x = VPLayout.cardPaddingH
        let contentWidth = cardBox.width - 2 * x

        // Title: glyph + text.
        let glyphSize: CGFloat = 18
        let glyphRect = CGRect(x: x, y: y + (VPLayout.cardTitleHeight - glyphSize) / 2, width: glyphSize, height: glyphSize)
        ctx.saveGState()
        ctx.translateBy(x: glyphRect.minX, y: glyphRect.minY)
        ctx.addPath(glyph.path(fitted: glyphRect.size))
        ctx.setFillColor(VPPalette.textPrimary.cgColor)
        ctx.fillPath()
        ctx.restoreGState()

        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 16, weight: .medium),
            .foregroundColor: VPPalette.textPrimary
        ]
        let titleRect = CGRect(x: x + glyphSize + 8, y: y, width: contentWidth - glyphSize - 8, height: VPLayout.cardTitleHeight)
        title.draw(in: centeredVertically(titleRect, textHeight: 19), withAttributes: titleAttrs)
        y += VPLayout.cardTitleHeight

        if let emptyMessage {
            y += 8
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13),
                .foregroundColor: VPPalette.textSecondary
            ]
            emptyMessage.draw(in: CGRect(x: x, y: y, width: contentWidth, height: VPLayout.cardRowLabelHeight), withAttributes: attrs)
            return
        }

        for row in rows {
            y += VPLayout.cardRowSpacingTop

            let labelAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13),
                .foregroundColor: VPPalette.textPrimary
            ]
            let resetAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13),
                .foregroundColor: VPPalette.textSecondary
            ]
            row.label.draw(at: CGPoint(x: x, y: y), withAttributes: labelAttrs)
            if let resetsAt = row.resetsAt {
                let text = ResetTime.label(for: resetsAt)
                let size = text.size(withAttributes: resetAttrs)
                text.draw(at: CGPoint(x: x + contentWidth - size.width, y: y), withAttributes: resetAttrs)
            }
            y += VPLayout.cardRowLabelHeight + VPLayout.cardBarGap

            // Bar.
            let barRect = CGRect(x: x, y: y, width: contentWidth, height: VPLayout.cardBarHeight)
            ctx.saveGState()
            ctx.addPath(CGPath(roundedRect: barRect, cornerWidth: barRect.height / 2, cornerHeight: barRect.height / 2, transform: nil))
            ctx.setFillColor(VPPalette.barTrack.cgColor)
            ctx.fillPath()
            ctx.restoreGState()

            let fraction = max(0, min(1, row.usedPercent / 100))
            if fraction > 0 {
                let fillRect = CGRect(x: x, y: y, width: contentWidth * CGFloat(fraction), height: VPLayout.cardBarHeight)
                ctx.saveGState()
                ctx.addPath(CGPath(roundedRect: fillRect, cornerWidth: fillRect.height / 2, cornerHeight: fillRect.height / 2, transform: nil))
                ctx.setFillColor(row.band.color.cgColor)
                ctx.fillPath()
                ctx.restoreGState()
            }
            y += VPLayout.cardBarHeight + VPLayout.cardBarGap

            let usedText = "\(Int(row.usedPercent.rounded())) % usado"
            let usedAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13),
                .foregroundColor: VPPalette.textPrimary
            ]
            usedText.draw(at: CGPoint(x: x, y: y), withAttributes: usedAttrs)
            y += VPLayout.cardUsedHeight
        }
    }

    private func centeredVertically(_ rect: CGRect, textHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: rect.minY + (rect.height - textHeight) / 2, width: rect.width, height: textHeight)
    }
}
