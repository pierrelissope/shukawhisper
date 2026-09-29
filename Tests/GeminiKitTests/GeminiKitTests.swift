import Foundation
import Testing
@testable import GeminiKit

@Suite struct LiveProtocolTests {
    @Test func parsesServerEvents() {
        #expect(LiveServerEvent.parse(Data(#"{"setupComplete": {}}"#.utf8)) == [.setupComplete])
        #expect(LiveServerEvent.parse(Data(#"{"serverContent": {"inputTranscription": {"text": "Bonjour"}}}"#.utf8)) == [.transcript("Bonjour")])
        #expect(LiveServerEvent.parse(Data(#"{"serverContent": {"generationComplete": true}}"#.utf8)) == [.generationComplete])
        #expect(LiveServerEvent.parse(Data(#"{"serverContent": {"interimInputTranscription": {"text": "Bon"}}}"#.utf8)) == [])
        #expect(LiveServerEvent.parse(Data(#"{"serverContent": {}, "voiceActivity": {"type": "ACTIVITY_END"}}"#.utf8)) == [])
        #expect(LiveServerEvent.parse(Data(#"{"error": {"message": "quota"}}"#.utf8)) == [.error("quota")])
        #expect(LiveServerEvent.parse(Data("garbage".utf8)) == [])
    }

    @Test func setupMessageUsesManualActivityDetection() throws {
        let json = LiveClientMessage.setup(model: "m", options: .init(vocabulary: ["Supabase"], languageCodes: []))
        let object = try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        let setup = try #require(object["setup"] as? [String: Any])
        #expect(setup["model"] as? String == "models/m")
        let transcription = try #require(setup["inputAudioTranscription"] as? [String: Any])
        #expect(transcription["customVocabulary"] as? [String] == ["Supabase"])
        #expect(transcription["mode"] == nil)
        let vad = (setup["realtimeInputConfig"] as? [String: Any])?["automaticActivityDetection"] as? [String: Any]
        #expect(vad?["disabled"] as? Bool == true)
    }

    @Test func audioMessageIsBase64PCM() throws {
        let json = LiveClientMessage.audio(Data([1, 2, 3]))
        #expect(json.contains(#""data":"AQID""#))
        #expect(json.contains("audio\\/pcm;rate=16000") || json.contains("audio/pcm;rate=16000"))
    }
}

@Suite struct ResponseParsingTests {
    @Test func generateContentSkipsThoughts() throws {
        let json = #"{"candidates":[{"content":{"parts":[{"text":"thinking...","thought":true},{"text":"Hello"},{"text":" world"}]}}]}"#
        let response = try JSONDecoder().decode(GenerateContentResponse.self, from: Data(json.utf8))
        #expect(response.text == "Hello world")
    }

    @Test func interactionResponseReadsSteps() throws {
        let json = #"{"status":"completed","steps":[{"type":"model_output","content":[{"type":"text","text":"Bonjour"}]}]}"#
        let response = try JSONDecoder().decode(InteractionResponse.self, from: Data(json.utf8))
        #expect(response.text == "Bonjour")
    }

    @Test func errorMessageExtraction() {
        let body = Data(#"{"error":{"code":400,"message":"API key not valid"}}"#.utf8)
        #expect(HTTPClient.errorMessage(from: body) == "API key not valid")
        #expect(GeminiError.api(status: 400, message: "API key not valid").errorDescription == "Invalid Gemini API key")
    }

    @Test func thinkingConfigPerModel() {
        #expect(TextGenerator.thinkingConfig(for: "gemini-3.5-flash-lite") == nil)
        #expect(TextGenerator.thinkingConfig(for: "gemini-3.8-flash")?.thinkingLevel == "low")
    }
}

@Suite struct WAVEncoderTests {
    @Test func writesValidHeader() {
        let pcm = Data(repeating: 0, count: 32_000)
        let wav = WAVEncoder.wav(fromPCM16: pcm, sampleRate: 16_000)
        #expect(wav.count == 44 + pcm.count)
        #expect(String(decoding: wav.prefix(4), as: UTF8.self) == "RIFF")
        #expect(String(decoding: wav[8..<12], as: UTF8.self) == "WAVE")
        let sampleRate = wav[24..<28].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        #expect(UInt32(littleEndian: sampleRate) == 16_000)
    }
}

/// Stubs URLSession responses so REST clients can be tested without the network.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        let (status, data) = Self.handler?(request) ?? (500, Data())
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
}

@Suite(.serialized) struct TextGeneratorTests {
    func makeGenerator() -> TextGenerator {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return TextGenerator(configuration: GeminiConfiguration(apiKey: "test-key", session: URLSession(configuration: config)))
    }

    @Test func sendsKeyAndReturnsTrimmedText() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.value(forHTTPHeaderField: "x-goog-api-key") == "test-key")
            #expect(request.url?.path.hasSuffix("models/gemini-3.5-flash-lite:generateContent") == true)
            return (200, Data(#"{"candidates":[{"content":{"parts":[{"text":"  Hello \n"}]}}]}"#.utf8))
        }
        let text = try await makeGenerator().generate(model: "gemini-3.5-flash-lite", system: "s", user: "u")
        #expect(text == "Hello")
    }

    @Test func mapsHTTPErrors() async {
        StubURLProtocol.handler = { _ in (429, Data(#"{"error":{"message":"Resource exhausted"}}"#.utf8)) }
        await #expect(throws: GeminiError.api(status: 429, message: "Resource exhausted")) {
            try await makeGenerator().generate(model: "m", system: "s", user: "u")
        }
    }

    @Test func emptyTextIsAnError() async {
        StubURLProtocol.handler = { _ in (200, Data(#"{"candidates":[]}"#.utf8)) }
        await #expect(throws: GeminiError.emptyResult) {
            try await makeGenerator().generate(model: "m", system: "s", user: "u")
        }
    }
}
