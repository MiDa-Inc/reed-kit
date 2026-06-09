import Foundation

/// Groq Whisper transcription — multipart POST to the OpenAI-compatible endpoint,
/// one retry on transient failures.
struct GroqClient {
    let apiKey: String
    let model: String
    private let endpoint = URL(string: "https://api.groq.com/openai/v1/audio/transcriptions")!

    func transcribe(wav: Data) async throws -> String {
        guard !apiKey.isEmpty else { throw DictationError.missingGroqKey }

        let boundary = "Boundary-\(UUID().uuidString)"
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 30
        req.httpBody = body(boundary: boundary, wav: wav)

        let (data, response) = try await sendWithRetry(req)
        guard let http = response as? HTTPURLResponse else {
            throw DictationError.transcription("No HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw DictationError.transcription("HTTP \(http.statusCode): \(String(data: data, encoding: .utf8) ?? "")")
        }
        struct Resp: Decodable { let text: String }
        let resp = try JSONDecoder().decode(Resp.self, from: data)
        return resp.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func body(boundary: String, wav: Data) -> Data {
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append(Data("--\(boundary)\r\n".utf8))
            body.append(Data("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8))
            body.append(Data("\(value)\r\n".utf8))
        }
        field("model", model)
        field("response_format", "json")
        field("temperature", "0")
        // Disfluency bias — discourages over-cleanup. NOT instructions (Whisper
        // leaks instruction text into the output).
        field("prompt", "Um, ah, like, you know, so.")
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n".utf8))
        body.append(Data("Content-Type: audio/wav\r\n\r\n".utf8))
        body.append(wav)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        return body
    }

    private func sendWithRetry(_ req: URLRequest) async throws -> (Data, URLResponse) {
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse, (500..<600).contains(http.statusCode) {
                try await Task.sleep(nanoseconds: 500_000_000)
                return try await URLSession.shared.data(for: req)
            }
            return (data, resp)
        } catch {
            try await Task.sleep(nanoseconds: 500_000_000)
            return try await URLSession.shared.data(for: req)
        }
    }
}
