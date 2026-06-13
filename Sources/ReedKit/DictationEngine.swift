import Foundation

/// The public entry point: drives record → transcribe (Groq) → optional cleanup
/// (Claude) and publishes state + the resulting text. Use it directly, or hand it
/// to `HoldToTalkButton` for a ready-made tap-and-hold UI.
///
/// ```swift
/// let engine = DictationEngine(config: .init(groqKey: "gsk_…", anthropicKey: "sk-ant-…"))
/// engine.onResult = { text in /* insert text */ }
/// // SwiftUI: HoldToTalkButton(engine: engine)
/// // or programmatically: await engine.start() ... await engine.stop()
/// ```
@MainActor
public final class DictationEngine: ObservableObject {
    public enum State: Equatable {
        case idle, recording, transcribing, done, error(String)
    }

    @Published public private(set) var state: State = .idle
    @Published public private(set) var transcript: String = ""

    /// Called with the final polished text when a dictation completes.
    public var onResult: ((String) -> Void)?

    private let config: DictationConfig
    private let recorder: Recording
    private let groq: Transcribing
    private let cleanup: Polishing

    public convenience init(config: DictationConfig) {
        let transcriber: Transcribing
        let polisher: Polishing
        if let endpoint = config.backendEndpoint {
            // Backend mode: the server owns the keys, the spec, and cleanup.
            transcriber = BackendClient(
                endpoint: endpoint,
                tokenProvider: config.backendTokenProvider ?? { nil },
                language: config.language
            )
            polisher = NoopPolisher()
        } else {
            let model = config.language.flatMap { LanguageSupport.modelByLanguage[$0] }
                ?? config.groqModel
            transcriber = GroqClient(apiKey: config.groqKey, model: model,
                                     language: config.language)
            polisher = CleanupClient(
                apiKey: config.enableCleanup ? config.anthropicKey : nil,
                model: config.cleanupModel,
                language: config.language
            )
        }
        self.init(config: config, recorder: AudioRecorder(), groq: transcriber, cleanup: polisher)
    }

    /// Injection seam for tests; production goes through `init(config:)`.
    init(config: DictationConfig, recorder: Recording, groq: Transcribing, cleanup: Polishing) {
        self.config = config
        self.recorder = recorder
        self.groq = groq
        self.cleanup = cleanup
        recorder.silenceFloorDB = config.silenceFloorDB
        recorder.onAutoStop = { [weak self] in
            Task { @MainActor in await self?.stop() }
        }
    }

    /// Begin recording. Pair with `stop()`. (Hold-to-talk: call on press / release.)
    /// - Parameter autoStopOnSilence: overrides `config.autoStopOnSilence` for this
    ///   take — e.g. `false` for hold-to-talk, `true` for a hands-free "tap to start".
    public func start(autoStopOnSilence: Bool? = nil) async {
        switch state {
        case .recording, .transcribing: return
        case .idle, .done, .error: break
        }
        transcript = ""
        do {
            try await recorder.start(autoStop: autoStopOnSilence ?? config.autoStopOnSilence)
            state = .recording
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    /// Stop recording and run the pipeline. If nothing was said, ends silently
    /// (state returns to `.idle`, no result emitted).
    public func stop() async {
        guard state == .recording else { return }
        state = .transcribing

        let wav = recorder.stop()
        guard wav.count > Int(16_000 * 2 * 0.3) else {   // < ~0.3s or silence → nothing
            state = .idle
            return
        }
        do {
            let raw = try await groq.transcribe(wav: wav)
            let polished = try await cleanup.polish(transcript: raw)
            transcript = polished
            state = .done
            onResult?(polished)
        } catch {
            state = .error(error.localizedDescription)
        }
    }
}
