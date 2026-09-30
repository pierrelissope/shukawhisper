import AppKit
import GeminiKit
import ShukaCore

/// Runs dictations and transforms end to end:
/// hotkey → record → transcribe → clean up / rewrite → insert → history.
@MainActor
final class SessionController {
    private unowned let app: AppModel
    private var gesture = PushToTalkGesture()
    private var recording: Recording?
    /// Transcription / generation in flight after recording stopped (or a keyboard transform).
    private var work: Task<Void, Never>?
    private var tapTimeout: Task<Void, Never>?
    private var hidePill: Task<Void, Never>?

    private var pill: PillModel { app.pill }
    private var configuration: Configuration { app.configuration }
    private var settings: AppSettings { app.settings }

    /// Recordings shorter than this are treated as accidental presses.
    private let minimumDuration: TimeInterval = 0.35

    init(app: AppModel) {
        self.app = app
        pill.onStop = { [weak self] in
            self?.gesture.reset()
            self?.finishRecording()
        }
        pill.onCancel = { [weak self] in
            self?.gesture.reset()
            self?.cancelRecording()
        }
    }

    var isBusy: Bool { recording != nil || work != nil }

    // MARK: - Input

    func handle(_ event: HotkeyMonitor.Event) {
        switch event {
        case let .dictationKey(isDown, time):
            apply(gesture.handle(isDown ? .keyDown(at: time) : .keyUp(at: time)))
        case .otherKeyWhileDictating:
            apply(gesture.handle(.otherKey))
        case .escape:
            if recording?.purpose == .voiceTransform {
                cancelRecording()
            } else if recording != nil {
                apply(gesture.handle(.escape))
            } else if let work {
                work.cancel()
                self.work = nil
                endSession(showing: .idle)
            }
        case let .transform(slot):
            runTransform(slot: slot)
        case let .voiceTransform(isDown):
            if isDown {
                startRecording(.voiceTransform)
            } else if recording?.purpose == .voiceTransform {
                finishRecording()
            }
        }
    }

