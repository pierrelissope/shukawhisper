import GeminiKit
import ServiceManagement
import ShukaCore
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @State private var confirmClearHistory = false

    var body: some View {
        @Bindable var store = app.configurationStore
        let settings = $store.configuration.settings

        Page(title: "Settings", subtitle: "Shortcuts, language, models and permissions.") {
            group("Dictation") {
                row("Dictation key", detail: "Hold to talk, double-tap for hands-free.") {
                    Picker("", selection: settings.dictationKey) {
                        ForEach(DictationKey.allCases) { Text($0.title).tag($0) }
                    }
                    .fixedSize()
                }
                if app.settings.dictationKey == .fn {
                    Text("Set System Settings › Keyboard › \"Press 🌐 key to\" to **Do Nothing**, and quit other dictation apps using fn.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Open Keyboard Settings") { Permissions.openKeyboardSettings() }
                        .buttonStyle(.link)
                        .font(.caption)
                }
                row("Transform shortcut", detail: "Held with a number key. ⌃⌥ keeps ⌥ + number free for typing symbols.") {
                    Picker("", selection: settings.transformModifier) {
                        ForEach(TransformModifier.allCases) { Text($0.title).tag($0) }
                    }
                    .fixedSize()
                }
                Divider()
                row("Spoken language", detail: "Auto-detect handles French and English in the same sentence.") {
                    Picker("", selection: settings.languageMode) {
                        ForEach(LanguageMode.allCases) { Text($0.title).tag($0) }
                    }
                    .fixedSize()
                }
                Divider()
                row("AI cleanup & styles", detail: "Remove filler words, fix punctuation and apply your styles. Off inserts the raw transcript.") {
                    Toggle("", isOn: settings.cleanupEnabled).labelsHidden()
                }
                row("Sound effects") {
                    Toggle("", isOn: settings.playSounds).labelsHidden()
                }
                row("Show resting indicator", detail: "A small dot at the bottom of the screen when idle.") {
                    Toggle("", isOn: settings.showIdleIndicator).labelsHidden()
                }
                row("Restore clipboard after inserting", detail: "Your clipboard is put back after text is pasted.") {
                    Toggle("", isOn: settings.restoreClipboard).labelsHidden()
                }
                row("Open at login") {
                    LaunchAtLoginToggle()
                }
            }

            APIKeySection()

            group("Models") {
                row("Cleanup model", detail: "Fast model applied to every dictation.") {
                    TextField("", text: settings.formatterModel).frame(width: 220)
                }
                row("Transform model", detail: "Used for transforms and voice edits.") {
                    TextField("", text: settings.transformModel).frame(width: 220)
                }
                Text("Transcription uses \(GeminiModel.liveTranscribe) (streaming), with \(GeminiModel.batchTranscribe) as a fallback.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .textFieldStyle(.roundedBorder)

            PermissionsSection()

            group("Data") {
                row("Configuration & history", detail: "Stored locally in Application Support. Audio is never saved.") {
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([app.configurationStore.fileURL])
                    }
                }
                row("History", detail: "Delete every saved dictation and transform.") {
                    Button("Clear history…", role: .destructive) { confirmClearHistory = true }
                }
            }
        }
        .onChange(of: app.settings) { app.applySettings() }
        .confirmationDialog("Delete all history?", isPresented: $confirmClearHistory) {
            Button("Delete all", role: .destructive) {
                Task {
                    try? await app.history.deleteAll()
                    app.historyDidChange()
                }
            }
        } message: {
            Text("Stats are computed from history, so they will reset too.")
        }
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.title3.weight(.semibold))
            Card {
                VStack(alignment: .leading, spacing: 12) { content() }
            }
        }
        .toggleStyle(.switch)
    }

    private func row<Control: View>(_ title: String, detail: String? = nil, @ViewBuilder control: () -> Control) -> some View {
        HStack {
            label(title, detail: detail)
            Spacer()
            control()
        }
    }

    private func label(_ title: String, detail: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            if let detail {
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct LaunchAtLoginToggle: View {
    @State private var enabled = SMAppService.mainApp.status == .enabled

    var body: some View {
        Toggle("Open at login", isOn: $enabled)
            .labelsHidden()
            .onChange(of: enabled) { _, newValue in
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                Log.info("launch at login failed: \(error)")
                enabled = SMAppService.mainApp.status == .enabled
            }
        }
    }
}

/// Shows, tests and replaces the Gemini API key.
struct APIKeySection: View {
    @Environment(AppModel.self) private var app
    @State private var draft = ""
    @State private var status: KeyStatus = .idle

    enum KeyStatus: Equatable { case idle, checking, valid, invalid(String) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Gemini API key").font(.title3.weight(.semibold))
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        if let key = app.apiKey {
                            Image(systemName: "key.fill").foregroundStyle(Theme.accent)
                            Text(Self.masked(key)).font(.body.monospaced())
                        } else {
                            Image(systemName: "key").foregroundStyle(.secondary)
                            Text("No key yet").foregroundStyle(.secondary)
                        }
                        Spacer()
                        statusView
                    }
                    HStack {
                        SecureField(app.apiKey == nil ? "Paste your API key" : "Replace key…", text: $draft)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit(save)
                        Button("Save", action: save)
                            .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                        if app.apiKey != nil {
                            Button("Test") { Task { await test(app.apiKey!) } }
                        }
                    }
                    Link("Get a free key at aistudio.google.com", destination: URL(string: "https://aistudio.google.com/apikey")!)
                        .font(.caption)
                    Text("Saved in ~/.config/shukawhisper/key, readable only by you. Only sent to Google's Gemini API.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var statusView: some View {
        switch status {
        case .idle: EmptyView()
        case .checking: ProgressView().controlSize(.small)
        case .valid: Label("Working", systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.callout)
        case let .invalid(message): Label(message, systemImage: "xmark.octagon.fill").foregroundStyle(.red).font(.callout).lineLimit(1)
        }
    }

    private func save() {
        let key = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        draft = ""
        Task {
            if await test(key) { app.setAPIKey(key) }
        }
    }

    @discardableResult
    private func test(_ key: String) async -> Bool {
        status = .checking
        do {
            let models = try await TextGenerator(configuration: GeminiConfiguration(apiKey: key)).listModels()
            guard models.contains(GeminiModel.liveTranscribe) else {
                status = .invalid("Key lacks \(GeminiModel.liveTranscribe)")
                return false
            }
            status = .valid
            return true
        } catch {
            status = .invalid((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            return false
        }
    }

    static func masked(_ key: String) -> String {
        guard key.count > 10 else { return String(repeating: "•", count: key.count) }
        return key.prefix(6) + String(repeating: "•", count: 8) + key.suffix(4)
    }
}

struct PermissionsSection: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Permissions").font(.title3.weight(.semibold))
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    PermissionRow(
                        title: "Microphone", detail: "To hear your voice.",
                        granted: app.microphoneGranted
                    ) {
                        Task {
                    await Permissions.requestMicrophone()
                    app.refreshPermissions()
                }
                    }
                    Divider()
                    PermissionRow(
                        title: "Accessibility", detail: "To detect the dictation key and type text for you.",
                        granted: app.accessibilityGranted
                    ) {
                        Permissions.requestAccessibility()
                        Permissions.openAccessibilitySettings()
                    }
                }
            }
        }
        .task {
            // Permissions are granted in System Settings; poll while this view is visible.
            while !Task.isCancelled {
                app.refreshPermissions()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}

struct PermissionRow: View {
    let title: String
    let detail: String
    let granted: Bool
    let action: () -> Void

    var body: some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(granted ? .green : .orange)
                .font(.system(size: 18))
                .contentTransition(.symbolEffect(.replace))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !granted {
                Button("Grant", action: action)
            }
        }
        .animation(Theme.Motion.select, value: granted)
    }
}
