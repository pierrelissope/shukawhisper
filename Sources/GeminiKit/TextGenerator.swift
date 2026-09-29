import Foundation

/// Anything that turns a system instruction + user text into model text.
/// The app depends on this protocol so it can be faked in tests.
public protocol TextGenerating: Sendable {
    func generate(model: String, system: String, user: String) async throws -> String
}

/// Calls `models/{model}:generateContent` for single-turn text generation.
public struct TextGenerator: TextGenerating {
    private let http: HTTPClient
    private let timeout: TimeInterval

    public init(configuration: GeminiConfiguration, timeout: TimeInterval = 15) {
        self.http = HTTPClient(configuration: configuration)
        self.timeout = timeout
    }

    public func generate(model: String, system: String, user: String) async throws -> String {
        let request = GenerateContentRequest(
            systemInstruction: .init(parts: [.init(text: system)]),
            contents: [.init(role: "user", parts: [.init(text: user)])],
            generationConfig: .init(temperature: 0, thinkingConfig: Self.thinkingConfig(for: model))
        )
        let response: GenerateContentResponse = try await http.post(
            "models/\(model):generateContent", body: request, timeout: timeout
        )
        let text = response.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw GeminiError.emptyResult }
        return text
    }

    /// Opens (or refreshes) the HTTPS connection with a free metadata request, so the
    /// next `generate` call skips the TLS handshake. Call it when recording starts.
    public func warmUp(model: String) async {
        struct ModelInfo: Decodable { var name: String }
        let _: ModelInfo? = try? await http.get("models/\(model)", timeout: 5)
    }

    /// Lists the models the key can use. Doubles as an API key check.
    public func listModels() async throws -> [String] {
        let response: ModelList = try await http.get("models", query: [.init(name: "pageSize", value: "200")], timeout: 10)
        return response.models.map { $0.name.replacingOccurrences(of: "models/", with: "") }
    }

    /// Keeps latency low: Flash-Lite models answer best without thinking, larger Flash
    /// models reject "minimal" and use "low" instead.
    static func thinkingConfig(for model: String) -> GenerateContentRequest.ThinkingConfig? {
        model.contains("lite") ? nil : .init(thinkingLevel: "low")
    }
}

// MARK: - Wire types

struct GenerateContentRequest: Encodable {
    struct Part: Codable { var text: String? }
    struct Content: Encodable {
        var role: String?
        var parts: [Part]
    }
    struct ThinkingConfig: Encodable { var thinkingLevel: String }
    struct GenerationConfig: Encodable {
        var temperature: Double
        var thinkingConfig: ThinkingConfig?
    }

    var systemInstruction: Content
    var contents: [Content]
    var generationConfig: GenerationConfig
}

struct GenerateContentResponse: Decodable {
    struct Part: Decodable {
        var text: String?
        var thought: Bool?
    }
    struct Content: Decodable { var parts: [Part]? }
    struct Candidate: Decodable { var content: Content? }

    var candidates: [Candidate]?

    /// Concatenated visible text of the first candidate (thought summaries excluded).
    var text: String {
        (candidates?.first?.content?.parts ?? [])
            .filter { $0.thought != true }
            .compactMap(\.text)
            .joined()
    }
}

struct ModelList: Decodable {
    struct Model: Decodable { var name: String }
    var models: [Model]
}
