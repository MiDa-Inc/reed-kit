import Foundation

/// Configuration for a `DictationEngine`. The host app supplies its own API keys.
public struct DictationConfig {
    /// Groq API key (required) — used for speech-to-text.
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

    public init(
        groqKey: String,
        anthropicKey: String? = nil,
        groqModel: String = "whisper-large-v3-turbo",
        cleanupModel: String = "claude-haiku-4-5-20251001",
        enableCleanup: Bool = true,
        autoStopOnSilence: Bool = false,
        silenceFloorDB: Double = -45
    ) {
        self.groqKey = groqKey
        self.anthropicKey = anthropicKey
        self.groqModel = groqModel
        self.cleanupModel = cleanupModel
        self.enableCleanup = enableCleanup
        self.autoStopOnSilence = autoStopOnSilence
        self.silenceFloorDB = silenceFloorDB
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
