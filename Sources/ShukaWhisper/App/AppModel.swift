import AppKit
import GeminiKit
import Observation
import ShukaCore

/// Root object of the app: owns persistent state, services and controllers.
@MainActor
@Observable
final class AppModel {
    let configurationStore: ConfigurationStore
    let history: HistoryStore
    let pill = PillModel()
    let hotkeys = HotkeyMonitor()
    @ObservationIgnored private(set) lazy var sessions = SessionController(app: self)

    private(set) var apiKey: String?
    private(set) var accessibilityGranted = Permissions.accessibilityGranted
    private(set) var microphoneGranted = Permissions.microphoneGranted
    /// Bumped whenever history changes so views can reload.
    private(set) var historyRevision = 0

    /// Opens the main window; set by the app delegate.
    @ObservationIgnored var showMainWindow: () -> Void = {}

    var configuration: Configuration {
        get { configurationStore.configuration }
        set { configurationStore.configuration = newValue }
    }

    var settings: AppSettings { configuration.settings }

    var gemini: GeminiConfiguration? {
        apiKey.map { GeminiConfiguration(apiKey: $0) }
    }

    /// Everything needed to dictate is in place.
    var isReady: Bool { apiKey != nil && accessibilityGranted && microphoneGranted }

    static let defaultSupportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appending(path: "ShukaWhisper", directoryHint: .isDirectory)

    init(supportDirectory support: URL = AppModel.defaultSupportDirectory, apiKey: String? = APIKeyStore.load()) {
        configurationStore = ConfigurationStore(fileURL: support.appending(path: "config.json"))
        do {
            history = try HistoryStore(url: support.appending(path: "history.sqlite"))
        } catch {
            NSLog("ShukaWhisper: history unavailable (\(error)); using an in-memory store")
            history = try! HistoryStore(url: nil)
        }
        self.apiKey = apiKey
    }

    /// Starts listening for hotkeys once permissions allow it.
    func start() {
        hotkeys.onEvent = { [weak self] event in self?.sessions.handle(event) }
        applySettings()
        refreshPermissions()
    }

    /// Pushes settings that services read directly.
    func applySettings() {
        hotkeys.dictationKey = settings.dictationKey
        pill.showsIdleIndicator = settings.showIdleIndicator
    }

    func refreshPermissions() {
        accessibilityGranted = Permissions.accessibilityGranted
        microphoneGranted = Permissions.microphoneGranted
        if accessibilityGranted, !hotkeys.isRunning {
            hotkeys.start()
        }
    }

    func setAPIKey(_ key: String?) {
        let trimmed = key?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            APIKeyStore.save(trimmed)
            apiKey = trimmed
        } else {
            APIKeyStore.delete()
            apiKey = nil
        }
    }

    func record(_ entry: HistoryEntry) {
        Task {
            do {
                try await history.insert(entry)
            } catch {
                NSLog("ShukaWhisper: could not save history: \(error)")
            }
            historyRevision += 1
        }
    }

    func historyDidChange() {
        historyRevision += 1
    }
}
