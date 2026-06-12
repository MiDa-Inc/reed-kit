import Foundation

/// Configuration for a `DictationEngine`. Two modes:
/// - **On-device keys** (default): the host supplies Groq (+ optional
///   Anthropic) keys and the pipeline runs from the device.
/// - **Backend** (`backendEndpoint` set): the recording is POSTed to a
///   reed-backend `/api/transcribe`, authenticated by `backendTokenProvider`
///   — no provider keys on the device; cleanup happens server-side.
public struct DictationConfig {
    /// reed-backend transcribe URL. Setting this selects backend mode and
    /// `groqKey`/`anthropicKey` are ignored.
    public var backendEndpoint: URL?
    /// Fresh bearer token per take (e.g. from an account session that
    /// refreshes). Required in backend mode.
    public var backendTokenProvider: (() async -> String?)?

    /// Groq API key — used for on-device speech-to-text (ignored in backend mode).
    public var groqKey: String
    /// Anthropic API key (optional) — used only to clean up the transcript.
    public var anthropicKey: String?
    /// Groq Whisper model.
    public var groqModel: String
    /// Anthropic model for cleanup.
    public var cleanupModel: String
    /// Whether to run the optional Claude cleanup pass (needs `anthropicKey`).
    public var enableCleanup: Bool
    /// Stop automatically after a trailing silence once speech is heard
    /// (good for a "tap to start" flow). Hold-to-talk leaves this off.
    public var autoStopOnSilence: Bool
    /// Recordings whose average level is below this (dBFS) are treated as silence
    /// and skipped — avoids Whisper hallucinating "Thank you." on an empty take.
    public var silenceFloorDB: Double
    /// ISO 639-1 language code ("en", "hy", "ru"); nil = Whisper auto-detect.
    /// Declaring a language also routes the per-language Whisper model and the
    /// language-aware cleanup prompt (e.g. "hy" uses whisper-large-v3, which
    /// takes precedence over `groqModel`).
    public var language: String?

    public init(
        groqKey: String = "",
        anthropicKey: String? = nil,
        groqModel: String = "whisper-large-v3-turbo",
        cleanupModel: String = "claude-haiku-4-5-20251001",
        enableCleanup: Bool = true,
        autoStopOnSilence: Bool = false,
        silenceFloorDB: Double = -45,
        language: String? = nil,
        backendEndpoint: URL? = nil,
        backendTokenProvider: (() async -> String?)? = nil
    ) {
        self.backendEndpoint = backendEndpoint
        self.backendTokenProvider = backendTokenProvider
        self.groqKey = groqKey
        self.anthropicKey = anthropicKey
        self.groqModel = groqModel
        self.cleanupModel = cleanupModel
        self.enableCleanup = enableCleanup
        self.autoStopOnSilence = autoStopOnSilence
        self.silenceFloorDB = silenceFloorDB
        self.language = language
    }
}

/// Errors surfaced by the dictation pipeline.
public enum DictationError: LocalizedError {
    case missingGroqKey
    case micDenied
    case audio(String)
    case transcription(String)

    public var errorDescription: String? {
        switch self {
        case .missingGroqKey: return "Groq API key not set."
        case .micDenied: return "Microphone permission denied."
        case .audio(let detail): return detail
        case .transcription(let detail): return detail
        }
    }
}
