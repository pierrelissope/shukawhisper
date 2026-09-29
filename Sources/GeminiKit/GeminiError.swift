import Foundation

public enum GeminiError: Error, Equatable, Sendable, LocalizedError {
    /// The API rejected the request (bad key, quota, invalid argument, ...).
    case api(status: Int, message: String)
    /// The response could not be understood.
    case invalidResponse(String)
    /// The live transcription socket closed or failed before a transcript arrived.
    case connection(String)
    /// No answer within the allotted time.
    case timeout
    /// The model returned no text.
    case emptyResult

    public var errorDescription: String? {
        switch self {
        case let .api(status, message):
            switch status {
            case 400 where message.localizedCaseInsensitiveContains("api key"),
                 401, 403:
                return "Invalid Gemini API key"
            case 429:
                return "Gemini rate limit reached"
            default:
                return message.isEmpty ? "Gemini error \(status)" : message
            }
        case let .invalidResponse(detail): return "Unexpected Gemini response: \(detail)"
        case let .connection(detail): return "Connection failed: \(detail)"
        case .timeout: return "Gemini took too long to answer"
        case .emptyResult: return "Nothing was transcribed"
        }
    }
}

/// Runs `operation`, throwing `GeminiError.timeout` if it doesn't finish in time.
func withTimeout<T: Sendable>(
    _ seconds: TimeInterval,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: .seconds(seconds))
            throw GeminiError.timeout
        }
        defer { group.cancelAll() }
        return try await group.next()!
    }
}
