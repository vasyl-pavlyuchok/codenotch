// audience: machine
// Reads ~/.claude/state/usage-5h.json, the file Scripts/tb-usage-sink.js
// writes from the status line's own JSON. This is the primary, no-network
// source for Claude's "current session" (five_hour) and "this week, all
// models" (seven_day) rows.
//
// Frozen top-level keys, read 17-sep-2026 from the live file and from
// ~/.claude/bin/tb_usage_breaker.py's own docstring: used_percentage,
// resets_at, updated_at (all at the top level — this is the 5h reading, kept
// exactly as tb_usage_breaker.py expects it). seven_day is an additive
// sibling object the breaker does not read and must not be broken.
import Foundation

enum ClaudeUsageFile {
    struct Reading {
        let fiveHour: LimitRow?
        let sevenDay: LimitRow?
        let updatedAt: Date?
        let isStale: Bool
    }

    static var path: String {
        NSHomeDirectory() + "/.claude/state/usage-5h.json"
    }

    /// 30 minutes, the same staleness window `tb_usage_breaker.py` uses to
    /// decide a reading is too old to trust.
    static let staleAfter: TimeInterval = 30 * 60

    static func read(now: Date = Date()) -> Reading? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        func number(_ v: Any?) -> Double? {
            if let d = v as? Double { return d }
            if let i = v as? Int { return Double(i) }
            if let n = v as? NSNumber { return n.doubleValue }
            return nil
        }

        var fiveHour: LimitRow?
        var updated: Date?
        if let pct = number(obj["used_percentage"]) {
            let resets = number(obj["resets_at"]).map { Date(timeIntervalSince1970: $0) }
            fiveHour = LimitRow(label: "Sesión actual", usedPercent: pct, resetsAt: resets)
        }
        if let updatedAt = number(obj["updated_at"]) {
            updated = Date(timeIntervalSince1970: updatedAt)
        }

        var sevenDay: LimitRow?
        if let week = obj["seven_day"] as? [String: Any],
           let pct = number(week["used_percentage"]) {
            let resets = number(week["resets_at"]).map { Date(timeIntervalSince1970: $0) }
            sevenDay = LimitRow(label: "Esta semana · todos los modelos", usedPercent: pct, resetsAt: resets)
        }

        let stale: Bool
        if let updated {
            stale = now.timeIntervalSince(updated) > staleAfter
        } else {
            stale = true
        }

        guard fiveHour != nil || sevenDay != nil else { return nil }
        return Reading(fiveHour: fiveHour, sevenDay: sevenDay, updatedAt: updated, isStale: stale)
    }
}
