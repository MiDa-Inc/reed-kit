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
    private let recorder = AudioRecorder()
    private let groq: GroqClient
    private let cleanup: CleanupClient

    public init(config: DictationConfig) {
        self.config = config
        self.groq = GroqClient(apiKey: config.groqKey, model: config.groqModel)
        self.cleanup = CleanupClient(
            apiKey: config.enableCleanup ? config.anthropicKey : nil,
            model: config.cleanupModel
        )
        recorder.silenceFloorDB = config.silenceFloorDB
        recorder.onAutoStop = { [weak self] in
            Task { @MainActor in await self?.stop() }
        }
    }

    /// Begin recording. Pair with `stop()`. (Hold-to-talk: call on press / release.)
    public func start() async {
        switch state {
        case .recording, .transcribing: return
        case .idle, .done, .error: break
        }
        transcript = ""
        do {
            try await recorder.start(autoStop: config.autoStopOnSilence)
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
