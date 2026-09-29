import Foundation
import Observation

/// Everything the user can configure, persisted as one JSON file.
public struct Configuration: Codable, Sendable, Equatable {
    public var settings = AppSettings()
    public var categories = StyleCategory.defaults
    public var dictionary: [DictionaryEntry] = []
    public var transforms = Transform.defaults

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        settings = try c.decodeIfPresent(AppSettings.self, forKey: .settings) ?? AppSettings()
        categories = try c.decodeIfPresent([StyleCategory].self, forKey: .categories) ?? StyleCategory.defaults
        dictionary = try c.decodeIfPresent([DictionaryEntry].self, forKey: .dictionary) ?? []
        transforms = try c.decodeIfPresent([Transform].self, forKey: .transforms) ?? Transform.defaults
        if !categories.contains(where: \.isFallback) {
            categories.append(StyleCategory.defaults.first(where: \.isFallback)!)
        }
    }

    public func transform(inSlot slot: Int) -> Transform? {
        transforms.first { $0.slot == slot }
    }
}

/// Observable owner of the `Configuration`. Every change is saved to disk automatically.
@MainActor
@Observable
public final class ConfigurationStore {
    public var configuration: Configuration {
        didSet { if configuration != oldValue { scheduleSave() } }
    }

    public let fileURL: URL
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    public init(fileURL: URL) {
        self.fileURL = fileURL
        self.configuration = Self.load(from: fileURL)
    }

    public nonisolated static func load(from url: URL) -> Configuration {
        guard let data = try? Data(contentsOf: url) else { return Configuration() }
        do {
            return try JSONDecoder().decode(Configuration.self, from: data)
        } catch {
            // Keep a copy of the unreadable file rather than silently overwriting the user's setup.
            let backup = url.deletingPathExtension().appendingPathExtension("corrupt.json")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.copyItem(at: url, to: backup)
            return Configuration()
        }
    }

    /// Writes immediately. Normally not needed: changes are saved after a short debounce.
    public func saveNow() {
        saveTask?.cancel()
        write(configuration)
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let self else { return }
            self.write(self.configuration)
        }
    }

    private func write(_ configuration: Configuration) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoder.encode(configuration).write(to: fileURL, options: .atomic)
        } catch {
            NSLog("ShukaWhisper: failed to save configuration: \(error)")
        }
    }
}