    private func apply(_ actions: [PushToTalkGesture.Action]) {
        for action in actions {
            switch action {
            case .startRecording:
                startRecording(.dictation)
            case .lock:
                pill.phase = .locked
            case .finish:
                finishRecording()
            case .cancel:
                cancelRecording()
            case let .scheduleTapTimeout(delay):
                tapTimeout?.cancel()
                tapTimeout = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(delay))
                    guard !Task.isCancelled, let self else { return }
                    self.apply(self.gesture.handle(.tapTimeout))
                }
            }
        }
    }

    // MARK: - Recording

    private func startRecording(_ purpose: Recording.Purpose) {
        guard !isBusy else {
            if purpose == .dictation { gesture.reset() }
            return
        }
        guard let gemini = app.gemini else {
            gesture.reset()
            showError("Add your Gemini API key")
            app.showMainWindow()
            return
        }
        guard Permissions.microphoneGranted else {
            gesture.reset()
            showError("Microphone access needed")
            app.showMainWindow()
            return
        }

        let snapshot = ContextProvider.frontmostApp()
        let transcriber = Transcriber(
            configuration: gemini,
            options: LiveTranscriptionOptions(
                vocabulary: PromptBuilder.vocabulary(configuration.dictionary),
                languageCodes: settings.languageMode.languageCodes
            )
        )
        let recording = Recording(
            purpose: purpose,
            transcriber: transcriber,
            context: Task { await ContextProvider.resolveHost(for: snapshot) },
            selection: purpose == .voiceTransform ? Task { await TextInserter.selectedText() } : nil
        )

        let pill = self.pill
        do {
            try recording.recorder.start(
                onChunk: { [continuation = recording.chunks] in continuation.yield($0) },
                onLevel: { level in Task { @MainActor in pill.push(level: level) } }
            )
        } catch {
            recording.chunks.finish()
            gesture.reset()
            showError(error.localizedDescription)
            return
        }

        self.recording = recording
        let model = purpose == .dictation ? settings.formatterModel : settings.transformModel
        Task.detached { await TextGenerator(configuration: gemini).warmUp(model: model) }
        hidePill?.cancel()
        pill.label = purpose == .voiceTransform
            ? "Voice edit"
            : StyleResolver.category(for: snapshot, in: configuration.categories).name
        pill.beginRecording()
        app.hotkeys.interceptsEscape = true
        SoundPlayer.play(.start, enabled: settings.playSounds)

        if purpose == .dictation {
            // Refine the label once the browser tab is known (e.g. Chrome → Email).
            Task { [weak self] in
                let context = await recording.context.value
                guard let self, self.recording === recording else { return }
                self.pill.label = StyleResolver.category(for: context, in: self.configuration.categories).name
            }
        }
    }

    private func finishRecording() {
        guard let recording else { return }
        self.recording = nil
        tapTimeout?.cancel()
        recording.stop()

        guard recording.duration >= minimumDuration else {
            Task { await recording.transcriber.cancel() }
            endSession(showing: .idle)
            return
        }

        pill.phase = .processing
        SoundPlayer.play(.stop, enabled: settings.playSounds)
        work = Task { [weak self] in
            await self?.process(recording)
            self?.work = nil
        }
    }

    private func cancelRecording() {
        tapTimeout?.cancel()
        guard let recording else { return }
        self.recording = nil
        recording.stop()
        Task { await recording.transcriber.cancel() }
        endSession(showing: .idle)
    }

    // MARK: - Processing

    private func process(_ recording: Recording) async {
        let releasedAt = Date()
        do {
            await recording.pump.value
            let transcript = try await recording.transcriber.finish()
            try Task.checkCancellation()
            guard !transcript.isEmpty else { throw SessionError.nothingHeard }
            let context = await recording.context.value

            switch recording.purpose {
            case .dictation:
                let category = StyleResolver.category(for: context, in: configuration.categories)
                let text = try await cleanUp(transcript, category: category, context: context)
                try Task.checkCancellation()
                await TextInserter.insert(text, restoreClipboard: settings.restoreClipboard)
                app.record(HistoryEntry(
                    kind: .dictation, rawText: transcript, finalText: text,
                    appName: context.appName, bundleID: context.bundleID, label: category.name,
                    audioDuration: recording.duration, latency: Date().timeIntervalSince(releasedAt)
                ))

            case .voiceTransform:
                let selection = await recording.selection?.value
                let prompt = PromptBuilder.voiceTransform(
                    instruction: transcript, selection: selection, dictionary: configuration.dictionary
                )
                let text = try await generate(prompt, model: settings.transformModel)
                try Task.checkCancellation()
                await TextInserter.insert(text, restoreClipboard: settings.restoreClipboard)
                app.record(HistoryEntry(
                    kind: .voiceTransform, rawText: selection ?? "", finalText: text,
                    appName: context.appName, bundleID: context.bundleID, label: transcript,
                    audioDuration: recording.duration, latency: Date().timeIntervalSince(releasedAt)
                ))
            }
            endSession(showing: .success)
        } catch is CancellationError {
            endSession(showing: .idle)
        } catch {
            endSession(showing: .error(Self.message(for: error)))
        }
    }

    /// Applies the style category. Falls back to the raw transcript if the formatter fails,
    /// so a flaky network never loses a dictation.
    private func cleanUp(_ transcript: String, category: StyleCategory, context: AppContext) async throws -> String {
        guard settings.cleanupEnabled else { return transcript }
        let prompt = PromptBuilder.dictation(
            transcript: transcript, category: category, dictionary: configuration.dictionary, context: context
        )
        do {
            let text = try await generate(prompt, model: settings.formatterModel)
            // Guard against the model answering the dictated text instead of formatting it.
            if text.count > transcript.count * 2 + 80 { return transcript }
            return text
        } catch GeminiError.emptyResult {
            throw SessionError.nothingHeard
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            Log.info("cleanup failed (\(error.localizedDescription)); inserting raw transcript")
            return transcript
        }
    }

    // MARK: - Keyboard transforms

    private func runTransform(slot: Int) {
        guard !isBusy else { return }
        guard app.gemini != nil else {
            showError("Add your Gemini API key")
            return
        }
        guard let transform = configuration.transform(inSlot: slot) else {
            showError("Nothing assigned to \(settings.transformModifier.label(slot: slot))")
            return
        }
        hidePill?.cancel()
        pill.label = transform.name
        pill.phase = .processing
        app.hotkeys.interceptsEscape = true
        let context = ContextProvider.frontmostApp()

        work = Task { [weak self] in
            guard let self else { return }
            defer { self.work = nil }
            let started = Date()
            do {
                guard let selection = await TextInserter.selectedText(),
                      !selection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                else { throw SessionError.noSelection }
                let prompt = PromptBuilder.transform(transform, text: selection, dictionary: self.configuration.dictionary)
                let text = try await self.generate(prompt, model: self.settings.transformModel)
                try Task.checkCancellation()
                await TextInserter.insert(text, restoreClipboard: self.settings.restoreClipboard)
                self.app.record(HistoryEntry(
                    kind: .transform, rawText: selection, finalText: text,
                    appName: context.appName, bundleID: context.bundleID, label: transform.name,
                    latency: Date().timeIntervalSince(started)
                ))
                self.endSession(showing: .success)
            } catch is CancellationError {
                self.endSession(showing: .idle)
            } catch {
                self.endSession(showing: .error(Self.message(for: error)))
            }
        }
    }

    // MARK: - Helpers

    private func generate(_ prompt: Prompt, model: String) async throws -> String {
        guard let gemini = app.gemini else { throw SessionError.missingKey }
        let text = try await TextGenerator(configuration: gemini)
            .generate(model: model, system: prompt.system, user: prompt.user)
        return Self.stripWrapperTags(text)
    }

    /// Models occasionally echo the XML-ish wrappers used in prompts.
    static func stripWrapperTags(_ text: String) -> String {
        var result = text
        for tag in ["transcript", "text"] {
            result = result.replacingOccurrences(of: "<\(tag)>", with: "")
                .replacingOccurrences(of: "</\(tag)>", with: "")
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func endSession(showing phase: PillModel.Phase) {
        app.hotkeys.interceptsEscape = false
        hidePill?.cancel()
        pill.phase = phase
        switch phase {
        case .success:
            scheduleHide(after: 0.9)
        case .error:
            SoundPlayer.play(.error, enabled: settings.playSounds)
            scheduleHide(after: 2.8)
        default:
            break
        }
    }

    private func showError(_ message: String) {
        endSession(showing: .error(message))
    }

    private func scheduleHide(after seconds: TimeInterval) {
        hidePill = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self, !self.isBusy else { return }
            self.pill.phase = .idle
        }
    }

    private static func message(for error: Error) -> String {
        if let error = error as? URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost: return "No internet connection"
            case .timedOut: return "Gemini timed out"
            default: break
            }
        }
        return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}

