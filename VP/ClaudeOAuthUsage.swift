// audience: machine
// Reads the Claude Code OAuth token from the macOS login keychain
// ("Claude Code-credentials") and calls the same usage endpoint the upstream
// ClaudeOAuthProvider.swift does, to find the Fable weekly window (the third
// bar in the Claude card). Read-only: never refreshes, never writes, never
// logs the token value.
//
// Field shapes copied from Sources/Providers/ClaudeCredentials.swift
// (keychain JSON: claudeAiOauth.{accessToken, expiresAt, subscriptionType})
// and Sources/Providers/ClaudeOAuthProvider.swift (endpoint request/response,
// "limits" array with kind/percent/resetsAt/scope.model.displayName).
import Foundation
import Security

enum ClaudeOAuthUsage {
    private static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private static let minPollInterval: TimeInterval = 60

    private static var lastAttempt: Date?
    private static var backoffUntil: Date?
    private static var consecutive429: Int = 0

    /// True once so the "no Fable window in this response" case is logged
    /// only the first time it is seen, not on every 60s poll.
    private static var loggedMissingFable = false

    // MARK: Keychain

    private struct Credential {
        let accessToken: String
        let expiresAt: Date
    }

    /// Reads the newest "Claude Code-credentials" item for the current user.
    /// Never prompts (kSecUseAuthenticationUI = .fail) — a locked keychain or
    /// a missing item both just mean "no Fable row this run", not a crash.
    private static func readKeychainCredential() -> Credential? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: "Claude Code-credentials",
            kSecAttrAccount: NSUserName(),
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
            kSecUseAuthenticationUI: kSecUseAuthenticationUIFail
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            if status != errSecItemNotFound {
                FileHandle.standardError.write("codenotch-vp: keychain read for Fable usage failed, OSStatus \(status)\n".data(using: .utf8)!)
            }
            return nil
        }
        return decode(data)
    }

    private static func decode(_ data: Data) -> Credential? {
        struct Payload: Decodable {
            struct OAuth: Decodable {
                let accessToken: String
                let expiresAt: Double
            }
            let claudeAiOauth: OAuth
        }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data),
              !payload.claudeAiOauth.accessToken.isEmpty else { return nil }
        return Credential(
            accessToken: payload.claudeAiOauth.accessToken,
            expiresAt: Date(timeIntervalSince1970: payload.claudeAiOauth.expiresAt / 1000)
        )
    }

    // MARK: Endpoint

    private struct UsageResponse: Decodable {
        struct Scope: Decodable {
            struct Model: Decodable { let displayName: String? }
            let model: Model?
        }
        struct Limit: Decodable {
            let kind: String
            let percent: Double
            let resetsAt: Date?
            let scope: Scope?

            private enum CodingKeys: String, CodingKey { case kind, percent, resetsAt, scope }
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                kind = try c.decode(String.self, forKey: .kind)
                percent = try c.decode(Double.self, forKey: .percent)
                resetsAt = try c.decodeIfPresent(Date.self, forKey: .resetsAt)
                scope = try? c.decodeIfPresent(Scope.self, forKey: .scope)
            }
        }
        let limits: [Limit]?
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            if let date = withFraction.date(from: text) ?? plain.date(from: text) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "bad date \(text)"))
        }
        return decoder
    }()

    /// Poll for the Fable weekly row. Fires the completion on the main queue.
    /// Respects a 60s minimum interval and backs off on 429; every other
    /// failure (no keychain item, network error, no matching window) simply
    /// completes with nil so the caller hides the row instead of crashing.
    static func poll(completion: @escaping (LimitRow?) -> Void) {
        let now = Date()
        if let backoffUntil, backoffUntil > now { completion(nil); return }
        if let lastAttempt, now.timeIntervalSince(lastAttempt) < minPollInterval { completion(nil); return }
        lastAttempt = now

        guard let credential = readKeychainCredential(), !credential.accessToken.isEmpty else {
            completion(nil)
            return
        }

        var request = URLRequest(url: endpoint)
        request.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.timeoutInterval = 15

        URLSession.shared.dataTask(with: request) { data, response, error in
            defer {} // token/credential are local to this closure and go out of scope here
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0

            if status == 429 {
                consecutive429 += 1
                let floor: TimeInterval = 60, ceiling: TimeInterval = 15 * 60
                let wait = min(ceiling, floor * pow(2, Double(min(consecutive429, 4))))
                backoffUntil = Date().addingTimeInterval(wait)
                DispatchQueue.main.async { completion(nil) }
                return
            }
            consecutive429 = 0

            guard error == nil, (200..<300).contains(status), let data else {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            guard let payload = try? decoder.decode(UsageResponse.self, from: data),
                  let limits = payload.limits else {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            let fable = limits.first { limit in
                let name = limit.scope?.model?.displayName ?? ""
                return name.range(of: "fable", options: .caseInsensitive) != nil
                    || limit.kind.range(of: "fable", options: .caseInsensitive) != nil
            }

            guard let fable, let resetsAt = fable.resetsAt else {
                if !loggedMissingFable {
                    loggedMissingFable = true
                    FileHandle.standardError.write("codenotch-vp: no Fable window in /api/oauth/usage response — hiding the third bar\n".data(using: .utf8)!)
                }
                DispatchQueue.main.async { completion(nil) }
                return
            }

            let row = LimitRow(
                label: "Fable esta semana · límite propio",
                usedPercent: fable.percent,
                resetsAt: resetsAt
            )
            DispatchQueue.main.async { completion(row) }
        }.resume()
    }
}
