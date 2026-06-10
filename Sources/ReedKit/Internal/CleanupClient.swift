import Foundation

/// Optional Anthropic cleanup of a raw transcript (punctuation, casing, filler
/// removal). Returns the input unchanged if no key is set.
struct CleanupClient {
    let apiKey: String?
    let model: String
    /// ISO 639-1 code, or nil — selects the language-aware cleanup prompt.
    let language: String?
    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    private var systemPrompt: String { LanguageSupport.cleanupPrompt(language: language) }

    func polish(transcript: String) async throws -> String {
        guard let apiKey, !apiKey.isEmpty else { return transcript }

        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 30

        let payload: [String: Any] = [
            "model": model,
            "max_tokens": 2048,
            "system": [["type": "text", "text": systemPrompt, "cache_control": ["type": "ephemeral"]]],
            "messages": [["role": "user", "content": "Transcript:\n\(transcript)"]],
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            return transcript   // cleanup is best-effort; fall back to the raw transcript
        }
        struct Block: Decodable { let type: String; let text: String? }
        struct Resp: Decodable { let content: [Block] }
        let resp = try JSONDecoder().decode(Resp.self, from: data)
        let cleaned = resp.content.compactMap { $0.type == "text" ? $0.text : nil }
            .joined().trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? transcript : cleaned
    }
}
