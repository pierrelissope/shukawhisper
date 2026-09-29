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

public struct AppSettings: Codable, Sendable, Equatable {
    public var dictationKey: DictationKey = .fn
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
        languageMode = try c.decodeIfPresent(LanguageMode.self, forKey: .languageMode) ?? d.languageMode
        cleanupEnabled = try c.decodeIfPresent(Bool.self, forKey: .cleanupEnabled) ?? d.cleanupEnabled
        formatterModel = try c.decodeIfPresent(String.self, forKey: .formatterModel) ?? d.formatterModel
        transformModel = try c.decodeIfPresent(String.self, forKey: .transformModel) ?? d.transformModel
        playSounds = try c.decodeIfPresent(Bool.self, forKey: .playSounds) ?? d.playSounds
        showIdleIndicator = try c.decodeIfPresent(Bool.self, forKey: .showIdleIndicator) ?? d.showIdleIndicator
        restoreClipboard = try c.decodeIfPresent(Bool.self, forKey: .restoreClipboard) ?? d.restoreClipboard
    }
}
