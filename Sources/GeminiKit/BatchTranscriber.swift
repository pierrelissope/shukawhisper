import Foundation

/// Transcribes a complete recording in one request through the Interactions API.
///
/// Used as a fallback when the live socket is unavailable. Slower than live
/// transcription (~3 s) because processing only starts once the upload is done.
public struct BatchTranscriber: Sendable {
    private let http: HTTPClient

    public init(configuration: GeminiConfiguration) {
        self.http = HTTPClient(configuration: configuration)
    }

    /// - Parameters:
    ///   - pcm: 16 kHz, mono, 16-bit little-endian PCM samples.
    ///   - vocabulary: Terms the recognizer should favour (names, jargon).
    ///   - languageCodes: BCP-47 hints; empty means auto-detect.
    public func transcribe(pcm: Data, vocabulary: [String], languageCodes: [String] = []) async throws -> String {
        let wav = WAVEncoder.wav(fromPCM16: pcm, sampleRate: 16_000)
        let request = InteractionRequest(
            model: GeminiModel.batchTranscribe,
            input: [.init(type: "audio", data: wav.base64EncodedString(), mime_type: "audio/wav")],
            generation_config: .init(transcription_config: .init(
                language_codes: languageCodes,
                custom_vocabulary: vocabulary.isEmpty ? nil : Array(vocabulary.prefix(1000))
            ))
        )
        // Allow roughly real-time plus overhead for long recordings.
        let seconds = Double(pcm.count) / 32_000
        let response: InteractionResponse = try await http.post("interactions", body: request, timeout: 20 + seconds)
        let text = response.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw GeminiError.emptyResult }
        return text
    }
}

// MARK: - Wire types (the Interactions API uses snake_case keys)

struct InteractionRequest: Encodable {
    struct Input: Encodable {
        var type: String
        var data: String
        var mime_type: String
    }
    struct TranscriptionConfig: Encodable {
        var language_codes: [String]
        var custom_vocabulary: [String]?
    }
    struct GenerationConfig: Encodable { var transcription_config: TranscriptionConfig }

    var model: String
    var input: [Input]
    var generation_config: GenerationConfig
}

struct InteractionResponse: Decodable {
    struct Content: Decodable {
        var type: String?
        var text: String?
    }
    struct Step: Decodable {
        var type: String?
        var content: [Content]?
    }

    var output_text: String?
    var steps: [Step]?

    var text: String {
        if let output_text, !output_text.isEmpty { return output_text }
        return (steps ?? [])
            .filter { $0.type == nil || $0.type == "model_output" }
            .flatMap { $0.content ?? [] }
            .compactMap(\.text)
            .joined(separator: " ")
    }
}
