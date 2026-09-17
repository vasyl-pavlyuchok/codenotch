// audience: machine
// Codex is not installed on this Mac, so this reads the same on-disk
// convention Sources/Providers/CodexProfile.swift and CodexCredentials.swift
// use (~/.codex/auth.json, tokens.{access_token,account_id}) and, only if
// that folder exists, calls the same endpoint CodexLocalProvider.swift does
// (chatgpt.com/backend-api/wham/usage, rate_limit.primary_window). If the
// folder is missing this never touches the network and reports
// `.notInstalled` so the ring can grey out honestly instead of inventing data.
import Foundation

enum CodexUsageReader {
    private static var home: String { NSHomeDirectory() }
    private static var codexDir: String { home + "/.codex" }
    private static var authPath: String { codexDir + "/auth.json" }

    static var isInstalled: Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: codexDir, isDirectory: &isDir) && isDir.boolValue
    }

    private struct Credential {
        let accessToken: String
        let accountID: String
    }

    private static func loadCredential() -> Credential? {
        struct Auth: Decodable {
            struct Tokens: Decodable {
                let access_token: String
                let account_id: String
            }
            let tokens: Tokens
        }
        guard let data = FileManager.default.contents(atPath: authPath),
              let auth = try? JSONDecoder().decode(Auth.self, from: data),
              !auth.tokens.access_token.isEmpty else { return nil }
        return Credential(accessToken: auth.tokens.access_token, accountID: auth.tokens.account_id)
    }

    private struct Window: Decodable {
        let used_percent: Double?
        let reset_at: Double?
        let reset_after_seconds: Double?
    }
    private struct RateLimit: Decodable {
        let primary_window: Window?
    }
    private struct Response: Decodable {
        let rate_limit: RateLimit?
    }

    /// Only ever called when `isInstalled` is true. Completes with nil on any
    /// failure (no credential, network error, bad response) so the caller can
    /// show "installed but unavailable" rather than crash.
    static func poll(completion: @escaping (LimitRow?) -> Void) {
        guard isInstalled, let credential = loadCredential() else { completion(nil); return }

        var request = URLRequest(
            url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 15
        )
        request.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(credential.accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: request) { data, response, _ in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(status), let data,
                  let payload = try? JSONDecoder().decode(Response.self, from: data),
                  let window = payload.rate_limit?.primary_window,
                  let pct = window.used_percent else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            let resetsAt = window.reset_at.map { Date(timeIntervalSince1970: $0) }
                ?? window.reset_after_seconds.map { Date().addingTimeInterval($0) }
            let row = LimitRow(label: "Sesión actual", usedPercent: pct, resetsAt: resetsAt)
            DispatchQueue.main.async { completion(row) }
        }.resume()
    }
}