// MARK: - Supporting types

enum SessionError: LocalizedError {
    case nothingHeard, noSelection, missingKey

    var errorDescription: String? {
        switch self {
        case .nothingHeard: "Didn't catch that"
        case .noSelection: "Select some text first"
        case .missingKey: "Add your Gemini API key"
        }
    }
}

/// Everything belonging to one in-progress recording.
@MainActor
private final class Recording {
    enum Purpose { case dictation, voiceTransform }

    let purpose: Purpose
    let transcriber: Transcriber
    let recorder = AudioRecorder()
    let startedAt = Date()
    let context: Task<AppContext, Never>
    let selection: Task<String?, Never>?
    let chunks: AsyncStream<Data>.Continuation
    /// Forwards audio to the transcriber in order, in ~100 ms batches.
    let pump: Task<Void, Never>
    private(set) var duration: TimeInterval = 0

    init(purpose: Purpose, transcriber: Transcriber, context: Task<AppContext, Never>, selection: Task<String?, Never>?) {
        self.purpose = purpose
        self.transcriber = transcriber
        self.context = context
        self.selection = selection
        let (stream, continuation) = AsyncStream.makeStream(of: Data.self)
        self.chunks = continuation
        self.pump = Task {
            await transcriber.start()
            var batch = Data()
            for await chunk in stream {
                batch.append(chunk)
                if batch.count >= 3_200 {
                    await transcriber.append(batch)
                    batch.removeAll(keepingCapacity: true)
                }
            }
            if !batch.isEmpty { await transcriber.append(batch) }
        }
    }

    func stop() {
        recorder.stop()
        chunks.finish()
        duration = Date().timeIntervalSince(startedAt)
    }
}
