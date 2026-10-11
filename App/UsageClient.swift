import Foundation

/// Reads Claude Code's OAuth login from the Keychain and calls the same endpoint `/usage` uses.
enum UsageClient {
    enum FetchError: LocalizedError {
        case noCredentials, expired, http(Int), badData

        var errorDescription: String? {
            switch self {
            case .noCredentials: return "No Claude Code login found. Run `claude` and sign in."
            case .expired: return "Login token expired. Open Claude Code to refresh it."
            case .http(let code): return "Usage request failed (HTTP \(code))."
            case .badData: return "Unexpected response from the usage API."
            }
        }
    }

    static func fetch(pollMinutes: Int) async throws -> UsageSnapshot {
        let token = try readToken()
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 { throw FetchError.expired }
        guard status == 200 else { throw FetchError.http(status) }

        var snapshot = try parse(data)
        snapshot.pollMinutes = pollMinutes
        return snapshot
    }

    /// Shells out to /usr/bin/security, which Claude Code's keychain item already trusts,
    /// so no extra Keychain prompt is needed and the token never leaves this machine.
    private static func readToken() throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String
        else { throw FetchError.noCredentials }

        if let expiresAt = number(oauth["expiresAt"]), expiresAt / 1000 < Date().timeIntervalSince1970 {
            throw FetchError.expired
        }
        return token
    }

    static func parse(_ data: Data) throws -> UsageSnapshot {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw FetchError.badData
        }

        var limits: [UsageLimit] = []
        for (index, item) in (root["limits"] as? [[String: Any]] ?? []).enumerated() {
            let kind = item["kind"] as? String ?? "limit"
            let scope = item["scope"] as? [String: Any]
            let model = (scope?["model"] as? [String: Any])?["display_name"] as? String
            let (title, short) = titles(kind: kind, model: model)
            limits.append(UsageLimit(
                id: "\(kind)-\(model ?? "")-\(index)",
                title: title,
                shortTitle: short,
                percent: number(item["percent"]) ?? 0,
                resetsAt: date(item["resets_at"])
            ))
        }

        // Older response shape: per-window objects with a `utilization` field.
        if limits.isEmpty {
            let windows = [
                ("five_hour", "Current session", "Session"),
                ("seven_day", "Weekly · all models", "Week"),
                ("seven_day_opus", "Weekly · Opus", "Opus"),
                ("seven_day_sonnet", "Weekly · Sonnet", "Sonnet"),
            ]
            for (key, title, short) in windows {
                guard let window = root[key] as? [String: Any], let used = number(window["utilization"]) else { continue }
                limits.append(UsageLimit(id: key, title: title, shortTitle: short, percent: used,
                                         resetsAt: date(window["resets_at"])))
            }
        }
        guard !limits.isEmpty else { throw FetchError.badData }

        var snapshot = UsageSnapshot(limits: limits, fetchedAt: .now)
        if let spend = root["spend"] as? [String: Any], spend["enabled"] as? Bool == true,
           let limit = money(spend["limit"]), limit > 0 {
            snapshot.extraLimit = limit
            snapshot.extraUsed = money(spend["used"]) ?? 0
            snapshot.currency = (spend["limit"] as? [String: Any])?["currency"] as? String
        }
        return snapshot
    }

    private static func titles(kind: String, model: String?) -> (String, String) {
        switch kind {
        case "session": return ("Current session", "Session")
        case "weekly_all": return ("Weekly · all models", "Week")
        case "weekly_scoped": return ("Weekly · \(model ?? "scoped")", model ?? "Scoped")
        default:
            let name = kind.replacingOccurrences(of: "_", with: " ").capitalized
            return (name, name)
        }
    }

    private static func number(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue
    }

    private static func money(_ value: Any?) -> Double? {
        guard let dict = value as? [String: Any], let minor = number(dict["amount_minor"]) else { return nil }
        return minor / pow(10, number(dict["exponent"]) ?? 2)
    }

    private static func date(_ value: Any?) -> Date? {
        // The API sends microsecond precision, which ISO8601DateFormatter can't read; seconds are plenty.
        guard let string = value as? String else { return nil }
        let trimmed = string.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
        return ISO8601DateFormatter().date(from: trimmed)
    }
}
