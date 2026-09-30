import Foundation

/// Spoken language hint passed to the transcriber.
public enum LanguageMode: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Auto-detect, including mid-sentence French/English switching. Recommended.
    case auto
    case english
    case french

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .auto: "Auto-detect"
        case .english: "English"
        case .french: "French"
        }
    }

    public var languageCodes: [String] {
        switch self {
        case .auto: []
        case .english: ["en-US"]
        case .french: ["fr-FR"]
        }
    }
}

/// The key held down to dictate.
public enum DictationKey: String, Codable, CaseIterable, Sendable, Identifiable {
    case fn, rightOption, rightCommand

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .fn: "fn / 🌐"
        case .rightOption: "Right ⌥ Option"
        case .rightCommand: "Right ⌘ Command"
        }
    }

    /// Virtual key code reported in `flagsChanged` events.
    public var keyCode: UInt16 {
        switch self {
        case .fn: 63
        case .rightOption: 61
        case .rightCommand: 54
        }
    }
}

/// Modifier held with a number key to run a transform.
public enum TransformModifier: String, Codable, CaseIterable, Sendable, Identifiable {
    /// `⌃⌥` + digit: leaves plain `⌥` + digit free for typing symbols (`{`, `}`, `[`… on AZERTY).
    case controlOption
    /// `⌥` + digit: shorter, but hides the symbols macOS types with Option + number keys.
    case option

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .controlOption: "⌃ Control + ⌥ Option"
        case .option: "⌥ Option only"
        }
    }

    public var symbols: [String] {
        switch self {
        case .controlOption: ["⌃", "⌥"]
        case .option: ["⌥"]
        }
    }

    /// Key caps for a slot, e.g. `["⌃", "⌥", "1"]`.
    public func keys(slot: Int) -> [String] { symbols + ["\(slot)"] }

    /// Compact label for a slot, e.g. `⌃⌥1`.
    public func label(slot: Int) -> String { keys(slot: slot).joined() }
}

public struct AppSettings: Codable, Sendable, Equatable {
    public var dictationKey: DictationKey = .fn
    public var transformModifier: TransformModifier = .controlOption
    public var languageMode: LanguageMode = .auto
    /// Run the AI cleanup/style pass. When off, the raw transcript is inserted.
    public var cleanupEnabled = true
    public var formatterModel = "gemini-3.5-flash-lite"
    public var transformModel = "gemini-3.8-flash"
    public var playSounds = true
    /// Show a small resting dot at the bottom of the screen when idle.
    public var showIdleIndicator = true
    /// Put the previous clipboard content back after inserting text.
    public var restoreClipboard = true

    public init() {}

    public init(from decoder: Decoder) throws {
        // Every field is optional on disk so new settings never break old config files.
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        dictationKey = try c.decodeIfPresent(DictationKey.self, forKey: .dictationKey) ?? d.dictationKey
        transformModifier = try c.decodeIfPresent(TransformModifier.self, forKey: .transformModifier) ?? d.transformModifier
        languageMode = try c.decodeIfPresent(LanguageMode.self, forKey: .languageMode) ?? d.languageMode
        cleanupEnabled = try c.decodeIfPresent(Bool.self, forKey: .cleanupEnabled) ?? d.cleanupEnabled
        formatterModel = try c.decodeIfPresent(String.self, forKey: .formatterModel) ?? d.formatterModel
        transformModel = try c.decodeIfPresent(String.self, forKey: .transformModel) ?? d.transformModel
        playSounds = try c.decodeIfPresent(Bool.self, forKey: .playSounds) ?? d.playSounds
        showIdleIndicator = try c.decodeIfPresent(Bool.self, forKey: .showIdleIndicator) ?? d.showIdleIndicator
        restoreClipboard = try c.decodeIfPresent(Bool.self, forKey: .restoreClipboard) ?? d.restoreClipboard
    }
}
