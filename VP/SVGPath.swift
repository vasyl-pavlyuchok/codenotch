// audience: machine
// Minimal SVG path ("d" attribute) parser, just enough for the two glyph
// paths this app draws (Claude and OpenAI symbol marks). Supports the
// commands those two paths actually use: M/m, L/l, H/h, V/v, C/c, Z/z.
// Not a general SVG engine — no arcs, no quadratic/smooth curves, because
// the source glyphs never need them.
import CoreGraphics

private struct SVGPathTokenizer {
    private let chars: [Character]
    private var idx = 0
    private var pushedBack: String?

    init(_ d: String) { chars = Array(d) }

    mutating func pushBack(_ token: String) {
        pushedBack = token
    }

    mutating func nextToken() -> String? {
        if let p = pushedBack {
            pushedBack = nil
            return p
        }
        skipSeparators()
        guard idx < chars.count else { return nil }
        let c = chars[idx]
        if c.isLetter {
            idx += 1
            return String(c)
        }
        return readNumber()
    }

    private mutating func skipSeparators() {
        while idx < chars.count {
            let c = chars[idx]
            if c == " " || c == "," || c == "\n" || c == "\t" || c == "\r" {
                idx += 1
            } else {
                break
            }
        }
    }

    private mutating func readNumber() -> String? {
        var s = ""
        if idx < chars.count, chars[idx] == "+" || chars[idx] == "-" {
            s.append(chars[idx]); idx += 1
        }
        var sawDot = false
        while idx < chars.count {
            let c = chars[idx]
            if c.isNumber {
                s.append(c); idx += 1
            } else if c == "." && !sawDot {
                sawDot = true
                s.append(c); idx += 1
            } else {
                break
            }
        }
        return s.isEmpty ? nil : s
    }
}

enum SVGPath {
    /// Parses a "d" attribute string into a CGPath, in the SVG's own
    /// (y-down) coordinate space. The caller is responsible for scaling and
    /// translating into whatever target rect it needs.
    static func cgPath(_ d: String) -> CGPath {
        let path = CGMutablePath()
        var tok = SVGPathTokenizer(d)
        var current = CGPoint.zero
        var subpathStart = CGPoint.zero
        var cmd: Character?

        func nextNumber() -> CGFloat? {
            guard let t = tok.nextToken() else { return nil }
            if let c = t.first, t.count == 1, c.isLetter {
                // Not a number — this is the next command; push it back so
                // the outer loop reads it as such and bail on this group.
                tok.pushBack(t)
                return nil
            }
            return Double(t).map { CGFloat($0) }
        }

        while let token = tok.nextToken() {
            if let c = token.first, token.count == 1, c.isLetter {
                cmd = c
            } else {
                tok.pushBack(token)
            }
            guard let command = cmd else { break }

            switch command {
            case "M", "m":
                guard let x = nextNumber(), let y = nextNumber() else { return path }
                let pt = command == "m" ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
                path.move(to: pt)
                current = pt
                subpathStart = pt
                // Extra coordinate pairs after the first are implicit lineto.
                cmd = command == "m" ? "l" : "L"
            case "L", "l":
                guard let x = nextNumber(), let y = nextNumber() else { return path }
                let pt = command == "l" ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
                path.addLine(to: pt)
                current = pt
            case "H", "h":
                guard let x = nextNumber() else { return path }
                let pt = command == "h" ? CGPoint(x: current.x + x, y: current.y) : CGPoint(x: x, y: current.y)
                path.addLine(to: pt)
                current = pt
            case "V", "v":
                guard let y = nextNumber() else { return path }
                let pt = command == "v" ? CGPoint(x: current.x, y: current.y + y) : CGPoint(x: current.x, y: y)
                path.addLine(to: pt)
                current = pt
            case "C", "c":
                guard let x1 = nextNumber(), let y1 = nextNumber(),
                      let x2 = nextNumber(), let y2 = nextNumber(),
                      let x = nextNumber(), let y = nextNumber() else { return path }
                let c1 = command == "c" ? CGPoint(x: current.x + x1, y: current.y + y1) : CGPoint(x: x1, y: y1)
                let c2 = command == "c" ? CGPoint(x: current.x + x2, y: current.y + y2) : CGPoint(x: x2, y: y2)
                let pt = command == "c" ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
                path.addCurve(to: pt, control1: c1, control2: c2)
                current = pt
            case "Z", "z":
                path.closeSubpath()
                current = subpathStart
            default:
                return path
            }
        }
        return path
    }

    /// Returns a copy of `path` scaled and centred to fit `size`, preserving
    /// aspect ratio, given the path's own coordinate space is `viewBox`.
    static func fitted(_ path: CGPath, viewBox: CGSize, into size: CGSize) -> CGPath {
        let scale = min(size.width / viewBox.width, size.height / viewBox.height)
        let scaledWidth = viewBox.width * scale
        let scaledHeight = viewBox.height * scale
        let dx = (size.width - scaledWidth) / 2
        let dy = (size.height - scaledHeight) / 2
        var transform = CGAffineTransform(translationX: dx, y: dy)
            .scaledBy(x: scale, y: scale)
        return path.copy(using: &transform) ?? path
    }
}
