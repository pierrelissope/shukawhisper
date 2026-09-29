import Foundation

/// One dictation or transform, as stored in the local history.
public struct HistoryEntry: Sendable, Identifiable, Equatable {
    public enum Kind: String, Sendable, CaseIterable {
        case dictation, transform, voiceTransform
    }

    public var id: UUID
    public var date: Date
    public var kind: Kind
    /// Transcript before cleanup (or the original selection for transforms).
    public var rawText: String
    /// Text that was inserted.
    public var finalText: String
    public var appName: String?
    public var bundleID: String?
    /// Style category or transform name.
    public var label: String?
    /// Length of the recording, in seconds (0 for keyboard transforms).
    public var audioDuration: TimeInterval
    /// Time from the end of speech to the text being inserted, in seconds.
    public var latency: TimeInterval
    public var errorMessage: String?

    public init(
        id: UUID = UUID(),
        date: Date = Date(),
        kind: Kind,
        rawText: String,
        finalText: String,
        appName: String? = nil,
        bundleID: String? = nil,
        label: String? = nil,
        audioDuration: TimeInterval = 0,
        latency: TimeInterval = 0,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.date = date
        self.kind = kind
        self.rawText = rawText
        self.finalText = finalText
        self.appName = appName
        self.bundleID = bundleID
        self.label = label
        self.audioDuration = audioDuration
        self.latency = latency
        self.errorMessage = errorMessage
    }

    public var wordCount: Int { finalText.wordCount }
}

extension String {
    var wordCount: Int {
        split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }
}
