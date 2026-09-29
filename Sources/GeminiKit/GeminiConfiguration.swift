import Foundation

/// Connection settings shared by every Gemini client.
public struct GeminiConfiguration: Sendable {
    public var apiKey: String
    public var baseURL: URL
    public var liveURL: URL
    public var session: URLSession

    public init(
        apiKey: String,
        baseURL: URL = URL(string: "https://generativelanguage.googleapis.com/v1beta")!,
        liveURL: URL = URL(string: "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent")!,
        session: URLSession = .shared
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.liveURL = liveURL
        self.session = session
    }
}

/// Model identifiers used by the app. Chosen by benchmark, see `docs/PLAN.md`.
public enum GeminiModel {
    /// Streaming speech-to-text over WebSocket. Transcript is ready ~0.3 s after audio ends.
    public static let liveTranscribe = "gemini-3.5-transcribe-live"
    /// Request/response speech-to-text. Slower (~3 s) but works without a socket.
    public static let batchTranscribe = "gemini-3.5-transcribe"
    /// Fast text model used to clean up and style dictation (~0.5 s).
    public static let formatter = "gemini-3.5-flash-lite"
    /// Higher quality text model used for transforms.
    public static let transformer = "gemini-3.8-flash"
}
