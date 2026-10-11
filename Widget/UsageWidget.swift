import SwiftUI
import WidgetKit

@main
struct ClaudeUsageWidgets: WidgetBundle {
    var body: some Widget { ClaudeUsageWidget() }
}

struct ClaudeUsageWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ClaudeUsageWidget", provider: Provider()) { entry in
            UsageWidgetView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Claude Usage")
        .description("Your Claude plan limits at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct UsageEntry: TimelineEntry {
    let date: Date
    let snapshot: UsageSnapshot?
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> UsageEntry {
        UsageEntry(date: .now, snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        completion(UsageEntry(date: .now, snapshot: UsageSnapshot.load() ?? (context.isPreview ? .sample : nil)))
    }

    /// The menu bar app does the fetching and pokes us after each check; this timeline is the
    /// fallback, plus extra entries at each reset time so a window drops to 0% on schedule.
    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        let snapshot = UsageSnapshot.load()
        let now = Date.now
        let resets = (snapshot?.limits.compactMap(\.resetsAt) ?? []).filter { $0 > now }.sorted().prefix(4)
        let entries = [UsageEntry(date: now, snapshot: snapshot)]
            + resets.map { UsageEntry(date: $0, snapshot: snapshot) }
        let next = now.addingTimeInterval(Double(snapshot?.pollMinutes ?? 5) * 60)
        completion(Timeline(entries: entries, policy: .after(next)))
    }
}

struct UsageWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: UsageEntry

    var body: some View {
        if let snapshot = entry.snapshot, !snapshot.limits.isEmpty {
            switch family {
            case .systemSmall: SmallView(snapshot: snapshot, now: entry.date)
            case .systemLarge: LargeView(snapshot: snapshot, now: entry.date)
            default: MediumView(snapshot: snapshot, now: entry.date)
            }
        } else {
            VStack(spacing: 6) {
                Image(systemName: "sparkle").font(.title2).foregroundStyle(Shared.accent)
                Text(entry.snapshot?.error ?? "Open Claude Usage to start tracking.")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct Header: View {
    let snapshot: UsageSnapshot
    var showUpdated = true

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "sparkle").foregroundStyle(Shared.accent)
            Text("Claude").font(.caption.weight(.semibold))
            Spacer(minLength: 4)
            if snapshot.error != nil {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            } else if showUpdated {
                Text(snapshot.fetchedAt, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .font(.caption)
    }
}

private struct Ring: View {
    let percent: Double
    var lineWidth: CGFloat = 9

    var body: some View {
        ZStack {
            Circle().stroke(.quaternary, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(percent, 100) / 100)
                .stroke(Shared.color(for: percent), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int(percent.rounded()))%")
                .font(.system(.title3, design: .rounded).weight(.bold))
                .monospacedDigit()
        }
    }
}

private struct SmallView: View {
    let snapshot: UsageSnapshot
    let now: Date

    var body: some View {
        let primary = snapshot.limits[0]
        VStack(alignment: .leading, spacing: 8) {
            Header(snapshot: snapshot, showUpdated: false)
            HStack {
                Spacer()
                VStack(spacing: 4) {
                    Ring(percent: primary.percent(at: now)).frame(width: 64, height: 64)
                    Text(primary.shortTitle).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
            }
            if snapshot.limits.count > 1 {
                LimitRow(limit: snapshot.limits[1], now: now, compact: true)
            }
        }
    }
}

private struct MediumView: View {
    let snapshot: UsageSnapshot
    let now: Date

    var body: some View {
        let primary = snapshot.limits[0]
        VStack(alignment: .leading, spacing: 10) {
            Header(snapshot: snapshot)
            HStack(spacing: 16) {
                VStack(spacing: 4) {
                    Ring(percent: primary.percent(at: now)).frame(width: 72, height: 72)
                    Text(primary.shortTitle).font(.caption2).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 10) {
                    if let resetsAt = primary.resetsAt, resetsAt > now {
                        Text("\(primary.shortTitle) resets in \(Text(resetsAt, style: .relative))")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                    ForEach(snapshot.limits.dropFirst().prefix(2)) {
                        LimitRow(limit: $0, now: now, compact: true)
                    }
                }
            }
        }
    }
}

private struct LargeView: View {
    let snapshot: UsageSnapshot
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Header(snapshot: snapshot)
            ForEach(snapshot.limits.prefix(5)) { LimitRow(limit: $0, now: now) }
            if let used = snapshot.extraUsed, let limit = snapshot.extraLimit {
                ExtraUsageRow(used: used, limit: limit, currency: snapshot.currency)
            }
            Spacer(minLength: 0)
            if let error = snapshot.error {
                Text(error).font(.caption2).foregroundStyle(.orange).lineLimit(2)
            }
            Text("Updated \(Text(snapshot.fetchedAt, style: .time)) · checks every \(snapshot.pollMinutes) min")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}
