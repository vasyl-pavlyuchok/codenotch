// audience: machine
// One provider's ring + glyph + percentage. Plain Core Graphics drawing in a
// flipped (top-left origin, y-down) NSView, so the arc math below reads the
// same way the mockup's SVG does: angle 0 = 3 o'clock, increasing angle
// sweeps clockwise, top of the circle is -90deg.
import AppKit

final class ProviderCellView: NSView {
    var kind: ProviderGlyphKind = .claude
    /// nil = not installed (Codex today): draw a grey ring and "—".
    var headlinePercent: Double?
    var isWorking = false { didSet { updateAnimationTimer() } }
    var isWaiting = false { didSet { updateAnimationTimer() } }
    var isInstalled = true

    private var spinAngle: CGFloat = 0
    private var pulsePhase: CGFloat = 0
    private var animationTimer: Timer?

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }

    deinit { animationTimer?.invalidate() }

    private func updateAnimationTimer() {
        let needsTimer = isWorking || isWaiting
        if needsTimer, animationTimer == nil {
            animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
                self?.tick()
            }
        } else if !needsTimer, let timer = animationTimer {
            timer.invalidate()
            animationTimer = nil
            spinAngle = 0
            pulsePhase = 0
            needsDisplay = true
        }
    }

    private func tick() {
        // Spin: one full turn every 1.6s, matching the mockup's `.spin` keyframe.
        if isWorking {
            spinAngle += (2 * .pi) / (1.6 * 30)
            if spinAngle > 2 * .pi { spinAngle -= 2 * .pi }
        }
        // Pulse: 1.4s ease-in-out cycle between full opacity and .35, like `.pulse`.
        if isWaiting {
            pulsePhase += (2 * .pi) / (1.4 * 30)
            if pulsePhase > 2 * .pi { pulsePhase -= 2 * .pi }
        }
        needsDisplay = true
    }

    private var pulseAlpha: CGFloat {
        // (cos+1)/2 goes 1 -> 0 -> 1 across a cycle; scaled to land on .35 at
        // the trough, matching the CSS keyframe's midpoint value.
        let t = (cos(pulsePhase) + 1) / 2
        return 0.35 + t * 0.65
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let ringRect = CGRect(x: (bounds.width - VPLayout.ringDiameter) / 2, y: 0,
                               width: VPLayout.ringDiameter, height: VPLayout.ringDiameter)
        let center = CGPoint(x: ringRect.midX, y: ringRect.midY)
        let radius = VPLayout.ringRadius

        // Track
        ctx.saveGState()
        let trackColor: NSColor
        let trackAlpha: CGFloat
        if isWaiting {
            trackColor = VPPalette.watch
            trackAlpha = pulseAlpha
        } else {
            trackColor = VPPalette.ringTrack
            trackAlpha = 1
        }
        ctx.setStrokeColor(trackColor.withAlphaComponent(trackColor.alphaComponent * trackAlpha).cgColor)
        ctx.setLineWidth(VPLayout.ringStroke)
        ctx.addArc(center: center, radius: radius, startAngle: 0, endAngle: 2 * .pi, clockwise: false)
        ctx.strokePath()
        ctx.restoreGState()

        // Progress arc, from the top, clockwise, by headlinePercent. Rotates
        // continuously while working (spinAngle), independent of the pct sweep.
        if let pct = headlinePercent {
            let fraction = max(0, min(1, pct / 100))
            let band = VPUsageBand.band(forPercent: pct)
            let color = isInstalled ? band.color : NSColor.white.withAlphaComponent(0.3)
            let start = -CGFloat.pi / 2 + spinAngle
            let end = start + 2 * .pi * CGFloat(fraction)
            ctx.saveGState()
            ctx.setStrokeColor(color.cgColor)
            ctx.setLineWidth(VPLayout.ringStroke)
            ctx.setLineCap(.round)
            ctx.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: false)
            ctx.strokePath()
            ctx.restoreGState()
        }

        // Glyph, centred in the ring.
        let glyphRect = CGRect(x: center.x - VPLayout.glyphSize / 2, y: center.y - VPLayout.glyphSize / 2,
                                width: VPLayout.glyphSize, height: VPLayout.glyphSize)
        let glyphColor = isInstalled ? VPPalette.textPrimary : VPPalette.textPrimary.withAlphaComponent(0.4)
        ctx.saveGState()
        ctx.translateBy(x: glyphRect.minX, y: glyphRect.minY)
        ctx.addPath(kind.path(fitted: glyphRect.size))
        ctx.setFillColor(glyphColor.cgColor)
        ctx.fillPath()
        ctx.restoreGState()

        // Percentage / placeholder label, below the ring.
        let text = isInstalled ? (headlinePercent.map { "\(Int($0.rounded()))%" } ?? "—") : "—"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: VPLayout.labelFontSize, weight: .medium),
            .foregroundColor: VPPalette.textPrimary
        ]
        let size = text.size(withAttributes: attrs)
        let labelRect = CGRect(x: (bounds.width - size.width) / 2,
                                y: VPLayout.ringDiameter + VPLayout.ringToLabelGap,
                                width: size.width, height: VPLayout.labelHeight)
        text.draw(in: labelRect, withAttributes: attrs)
    }
}
