import Foundation

/// The backend transport ("option b" of the Reed architecture): instead of
/// calling Groq/Claude with on-device keys, POST the recorded WAV to a
/// reed-backend `/api/transcribe`, authenticated by the host's account token.
/// The backend owns the provider keys and the cleanup spec.
struct BackendClient: Transcribing {
    let endpoint: URL
    /// Fresh bearer token per request — hosts hand a provider so a session
    /// can refresh between takes.
    let tokenProvider: () async -> String?
    let language: String?

    func transcribe(wav: Data) async throws -> String {
        guard let token = await tokenProvider(), !token.isEmpty else {
            throw DictationError.transcription("Not signed in.")
        }
        let boundary = "Boundary-\(UUID().uuidString)"
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 60
        req.httpBody = body(boundary: boundary, wav: wav)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw DictationError.transcription("No HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw DictationError.transcription(
                "HTTP \(http.statusCode): \(String(data: data, encoding: .utf8) ?? "")")
        }
        struct Resp: Decodable { let text: String }
        let resp = try JSONDecoder().decode(Resp.self, from: data)
        return resp.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // Internal (not private) so tests can pin the request shape.
    func body(boundary: String, wav: Data) -> Data {
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append(Data("--\(boundary)\r\n".utf8))
            body.append(Data("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8))
            body.append(Data("\(value)\r\n".utf8))
        }
        // Cleanup runs server-side (the backend IS the spec).
        field("cleanup", "true")
        if let language {
            field("language", language)
        }
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n".utf8))
        body.append(Data("Content-Type: audio/wav\r\n\r\n".utf8))
        body.append(wav)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        return body
    }
}
