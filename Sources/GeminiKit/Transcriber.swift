import Foundation

/// One recording's transcription: streams live, falls back to batch if the socket fails.
///
/// Every chunk is also kept locally, so a dropped connection never loses what was said.
public actor Transcriber {
    private let configuration: GeminiConfiguration
    private let options: LiveTranscriptionOptions
    private let live: LiveTranscriptionSession
    private var audio = Data()

    public init(configuration: GeminiConfiguration, options: LiveTranscriptionOptions) {
        self.configuration = configuration
        self.options = options
        self.live = LiveTranscriptionSession(configuration: configuration, options: options)
    }

    public func start() async {
        await live.start()
    }

    public func append(_ pcm: Data) async {
        audio.append(pcm)
        await live.append(pcm)
    }

    /// Seconds of audio received so far.
    public var duration: TimeInterval { Double(audio.count) / 32_000 }

    /// Final transcript. Empty when nothing intelligible was said.
    public func finish() async throws -> String {
        do {
            return try await live.finish(timeout: 6)
        } catch {
            guard !audio.isEmpty else { throw error }
            NSLog("ShukaWhisper: live transcription failed (\(error.localizedDescription)); falling back to batch")
            let batch = BatchTranscriber(configuration: configuration)
            return try await batch.transcribe(pcm: audio, vocabulary: options.vocabulary, languageCodes: options.languageCodes)
        }
    }

    public func cancel() async {
        await live.cancel()
    }
}
