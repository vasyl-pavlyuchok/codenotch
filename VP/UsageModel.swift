// audience: machine
// The small shared data shapes every reader (session file, OAuth endpoint,
// Codex) produces, and the view layer consumes. Kept provider-agnostic on
// purpose: the ring and the card only ever draw a "LimitRow".
import Foundation

struct LimitRow: Equatable {
    let label: String
    /// 0...100
    let usedPercent: Double
    let resetsAt: Date?

    var band: VPUsageBand { VPUsageBand.band(forPercent: usedPercent) }
}

/// What the ring shows for one provider right now.
struct ProviderReading: Equatable {
    enum State: Equatable {
        case ok
        case notInstalled
        case unavailable   // installed but no reading yet (auth/network failure)
    }
    var state: State
    /// The ring's own headline percentage (Claude: five-hour session; Codex:
    /// the account's primary window).
    var headlinePercent: Double?
    /// All rows shown on the hover card, in display order.
    var cardRows: [LimitRow]
    var isWorking: Bool = false
    var isWaitingForUser: Bool = false

    static func notInstalled() -> ProviderReading {
        ProviderReading(state: .notInstalled, headlinePercent: nil, cardRows: [])
    }
    static func unavailable() -> ProviderReading {
        ProviderReading(state: .unavailable, headlinePercent: nil, cardRows: [])
    }
}
