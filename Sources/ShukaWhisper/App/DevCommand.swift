import Foundation
import GeminiKit
import ShukaCore

/// Developer command: runs a WAV file through the full pipeline without the UI.
///
/// ```
/// ShukaWhisper --transcribe sample.wav [--bundle com.tinyspeck.slackmacgap] [--host mail.google.com]
/// ```
/// Audio is streamed at real-time speed, as if spoken, so the printed latency after
/// "release" matches what you'd feel when dictating.
enum DevCommand {
    static func runIfRequested() async -> Bool {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--transcribe"), index + 1 < arguments.count else { return false }

        func value(_ flag: String) -> String? {
            arguments.firstIndex(of: flag).flatMap { $0 + 1 < arguments.count ? arguments[$0 + 1] : nil }
        }

        do {
            try await run(file: URL(filePath: arguments[index + 1]), bundleID: value("--bundle"), host: value("--host"))
        } catch {
            print("error: \(error.localizedDescription)")
            exit(1)
        }
        return true
    }

    private static func run(file: URL, bundleID: String?, host: String?) async throws {
        guard let key = APIKeyProvider.load() else {
            print("error: no API key (set GEMINI_API_KEY or ~/.config/shukawhisper/key)")
            exit(1)
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let configuration = ConfigurationStore.load(from: support.appending(path: "ShukaWhisper/config.json"))
        let gemini = GeminiConfiguration(apiKey: key)

        let pcm = try pcmData(fromWAV: Data(contentsOf: file))
        let transcriber = Transcriber(configuration: gemini, options: LiveTranscriptionOptions(
            vocabulary: PromptBuilder.vocabulary(configuration.dictionary),
            languageCodes: configuration.settings.languageMode.languageCodes
        ))
        await transcriber.start()
        Task.detached { await TextGenerator(configuration: gemini).warmUp(model: configuration.settings.formatterModel) }

        let chunk = 3_200 // 100 ms
        var offset = 0
        while offset < pcm.count {
            await transcriber.append(pcm.subdata(in: offset..<min(offset + chunk, pcm.count)))
            offset += chunk
            try await Task.sleep(for: .milliseconds(100))
        }

        let released = Date()
        let transcript = try await transcriber.finish()
        let transcribed = Date()

        let context = AppContext(bundleID: bundleID, appName: bundleID, host: host)
        let category = StyleResolver.category(for: context, in: configuration.categories)
        let prompt = PromptBuilder.dictation(
            transcript: transcript, category: category, dictionary: configuration.dictionary, context: context
        )
        let final = try await TextGenerator(configuration: gemini)
            .generate(model: configuration.settings.formatterModel, system: prompt.system, user: prompt.user)
        let done = Date()

        print("category:   \(category.name)")
        print("transcript: \(transcript)")
        print("final:      \(final)")
        print(String(format: "latency:    transcribe %.2fs + cleanup %.2fs = %.2fs after release",
                     transcribed.timeIntervalSince(released), done.timeIntervalSince(transcribed), done.timeIntervalSince(released)))
    }

    /// Extracts the samples of a 16 kHz mono PCM16 WAV file.
    private static func pcmData(fromWAV data: Data) throws -> Data {
        var offset = 12
        while offset + 8 <= data.count {
            let id = String(decoding: data[offset..<offset + 4], as: UTF8.self)
            let size = Int(data[offset + 4..<offset + 8].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) })
            if id == "data" { return data.subdata(in: offset + 8..<min(offset + 8 + size, data.count)) }
            offset += 8 + size + (size % 2)
        }
        throw GeminiError.invalidResponse("not a PCM WAV file")
    }
}
