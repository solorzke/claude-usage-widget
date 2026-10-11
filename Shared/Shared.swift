import Foundation
import SwiftUI

enum Shared {
    /// Team-ID-prefixed App Group so the app and the sandboxed widget share one container.
    /// Set at build time from Config/Signing.local.xcconfig.
    static let appGroup = Bundle.main.object(forInfoDictionaryKey: "ClaudeAppGroup") as? String ?? ""
    static let pollChoices = [1, 2, 5, 10, 15, 30, 60]
    static let accent = Color(red: 0.85, green: 0.47, blue: 0.34)

    static var snapshotURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent("usage.json")
    }

    static func color(for percent: Double) -> Color {
        switch percent {
        case 90...: return .red
        case 75..<90: return .orange
        default: return accent
        }
    }
}

struct UsageLimit: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var shortTitle: String
    var percent: Double
    var resetsAt: Date?

    /// Once a window's reset time passes, its usage is back to zero even before the next poll.
    func percent(at now: Date) -> Double {
        if let resetsAt, resetsAt <= now { return 0 }
        return percent
    }
}

struct UsageSnapshot: Codable {
    var limits: [UsageLimit]
    var extraUsed: Double?
    var extraLimit: Double?
    var currency: String?
    var fetchedAt: Date
    var pollMinutes: Int = 5
    var error: String?

    static func load() -> UsageSnapshot? {
        guard let url = Shared.snapshotURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(UsageSnapshot.self, from: data)
    }

    func save() {
        guard let url = Shared.snapshotURL, let data = try? JSONEncoder().encode(self) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    static let sample = UsageSnapshot(
        limits: [
            UsageLimit(id: "session", title: "Current session", shortTitle: "Session", percent: 42,
                       resetsAt: .now.addingTimeInterval(2.5 * 3600)),
            UsageLimit(id: "weekly", title: "Weekly · all models", shortTitle: "Week", percent: 63,
                       resetsAt: .now.addingTimeInterval(3 * 86400)),
        ],
        fetchedAt: .now
    )
}

struct UsageBar: View {
    let percent: Double
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(Shared.color(for: percent))
                    .frame(width: max(height, geo.size.width * min(percent, 100) / 100))
                    .opacity(percent > 0 ? 1 : 0)
            }
        }
        .frame(height: height)
    }
}

struct LimitRow: View {
    let limit: UsageLimit
    let now: Date
    var compact = false

    var body: some View {
        let pct = limit.percent(at: now)
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(compact ? limit.shortTitle : limit.title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("\(Int(pct.rounded()))%")
                    .font(.system(.callout, design: .rounded).weight(.semibold))
                    .monospacedDigit()
            }
            UsageBar(percent: pct)
            if !compact, let resetsAt = limit.resetsAt, resetsAt > now {
                Text("Resets in \(Text(resetsAt, style: .relative))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
    }
}

struct ExtraUsageRow: View {
    let used: Double
    let limit: Double
    let currency: String?

    var body: some View {
        let format = FloatingPointFormatStyle<Double>.Currency(code: currency ?? "USD")
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Extra usage").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                Spacer()
                Text("\(used.formatted(format)) / \(limit.formatted(format))")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
            }
            UsageBar(percent: limit > 0 ? used / limit * 100 : 0)
        }
    }
}
