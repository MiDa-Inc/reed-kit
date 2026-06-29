import Foundation

/// Calls reed-backend's `POST /api/extract/task` and returns a structured
/// [[TaskExtraction]] (or nil when the transcript wasn't task-shaped).
///
/// Decoupled from `DictationEngine` on purpose: a host that wants the
/// pipeline (mic → transcript → task JSON) keeps using DictationEngine
/// for the audio half and hands the result here. A host that already
/// has a transcript from elsewhere (web app, share extension) doesn't
/// pay for audio plumbing it doesn't need.
///
/// Backend-only: this endpoint lives on the kit's backend, never on the
/// device. Hosts in fully on-device mode (no `backendEndpoint` configured)
/// have no extractor; the feature is only meaningful for hosts already
/// signed into a Reed account.
public struct TaskExtractor: Sendable {
    /// Full URL of the backend endpoint, including the `/api/extract/task`
    /// path. Hand a URL rather than a host string so the kit doesn't have
    /// to encode backend path conventions twice.
    public let endpoint: URL

    /// Fresh bearer token per call — matches the BackendClient pattern so a
    /// session that refreshes between requests doesn't surprise us with a
    /// stale token.
    public let tokenProvider: @Sendable () async -> String?

    /// Optional language hint passed through to the server; the model uses
    /// it to preserve the transcript's language in the extracted fields.
    public let language: String?

    /// `URLSession` injection point. Default = `.shared`; tests pass a
    /// session wired to a custom URLProtocol so they never hit the network.
    public let session: URLSession

    public init(
        endpoint: URL,
        tokenProvider: @escaping @Sendable () async -> String?,
        language: String? = nil,
        session: URLSession = .shared
    ) {
        self.endpoint = endpoint
        self.tokenProvider = tokenProvider
        self.language = language
        self.session = session
    }

    /// Extract a task from `transcript`. Returns nil when the backend
    /// signals task=null (transcript not task-shaped, or extraction was
    /// bypassed server-side). Throws on auth/transport/HTTP errors so
    /// hosts can show a real failure rather than silently dropping the
    /// dictation.
    public func extract(transcript: String) async throws -> TaskExtraction? {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let token = await tokenProvider(), !token.isEmpty else {
            throw ExtractionError.notSignedIn
        }
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 60
        req.httpBody = try body(transcript: transcript)

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw ExtractionError.http("No HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw ExtractionError.http(
                "HTTP \(http.statusCode): \(String(data: data, encoding: .utf8) ?? "")"
            )
        }
        struct Resp: Decodable { let task: TaskExtraction? }
        return try JSONDecoder().decode(Resp.self, from: data).task
    }

    /// Build the JSON body. Internal (not private) so tests can pin the
    /// wire shape the way the backend's tests do for its half.
    func body(transcript: String) throws -> Data {
        var payload: [String: Any] = ["transcript": transcript]
        if let language { payload["language"] = language }
        return try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    }

    public enum ExtractionError: LocalizedError {
        case notSignedIn
        case http(String)

        public var errorDescription: String? {
            switch self {
            case .notSignedIn: return "Not signed in."
            case .http(let detail): return detail
            }
        }
    }
}
