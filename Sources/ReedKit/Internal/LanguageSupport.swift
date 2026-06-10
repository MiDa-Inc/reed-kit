import Foundation

/// The language spec — mirrors reed-backend's adapters (the source of truth
/// for dictation behavior across Reed clients). Keep the maps and the cleanup
/// prompt in sync with the backend until hosts switch to backend mode, at
/// which point this file goes away.
enum LanguageSupport {
    /// Languages a host may declare. `nil` (auto-detect) is always allowed.
    static let supported: Set<String> = ["en", "hy", "ru"]

    /// Per-language Whisper model routing. Languages not listed use the
    /// config's `groqModel`. hy: full large-v3 — turbo is documented weaker
    /// on low-resource languages. Same API key either way.
    static let modelByLanguage = ["hy": "whisper-large-v3"]

    /// Disfluency bias per language — NOT instructions (Whisper leaks
    /// instruction text). Auto-detect sends no prompt: an English prompt
    /// biases detection on non-English takes.
    static let promptByLanguage = [
        "en": "Um, ah, like, you know, so.",
        "ru": "Э-э, ну, как бы, значит.",
        "hy": "Էէ, դե, ոնց որ, էլի.",
    ]

    /// The cleanup spec, built per language: same rules everywhere, native
    /// filler examples and punctuation conventions where they differ. The
    /// never-translate rule is load-bearing.
    static func cleanupPrompt(language: String?) -> String {
        let (fillers, punctuation): (String, String)
        switch language {
        case "en": (fillers, punctuation) = ("(um, uh, like, you know)", "")
        case "ru": (fillers, punctuation) = ("(э-э, ну, как бы, значит, короче)", "")
        case "hy": (fillers, punctuation) = (
            "(էէ, դե, ոնց որ, էլի)",
            "; use Armenian punctuation conventions (։ for full stop, ՞ for questions)"
        )
        default: (fillers, punctuation) = (
            "(um, uh — or their equivalents in the transcript's language)", ""
        )
        }
        return """
        You are a transcription cleaner. The input is raw speech-to-text from a dictation session.
        Return only the cleaned written version of the same content:
        - write in the same language as the transcript — NEVER translate or switch languages
        - remove filler words \(fillers)
        - resolve self-corrections ("Tuesday wait Wednesday" -> "Wednesday")
        - add appropriate punctuation and casing\(punctuation)
        - preserve technical terms, code identifiers, and proper nouns exactly
        - keep the user's voice, meaning, and length unchanged
        Return only the cleaned text. No preamble, no explanation, no surrounding quotes.
        """
    }
}
