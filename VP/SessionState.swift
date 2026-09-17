// audience: machine
// Deliberately simple "working / waiting" signal for Claude's ring, per the
// task spec (item 4): working = a session file touched in the last 90s, or
// the domain flag touched in the last 60s; waiting = a flag file exists. No
// parsing of session content — just mtimes and existence, on purpose.
import Foundation

enum SessionState {
    struct Flags: Equatable {
        var isWorking: Bool
        var isWaiting: Bool
    }

    private static var home: String { NSHomeDirectory() }

    static func currentClaudeFlags(now: Date = Date()) -> Flags {
        Flags(isWorking: isClaudeWorking(now: now), isWaiting: isClaudeWaiting())
    }

    private static func isClaudeWorking(now: Date) -> Bool {
        if mtimeWithin(path: home + "/.claude/state/tb-domain-flag.json", seconds: 60, now: now) {
            return true
        }
        return anySessionFileFresh(seconds: 90, now: now)
    }

    private static func isClaudeWaiting() -> Bool {
        FileManager.default.fileExists(atPath: home + "/.claude/state/needs-user.flag")
    }

    private static func anySessionFileFresh(seconds: TimeInterval, now: Date) -> Bool {
        let dir = home + "/.claude/sessions"
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return false }
        for name in names where name.hasSuffix(".json") {
            if mtimeWithin(path: dir + "/" + name, seconds: seconds, now: now) { return true }
        }
        return false
    }

    private static func mtimeWithin(path: String, seconds: TimeInterval, now: Date) -> Bool {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let mtime = attrs[.modificationDate] as? Date else { return false }
        return now.timeIntervalSince(mtime) < seconds
    }
}
