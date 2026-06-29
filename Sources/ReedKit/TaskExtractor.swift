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
            // Body is bounded: a malicious or misconfigured backend echoing
            // the bearer token or PII in an error payload shouldn't poison
            // host crash reports / log aggregators. 200 chars is enough to
            // see "invalid api key" / "rate limit" / "validation error".
            let body = String(data: data, encoding: .utf8).map { String($0.prefix(200)) } ?? ""
            throw ExtractionError.http("HTTP \(http.statusCode): \(body)")
        }
        struct Resp: Decodable { let task: TaskExtraction? }
        let decoder = JSONDecoder()
        // Match snake_case server fields automatically. TaskExtraction.dueDate
        // still needs an explicit CodingKey (or this strategy) — chose the
        // strategy because it covers any future field the backend adds
        // without requiring a kit release.
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(Resp.self, from: data).task
    }

    /// Build the JSON body. Internal (not private) so tests can pin the
    /// wire shape the way the backend's tests do for its half.
    func body(transcript: String) throws -> Data {
        var payload: [String: Any] = [
            "transcript": transcript,
            // Send the client's local wall-clock date so the backend can
            // resolve relative dates ("next Friday") against it instead of
            // UTC. The backend treats this field as optional + back-compat.
            "client_today": Self.todayFormatter.string(from: Date()),
        ]
        if let language { payload["language"] = language }
        return try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    }

    /// Local-time `yyyy-MM-dd` formatter for `client_today`. POSIX locale +
    /// the current `TimeZone` so the date the model resolves against is the
    /// user's perceived "today", not UTC.
    private static let todayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

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
