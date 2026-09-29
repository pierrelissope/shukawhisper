import AppKit
import ShukaCore
import SwiftUI

/// Developer command: renders every screen and pill state to PNG files with sample data.
///
/// ```
/// ShukaWhisper --snapshots docs/screenshots
/// ```
/// Used for the README and to review UI changes without clicking through the app.
/// Nothing touches your real configuration or history: a temporary directory is used.
@MainActor
enum Snapshots {
    static func runIfRequested() async -> Bool {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--snapshots"), index + 1 < arguments.count else { return false }
        let output = URL(filePath: arguments[index + 1], directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)

        let model = await sampleModel()
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let suffix = appearance == .darkAqua ? "-dark" : ""
            let pages: [(String, AnyView)] = [
                ("home", AnyView(HomeView())),
                ("styles", AnyView(StylesView())),
                ("dictionary", AnyView(DictionaryView())),
                ("transforms", AnyView(TransformsView())),
                ("settings", AnyView(SettingsView())),
                ("onboarding", AnyView(OnboardingView {})),
            ]
            for (name, page) in pages {
                render(page.environment(model).tint(Theme.accent).background(.background),
                       size: CGSize(width: 860, height: 760), appearance: appearance,
                       to: output.appending(path: "\(name)\(suffix).png"))
            }
        }

        let phases: [(String, PillModel.Phase)] = [
            ("idle", .idle), ("recording", .recording), ("locked", .locked),
            ("processing", .processing), ("success", .success), ("error", .error("No internet connection")),
        ]
        for (name, phase) in phases {
            let pill = PillModel()
            pill.label = "Work messages"
            if phase == .recording || phase == .locked {
                pill.beginRecording()
                for level in [0.2, 0.5, 0.9, 0.6, 0.8, 0.4, 0.7, 0.95, 0.5, 0.3, 0.6, 0.85, 0.45, 0.7, 0.55] {
                    pill.push(level: Float(level))
                }
            }
            pill.phase = phase
            let backdrop = LinearGradient(colors: [Color(red: 0.2, green: 0.25, blue: 0.4), Color(red: 0.55, green: 0.35, blue: 0.45)],
                                          startPoint: .topLeading, endPoint: .bottomTrailing)
            render(PillView(model: pill).background(backdrop), size: CGSize(width: 420, height: 110),
                   appearance: .darkAqua, to: output.appending(path: "pill-\(name).png"))
        }
        print("✓ Snapshots written to \(output.path)")
        return true
    }

    private static func sampleModel() async -> AppModel {
        let directory = FileManager.default.temporaryDirectory.appending(path: "shukawhisper-snapshots-\(UUID().uuidString)")
        let model = AppModel(supportDirectory: directory)
        model.configuration.dictionary = ["Supabase", "kubectl", "Claude Code", "Vercel", "Théo", "TanStack Query"]
            .map { DictionaryEntry(term: $0) }
        model.configuration.dictionary[1].aliases = ["cube control", "cubectal"]

        let now = Date()
        let samples: [(TimeInterval, String, String, String, String, HistoryEntry.Kind)] = [
            (-120, "Slack", "Work messages", "euh je pense qu'on peut merge la PR, les tests passent", "Je pense qu'on peut merge la PR, les tests passent", .dictation),
            (-900, "Terminal", "AI prompts & code", "refactor the auth hook to use TanStack Query and add tests", "Refactor the auth hook to use TanStack Query and add tests", .dictation),
            (-3600, "Google Chrome", "Email", "hi anna thanks for the quick reply i'll send the contract tomorrow best theo", "Hi Anna,\n\nThanks for the quick reply. I'll send the contract tomorrow.\n\nBest,\nThéo", .dictation),
            (-7200, "Notes", "Polish", "the meeting went good we decided things", "The meeting went well, and we made several decisions.", .transform),
            (-90_000, "WhatsApp", "Personal messages", "on se retrouve à 20h au resto", "On se retrouve à 20h au resto", .dictation),
        ]
        for (offset, app, label, raw, final, kind) in samples {
            try? await model.history.insert(HistoryEntry(
                date: now.addingTimeInterval(offset), kind: kind, rawText: raw, finalText: final,
                appName: app, label: label, audioDuration: kind == .dictation ? Double(final.count) / 14 : 0,
                latency: 0.8
            ))
        }
        return model
    }

    private static func render<V: View>(_ view: V, size: CGSize, appearance: NSAppearance.Name, to url: URL) {
        let hosting = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.contentView = hosting
        window.orderBack(nil)
        // Let SwiftUI run `.task` modifiers and animations settle.
        RunLoop.main.run(until: Date().addingTimeInterval(0.8))
        hosting.layoutSubtreeIfNeeded()

        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        window.orderOut(nil)
    }
}
