// audience: machine
// The pill body: draws the black flared-corner shape and hosts the two
// provider cells, with a tracking area per cell so the window controller can
// show/hide the right hover card.
import AppKit

protocol NotchContentViewDelegate: AnyObject {
    func notchContentView(_ view: NotchContentView, hoverChanged provider: ProviderGlyphKind?)
}

final class NotchContentView: NSView {
    weak var hoverDelegate: NotchContentViewDelegate?

    let claudeCell = ProviderCellView(frame: .zero)
    let codexCell = ProviderCellView(frame: .zero)

    private var claudeTrackingArea: NSTrackingArea?
    private var codexTrackingArea: NSTrackingArea?

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true

        claudeCell.kind = .claude
        codexCell.kind = .openai
        codexCell.isInstalled = false

        addSubview(claudeCell)
        addSubview(codexCell)
        layoutCells()
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        layoutCells()
        rebuildTrackingAreas()
    }

    private func layoutCells() {
        let cellWidth = VPLayout.pillDepth
        let cellHeight = VPLayout.cellHeight
        let x: CGFloat = 0
        let firstY = VPLayout.curl + VPLayout.paddingTop
        let secondY = firstY + cellHeight + VPLayout.cellGap
        claudeCell.frame = CGRect(x: x, y: firstY, width: cellWidth, height: cellHeight)
        codexCell.frame = CGRect(x: x, y: secondY, width: cellWidth, height: cellHeight)
    }

    private func rebuildTrackingAreas() {
        if let claudeTrackingArea { removeTrackingArea(claudeTrackingArea) }
        if let codexTrackingArea { removeTrackingArea(codexTrackingArea) }

        let claudeArea = NSTrackingArea(rect: claudeCell.frame,
                                         options: [.mouseEnteredAndExited, .activeAlways],
                                         owner: self, userInfo: ["provider": "claude"])
        let codexArea = NSTrackingArea(rect: codexCell.frame,
                                        options: [.mouseEnteredAndExited, .activeAlways],
                                        owner: self, userInfo: ["provider": "codex"])
        addTrackingArea(claudeArea)
        addTrackingArea(codexArea)
        claudeTrackingArea = claudeArea
        codexTrackingArea = codexArea
    }

    override func mouseEntered(with event: NSEvent) {
        guard let name = event.trackingArea?.userInfo?["provider"] as? String else { return }
        hoverDelegate?.notchContentView(self, hoverChanged: name == "claude" ? .claude : .openai)
    }

    override func mouseExited(with event: NSEvent) {
        hoverDelegate?.notchContentView(self, hoverChanged: nil)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        ctx.addPath(NotchPillPath.path(size: bounds.size, curl: VPLayout.curl, cornerRadius: VPLayout.cornerRadius))
        ctx.setFillColor(VPPalette.notchBlack.cgColor)
        ctx.fillPath()
        ctx.restoreGState()
    }
}
