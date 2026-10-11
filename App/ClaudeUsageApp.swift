import AppKit
import ServiceManagement
import SwiftUI
import WidgetKit

@main
struct ClaudeUsageApp: App {
    @StateObject private var model = UsageModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContent().environmentObject(model)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "gauge.with.dots.needle.33percent")
                if model.showPercentInMenuBar, let first = model.snapshot?.limits.first {
                    Text("\(Int(first.percent(at: .now).rounded()))%")
                }
            }
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class UsageModel: ObservableObject {
    @Published var snapshot = UsageSnapshot.load()
    @Published var isRefreshing = false
    @Published var pollMinutes: Int {
        didSet {
            UserDefaults.standard.set(pollMinutes, forKey: "pollMinutes")
            startPolling()
        }
    }
    @Published var showPercentInMenuBar: Bool {
        didSet { UserDefaults.standard.set(showPercentInMenuBar, forKey: "showPercentInMenuBar") }
    }

    private var pollTask: Task<Void, Never>?

    init() {
        let saved = UserDefaults.standard.integer(forKey: "pollMinutes")
        pollMinutes = saved > 0 ? saved : 5
        showPercentInMenuBar = UserDefaults.standard.object(forKey: "showPercentInMenuBar") as? Bool ?? true
        startPolling()

        // Timers don't fire during sleep, so check right away on wake.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.startPolling() }
        }
    }

    func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                let minutes = self?.pollMinutes ?? 5
                try? await Task.sleep(for: .seconds(minutes * 60))
            }
        }
    }

    func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }

        var next: UsageSnapshot
        do {
            next = try await UsageClient.fetch(pollMinutes: pollMinutes)
        } catch {
            // Keep the last good numbers on screen and flag the problem.
            next = snapshot ?? UsageSnapshot(limits: [], fetchedAt: .distantPast)
            next.error = error.localizedDescription
        }
        next.pollMinutes = pollMinutes
        snapshot = next
        next.save()
        WidgetCenter.shared.reloadAllTimelines()
    }
}

struct MenuContent: View {
    @EnvironmentObject private var model: UsageModel
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "sparkle").foregroundStyle(Shared.accent)
                Text("Claude Usage").font(.headline)
                Spacer()
                Button {
                    Task { await model.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(model.isRefreshing)
                .help("Check now")
            }

            if let snapshot = model.snapshot, !snapshot.limits.isEmpty {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(snapshot.limits) { LimitRow(limit: $0, now: context.date) }
                    }
                }
                if let used = snapshot.extraUsed, let limit = snapshot.extraLimit {
                    ExtraUsageRow(used: used, limit: limit, currency: snapshot.currency)
                }
            } else if model.isRefreshing {
                ProgressView().frame(maxWidth: .infinity)
            }

            if let error = model.snapshot?.error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let fetched = model.snapshot?.fetchedAt, fetched > .distantPast {
                Text("Updated \(Text(fetched, style: .relative)) ago")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Picker("Check every", selection: $model.pollMinutes) {
                ForEach(Shared.pollChoices, id: \.self) { minutes in
                    Text(minutes == 60 ? "1 hour" : "\(minutes) min").tag(minutes)
                }
            }
            Toggle("Show % in menu bar", isOn: $model.showPercentInMenuBar)
            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, enabled in
                    try? enabled ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                    launchAtLogin = SMAppService.mainApp.status == .enabled
                }

            Divider()

            Button("Quit Claude Usage") { NSApp.terminate(nil) }
                .buttonStyle(.borderless)
        }
        .padding(16)
        .frame(width: 300)
    }
}
