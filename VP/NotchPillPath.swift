// audience: machine
// The pill shape: rounded on the far (left) side, flush and concave-flared
// where it meets the screen's right edge — a straight port of the geometry
// in Sources/Notch/SideNotchShape.swift's canonicalPath(for: .right, joining:
// nil), rewritten against CGMutablePath for a plain (non-SwiftUI) NSView.
//
// Ported 1:1 into a y-down, top-left-origin coordinate space (this app's
// views all set `isFlipped = true`), which is the same convention SwiftUI's
// Path/CGPath use, so the addArc angles and clockwise flags below are the
// same values the original file uses — no sign-flipping required.
import CoreGraphics

enum NotchPillPath {
    /// `size` is the whole shape's bounding box, `size.width` = the pill's
    /// depth away from the bezel, `size.height` = its full length including
    /// the two flares. The bezel is the right edge (`size.width`).
    static func path(size: CGSize, curl: CGFloat, cornerRadius: CGFloat) -> CGPath {
        let rect = CGRect(origin: .zero, size: size)
        let wanted = max(0, min(cornerRadius, rect.width / 2))
        let curl = max(0, min(curl, rect.height / 2, rect.width - wanted))
        let corner = max(0, min(wanted, (rect.height - 2 * curl) / 2))
        let bodyTop = rect.minY + curl
        let bodyBottom = rect.maxY - curl

        let path = CGMutablePath()
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        if curl > 0 {
            path.addArc(center: CGPoint(x: rect.maxX - curl, y: rect.minY),
                        radius: curl,
                        startAngle: 0, endAngle: .pi / 2,
                        clockwise: false)
        }
        path.addLine(to: CGPoint(x: rect.minX + corner, y: bodyTop))
        if corner > 0 {
            path.addArc(center: CGPoint(x: rect.minX + corner, y: bodyTop + corner),
                        radius: corner,
                        startAngle: 3 * .pi / 2, endAngle: .pi,
                        clockwise: true)
        }
        path.addLine(to: CGPoint(x: rect.minX, y: bodyBottom - corner))
        if corner > 0 {
            path.addArc(center: CGPoint(x: rect.minX + corner, y: bodyBottom - corner),
                        radius: corner,
                        startAngle: .pi, endAngle: .pi / 2,
                        clockwise: true)
        }
        path.addLine(to: CGPoint(x: rect.maxX - curl, y: bodyBottom))
        if curl > 0 {
            path.addArc(center: CGPoint(x: rect.maxX - curl, y: rect.maxY),
                        radius: curl,
                        startAngle: 3 * .pi / 2, endAngle: 2 * .pi,
                        clockwise: false)
        }
        path.closeSubpath()
        return path
    }

    /// A plain rounded-rect card path (the tooltip), radius on all four
    /// corners.
    static func roundedRect(size: CGSize, radius: CGFloat) -> CGPath {
        CGPath(roundedRect: CGRect(origin: .zero, size: size), cornerWidth: radius, cornerHeight: radius, transform: nil)
    }
}
