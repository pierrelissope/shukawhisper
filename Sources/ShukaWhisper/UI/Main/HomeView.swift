import ShukaCore
import SwiftUI

/// Usage stats and searchable history.
struct HomeView: View {
    @Environment(AppModel.self) private var app
    @State private var entries: [HistoryEntry] = []
    @State private var stats = UsageStats()
    @State private var search = ""

    var body: some View {
        Page(title: "Home", subtitle: "Hold \(app.settings.dictationKey.title) anywhere to dictate. Double-tap it for hands-free.") {
            statsRow
            historySection
        }
        .task(id: ReloadKey(revision: app.historyRevision, search: search)) {
            await reload()
        }
    }

    private struct ReloadKey: Equatable {
        var revision: Int
        var search: String
    }

    private func reload() async {
        if !search.isEmpty { try? await Task.sleep(for: .milliseconds(150)) }
        entries = (try? await app.history.recent(limit: 300, matching: search)) ?? []
        stats = UsageStats(samples: (try? await app.history.statsSamples()) ?? [])
    }

    // MARK: Stats

    private var statsRow: some View {
        HStack(spacing: 12) {
            StatTile(value: stats.totalWords.formatted(), label: "words dictated", symbol: "text.word.spacing")
            StatTile(value: "\(stats.wordsPerMinute)", label: "words per minute", symbol: "speedometer")
            StatTile(value: Self.duration(minutes: stats.minutesSaved), label: "saved vs typing", symbol: "clock.arrow.circlepath")
            StatTile(value: "\(stats.dayStreak)", label: stats.dayStreak == 1 ? "day streak" : "days streak", symbol: "flame")
        }
    }

    private static func duration(minutes: Int) -> String {
        minutes < 60 ? "\(minutes) min" : String(format: "%.1f h", Double(minutes) / 60)
    }

    // MARK: History

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("History").font(.title3.weight(.semibold))
                Spacer()
                TextField("Search", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
            }

            if entries.isEmpty {
                Card {
                    VStack(spacing: 8) {
                        Image(systemName: "waveform")
                            .font(.system(size: 28))
                            .foregroundStyle(Theme.accent)
                        Text(search.isEmpty ? "Nothing yet" : "No matches")
                            .font(.headline)
                        Text(search.isEmpty ? "Your dictations and transforms will show up here." : "Try another search.")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                }
            } else {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(groupedByDay, id: \.day) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(group.day, format: .dateTime.weekday(.wide).day().month())
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                            Card(padding: 0) {
                                VStack(spacing: 0) {
                                    ForEach(group.entries) { entry in
                                        HistoryRow(entry: entry) { delete(entry) }
                                        if entry.id != group.entries.last?.id { Divider().padding(.leading, 16) }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var groupedByDay: [(day: Date, entries: [HistoryEntry])] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: entries) { calendar.startOfDay(for: $0.date) }
        return groups.keys.sorted(by: >).map { ($0, groups[$0]!) }
    }

    private func delete(_ entry: HistoryEntry) {
        Task {
            try? await app.history.delete(id: entry.id)
            app.historyDidChange()
        }
    }
}

private struct StatTile: View {
    let value: String
    let label: String
    let symbol: String

    var body: some View {
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                Text(value)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct HistoryRow: View {
    let entry: HistoryEntry
    let onDelete: () -> Void
    @State private var hovering = false
    @State private var showRaw = false
    @State private var copied = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(entry.date, format: .dateTime.hour().minute())
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .leading)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 6) {
                Text(showRaw ? entry.rawText : entry.finalText)
                    .textSelection(.enabled)
                    .lineLimit(showRaw ? nil : 4)
                    .foregroundStyle(showRaw ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 6) {
                    if let appName = entry.appName { Chip(text: appName) }
                    if let label = entry.label { Chip(text: label, systemImage: kindSymbol, prominent: true) }
                    if entry.latency > 0 {
                        Text(String(format: "%.1fs", entry.latency))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            HStack(spacing: 2) {
                iconButton(copied ? "checkmark" : "doc.on.doc", help: "Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(entry.finalText, forType: .string)
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.2))
                        copied = false
                    }
                }
                iconButton(showRaw ? "text.badge.checkmark" : "text.quote",
                           help: showRaw ? "Show final text" : "Show original") { showRaw.toggle() }
                iconButton("trash", help: "Delete", action: onDelete)
            }
            .opacity(hovering ? 1 : 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(.rect)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }

    private var kindSymbol: String {
        switch entry.kind {
        case .dictation: "waveform"
        case .transform: "wand.and.sparkles"
        case .voiceTransform: "mic.badge.plus"
        }
    }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 24, height: 24)
                .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .help(help)
    }
}
