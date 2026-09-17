// audience: machine
// Owns the two floating panels: the notch pill itself, pinned to the right
// screen edge, and the hover tooltip card that appears/disappears beside it.
// Both are borderless, non-activating NSPanels so they never take focus or
// show a Dock icon interaction, and both float above normal windows on every
// Space.
import AppKit

final class NotchWindowController: NSObject, NotchContentViewDelegate {
    private let panel: NSPanel
    private let contentView: NotchContentView
    private let tooltipPanel: NSPanel
    private let tooltipView: TooltipCardView

    private static let yOffsetDefaultsKey = "VPNotchYOffset"

    override init() {
        let size = CGSize(width: VPLayout.pillDepth, height: VPLayout.pillTotalHeight)
        contentView = NotchContentView(frame: CGRect(origin: .zero, size: size))

        panel = NSPanel(contentRect: CGRect(origin: .zero, size: size),
                         styleMask: [.borderless, .nonactivatingPanel],
                         backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.ignoresMouseEvents = false
        panel.isMovableByWindowBackground = false
        panel.contentView = contentView

        let tooltipSize = CGSize(width: VPLayout.cardWidth + TooltipCardView.pointerReach,
                                  height: TooltipCardView.height(forRowCount: 3, hasEmptyMessage: false))
        tooltipView = TooltipCardView(frame: CGRect(origin: .zero, size: tooltipSize))
        tooltipPanel = NSPanel(contentRect: CGRect(origin: .zero, size: tooltipSize),
                                styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
        tooltipPanel.isOpaque = false
        tooltipPanel.backgroundColor = .clear
        tooltipPanel.hasShadow = true
        tooltipPanel.level = .statusBar
        tooltipPanel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        tooltipPanel.ignoresMouseEvents = true
        tooltipPanel.contentView = tooltipView

        super.init()
        contentView.hoverDelegate = self
    }

    func show() {
        positionPanel()
        panel.orderFrontRegardless()
    }

    private func positionPanel() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let full = screen.frame
        let offset = UserDefaults.standard.double(forKey: Self.yOffsetDefaultsKey)
        let size = panel.frame.size
        let x = full.maxX - size.width
        var y = full.midY - size.height / 2 + offset
        y = min(max(y, full.minY), full.maxY - size.height)
        panel.setFrame(CGRect(x: x, y: y, width: size.width, height: size.height), display: true)
    }

    // MARK: Reading updates

    func updateClaude(headlinePercent: Double?, isWorking: Bool, isWaiting: Bool) {
        contentView.claudeCell.headlinePercent = headlinePercent
        contentView.claudeCell.isWorking = isWorking
        contentView.claudeCell.isWaiting = isWaiting
        contentView.claudeCell.needsDisplay = true
    }

    func updateCodex(headlinePercent: Double?, installed: Bool) {
        contentView.codexCell.isInstalled = installed
        contentView.codexCell.headlinePercent = headlinePercent
        contentView.codexCell.needsDisplay = true
    }

    private var claudeRows: [LimitRow] = []
    private var codexRows: [LimitRow] = []
    private var codexInstalled = false

    func setClaudeCardRows(_ rows: [LimitRow]) { claudeRows = rows }
    func setCodexCardRows(_ rows: [LimitRow], installed: Bool) {
        codexRows = rows
        codexInstalled = installed
    }

    // MARK: Hover

    func notchContentView(_ view: NotchContentView, hoverChanged provider: ProviderGlyphKind?) {
        guard let provider else {
            tooltipPanel.orderOut(nil)
            return
        }
        switch provider {
        case .claude:
            tooltipView.title = "Uso de Claude"
            tooltipView.glyph = .claude
            tooltipView.rows = claudeRows
            tooltipView.emptyMessage = claudeRows.isEmpty ? "Esperando la primera lectura…" : nil
            showTooltip(anchorCell: contentView.claudeCell, rowCount: claudeRows.count, hasEmptyMessage: claudeRows.isEmpty)
        case .openai:
            tooltipView.title = "Uso de Codex"
            tooltipView.glyph = .openai
            tooltipView.rows = codexRows
            tooltipView.emptyMessage = codexInstalled
                ? (codexRows.isEmpty ? "Esperando la primera lectura…" : nil)
                : "Codex no está instalado"
            showTooltip(anchorCell: contentView.codexCell, rowCount: codexRows.count,
                        hasEmptyMessage: !codexInstalled || codexRows.isEmpty)
        }
    }

    private func showTooltip(anchorCell: ProviderCellView, rowCount: Int, hasEmptyMessage: Bool) {
        let height = TooltipCardView.height(forRowCount: rowCount, hasEmptyMessage: hasEmptyMessage)
        let width = VPLayout.cardWidth + TooltipCardView.pointerReach
        tooltipView.frame = CGRect(x: 0, y: 0, width: width, height: height)

        // Anchor the pointer at the ring's vertical centre. `contentView` is
        // flipped (top-left origin) but the panel's own frame is in AppKit's
        // bottom-left screen space, so the cell's y offset from the panel's
        // top is what carries over.
        let panelScreenTop = panel.frame.maxY
        let pointerScreenY = panelScreenTop - (anchorCell.frame.minY + VPLayout.ringDiameter / 2)

        let screenX = panel.frame.minX - width - VPLayout.cardGapToNotch + TooltipCardView.pointerReach
        let screenY = pointerScreenY - height / 2
        tooltipPanel.setFrame(CGRect(x: screenX, y: screenY, width: width, height: height), display: false)
        tooltipView.pointerY = height / 2 // triangle points at the card's own vertical middle,
                                           // which the frame above already aligned with the ring.
        tooltipView.needsDisplay = true
        tooltipPanel.orderFrontRegardless()
    }
}
