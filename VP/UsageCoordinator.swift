// audience: machine
// Ties the readers to the window controller: polls each source on its own
// interval and pushes whatever it gets to the rings and the hover card. No
// view logic lives here, only scheduling and merging.
import Foundation

final class UsageCoordinator {
    private let window: NotchWindowController

    private var fableRow: LimitRow?
    private var claudeFileReading: ClaudeUsageFile.Reading?

    private var codexRow: LimitRow?
    private var codexInstalled = false

    init(window: NotchWindowController) {
        self.window = window
    }

    func start() {
        refreshClaudeFile()
        refreshSessionState()
        refreshCodex()
        pollFable()

        Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            self?.refreshClaudeFile()
        }
        Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.refreshSessionState()
        }
        Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.refreshCodex()
        }
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.pollFable()
        }
    }

    private func refreshClaudeFile() {
        claudeFileReading = ClaudeUsageFile.read()
        pushClaudeUpdate()
    }

    private func refreshSessionState() {
        let flags = SessionState.currentClaudeFlags()
        window.updateClaude(
            headlinePercent: claudeFileReading?.fiveHour?.usedPercent,
            isWorking: flags.isWorking,
            isWaiting: flags.isWaiting
        )
    }

    private func pollFable() {
        ClaudeOAuthUsage.poll { [weak self] row in
            self?.fableRow = row
            self?.pushClaudeUpdate()
        }
    }

    private func pushClaudeUpdate() {
        var rows: [LimitRow] = []
        if let fiveHour = claudeFileReading?.fiveHour { rows.append(fiveHour) }
        if let sevenDay = claudeFileReading?.sevenDay { rows.append(sevenDay) }
        if let fableRow { rows.append(fableRow) }
        window.setClaudeCardRows(rows)

        let flags = SessionState.currentClaudeFlags()
        window.updateClaude(
            headlinePercent: claudeFileReading?.fiveHour?.usedPercent,
            isWorking: flags.isWorking,
            isWaiting: flags.isWaiting
        )
    }

    private func refreshCodex() {
        codexInstalled = CodexUsageReader.isInstalled
        guard codexInstalled else {
            codexRow = nil
            window.updateCodex(headlinePercent: nil, installed: false)
            window.setCodexCardRows([], installed: false)
            return
        }
        CodexUsageReader.poll { [weak self] row in
            guard let self else { return }
            self.codexRow = row
            self.window.updateCodex(headlinePercent: row?.usedPercent, installed: true)
            self.window.setCodexCardRows(row.map { [$0] } ?? [], installed: true)
        }
    }
}
