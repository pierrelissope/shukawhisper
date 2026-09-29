import Foundation

/// Options for a live transcription session.
public struct LiveTranscriptionOptions: Sendable, Equatable {
    /// Terms the recognizer should favour (names, jargon). Up to 1,000; ~100 works best.
    public var vocabulary: [String]
    /// BCP-47 hints. Empty = auto-detect, which handles FR/EN code-switching best.
    public var languageCodes: [String]

    public init(vocabulary: [String] = [], languageCodes: [String] = []) {
        self.vocabulary = vocabulary
        self.languageCodes = languageCodes
    }
}

/// Streams microphone audio to `gemini-3.5-transcribe-live` while the user speaks.
///
/// Push-to-talk flow (manual voice activity detection):
/// ```
/// let session = LiveTranscriptionSession(configuration: config, options: options)
/// await session.start()            // opens the socket in the background
/// await session.append(pcmChunk)   // as audio arrives; buffered until the socket is ready
/// let text = try await session.finish()  // key released -> final transcript (~0.3 s)
/// ```
/// Because the server transcribes as audio arrives, the transcript is almost ready
/// by the time the user releases the key.
public actor LiveTranscriptionSession {
    private enum Phase { case idle, connecting, streaming, closed }

    private let configuration: GeminiConfiguration
    private let options: LiveTranscriptionOptions

    private var socket: URLSessionWebSocketTask?
    private var phase = Phase.idle
    private var pendingAudio: [Data] = []
    private var finishRequested = false
    private var transcript = ""
    private var generationComplete = false
    private var failure: GeminiError?
    private var finishWaiter: CheckedContinuation<String, Error>?

    public init(configuration: GeminiConfiguration, options: LiveTranscriptionOptions) {
        self.configuration = configuration
        self.options = options
    }

    /// Opens the WebSocket and sends the setup message. Returns immediately.
    public func start() {
        guard phase == .idle else { return }
        phase = .connecting

        var url = configuration.liveURL
        url.append(queryItems: [URLQueryItem(name: "key", value: configuration.apiKey)])
        let socket = configuration.session.webSocketTask(with: url)
        socket.maximumMessageSize = 16 * 1024 * 1024
        self.socket = socket
        socket.resume()

        send(LiveClientMessage.setup(model: GeminiModel.liveTranscribe, options: options))
        Task { await receiveLoop() }
    }

    /// Queues 16 kHz mono PCM16 audio. Safe to call before the socket is ready.
    public func append(_ pcm: Data) {
        guard !pcm.isEmpty, !finishRequested else { return }
        switch phase {
        case .idle, .connecting: pendingAudio.append(pcm)
        case .streaming: send(LiveClientMessage.audio(pcm))
        case .closed: break
        }
    }

    /// Signals the end of speech and waits for the final transcript.
    /// Returns an empty string if nothing intelligible was said.
    public func finish(timeout: TimeInterval = 8) async throws -> String {
        finishRequested = true
        if phase == .streaming { send(LiveClientMessage.activityEnd) }

        let text = try await withTimeout(timeout) { try await self.waitForTranscript() }
        close()
        return text
    }

    /// Aborts the session; any pending `finish()` throws.
    public func cancel() {
        fail(.connection("cancelled"))
        close()
    }

    // MARK: - Internals

    private func waitForTranscript() async throws -> String {
        if generationComplete { return transcript.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let failure { throw failure }
        return try await withCheckedThrowingContinuation { finishWaiter = $0 }
    }

    private func receiveLoop() async {
        while let socket, phase != .closed {
            do {
                let message = try await socket.receive()
                let data: Data
                switch message {
                case let .data(d): data = d
                case let .string(s): data = Data(s.utf8)
                @unknown default: continue
                }
                for event in LiveServerEvent.parse(data) { handle(event) }
            } catch {
                handleDisconnect(reason: socket.closeReasonText ?? error.localizedDescription)
                return
            }
        }
    }

    private func handle(_ event: LiveServerEvent) {
        switch event {
        case .setupComplete:
            phase = .streaming
            send(LiveClientMessage.activityStart)
            pendingAudio.forEach { send(LiveClientMessage.audio($0)) }
            pendingAudio.removeAll()
            if finishRequested { send(LiveClientMessage.activityEnd) }
        case let .transcript(text):
            transcript += transcript.isEmpty || text.hasPrefix(" ") ? text : " " + text
        case .generationComplete:
            generationComplete = true
            resumeWaiter()
        case let .error(message):
            fail(.connection(message))
        }
    }

    private func handleDisconnect(reason: String) {
        guard phase != .closed else { return }
        if finishRequested, !transcript.isEmpty {
            // The server closed right after sending text: treat what we have as final.
            generationComplete = true
            resumeWaiter()
        } else {
            fail(.connection(reason))
        }
        phase = .closed
    }

    private func resumeWaiter() {
        finishWaiter?.resume(returning: transcript.trimmingCharacters(in: .whitespacesAndNewlines))
        finishWaiter = nil
    }

    private func fail(_ error: GeminiError) {
        guard failure == nil else { return }
        failure = error
        finishWaiter?.resume(throwing: error)
        finishWaiter = nil
    }

    private func close() {
        phase = .closed
        socket?.cancel(with: .normalClosure, reason: nil)
        socket = nil
    }

    /// Uses the callback-based `send` so messages are enqueued synchronously, in call order.
    private func send(_ json: String) {
        socket?.send(.string(json)) { _ in }
    }
}

private extension URLSessionWebSocketTask {
    var closeReasonText: String? {
        guard let closeReason, !closeReason.isEmpty else { return nil }
        return String(decoding: closeReason, as: UTF8.self)
    }
}

// MARK: - Protocol messages

/// Client → server messages of the BidiGenerateContent protocol.
enum LiveClientMessage {
    static func setup(model: String, options: LiveTranscriptionOptions) -> String {
        var transcription: [String: Any] = ["languageCodes": options.languageCodes]
        if !options.vocabulary.isEmpty {
            transcription["customVocabulary"] = Array(options.vocabulary.prefix(1000))
        }
        return json([
            "setup": [
                "model": "models/\(model)",
                "generationConfig": ["responseModalities": ["TEXT"]],
                "inputAudioTranscription": transcription,
                // Push-to-talk: we mark the start and end of speech ourselves.
                "realtimeInputConfig": ["automaticActivityDetection": ["disabled": true]],
            ],
        ])
    }

    static let activityStart = json(["realtimeInput": ["activityStart": [String: Any]()]])
    static let activityEnd = json(["realtimeInput": ["activityEnd": [String: Any]()]])

    static func audio(_ pcm: Data) -> String {
        json(["realtimeInput": ["audio": [
            "data": pcm.base64EncodedString(),
            "mimeType": "audio/pcm;rate=16000",
        ]]])
    }

    private static func json(_ object: [String: Any]) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }
}

/// Server → client events we care about.
enum LiveServerEvent: Equatable {
    case setupComplete
    case transcript(String)
    case generationComplete
    case error(String)

    static func parse(_ data: Data) -> [LiveServerEvent] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        var events: [LiveServerEvent] = []
        if object["setupComplete"] != nil { events.append(.setupComplete) }
        if let content = object["serverContent"] as? [String: Any] {
            if let transcription = content["inputTranscription"] as? [String: Any],
               let text = transcription["text"] as? String, !text.isEmpty {
                events.append(.transcript(text))
            }
            if content["generationComplete"] as? Bool == true || content["turnComplete"] as? Bool == true {
                events.append(.generationComplete)
            }
        }
        if let error = object["error"] as? [String: Any] {
            events.append(.error(error["message"] as? String ?? "unknown error"))
        }
        return events
    }
}
