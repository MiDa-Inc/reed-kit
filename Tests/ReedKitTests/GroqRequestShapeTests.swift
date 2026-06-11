import XCTest
@testable import ReedKit

/// Pins the multipart request shape per language. This mirrors reed-backend's
/// adapter — the source of truth for cross-client parity — so a change here
/// or there that isn't made in both places fails loudly.
final class GroqRequestShapeTests: XCTestCase {
    private func bodyString(language: String?, model: String) -> String {
        let client = GroqClient(apiKey: "k", model: model, language: language)
        return String(decoding: client.body(boundary: "B", wav: Data([0x01])), as: UTF8.self)
    }

    private func field(_ name: String, _ value: String) -> String {
        "Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n"
    }

    func testArmenianRequest() {
        let body = bodyString(language: "hy", model: "whisper-large-v3")
        XCTAssertTrue(body.contains(field("model", "whisper-large-v3")))
        XCTAssertTrue(body.contains(field("language", "hy")))
        XCTAssertTrue(body.contains("դե"))                       // Armenian fillers
        XCTAssertFalse(body.contains("Um, ah"))                  // never the English prompt
    }

    func testEnglishRequest() {
        let body = bodyString(language: "en", model: "whisper-large-v3-turbo")
        XCTAssertTrue(body.contains(field("language", "en")))
        XCTAssertTrue(body.contains(field("prompt", "Um, ah, like, you know, so.")))
    }

    func testAutoDetectSendsNeitherLanguageNorPrompt() {
        let body = bodyString(language: nil, model: "whisper-large-v3-turbo")
        XCTAssertFalse(body.contains("name=\"language\""))
        XCTAssertFalse(body.contains("name=\"prompt\""))         // would bias detection
        XCTAssertTrue(body.contains(field("response_format", "json")))
    }
}
