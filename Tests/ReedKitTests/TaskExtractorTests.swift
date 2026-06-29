import XCTest
@testable import ReedKit

/// Wire-shape + decode tests for [[TaskExtractor]]. Mirrors the backend's
/// `tests/test_extract.py` — if the JSON contract drifts on either side,
/// these tests fail. No real network: a custom URLProtocol intercepts
/// requests and returns canned responses.
final class TaskExtractorTests: XCTestCase {
    func testEncodesTranscriptAndOptionalLanguage() throws {
        let extractor = TaskExtractor(
            endpoint: URL(string: "https://reed.example/api/extract/task")!,
            tokenProvider: { "jwt" }
        )
        let data = try extractor.body(transcript: "create task ship it")
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["transcript"] as? String, "create task ship it")
        XCTAssertNil(json["language"])
    }

    func testEncodesLanguageWhenProvided() throws {
        let extractor = TaskExtractor(
            endpoint: URL(string: "https://reed.example/api/extract/task")!,
            tokenProvider: { "jwt" },
            language: "ru"
        )
        let data = try extractor.body(transcript: "создать задачу")
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["language"] as? String, "ru")
    }

    func testHappyPathDecodesPopulatedTask() async throws {
        let response = """
        {"task":{"title":"Write the docs","assignees":["Aram"],"tags":["launch"]}}
        """
        let extractor = makeExtractor(responseBody: response, status: 200)
        let task = try await extractor.extract(transcript: "create task write the docs assign aram tag launch")
        XCTAssertNotNil(task)
        XCTAssertEqual(task?.title, "Write the docs")
        XCTAssertEqual(task?.assignees, ["Aram"])
        XCTAssertEqual(task?.tags, ["launch"])
        XCTAssertNil(task?.priority)
    }

    func testTaskNullDecodesAsNil() async throws {
        let extractor = makeExtractor(responseBody: #"{"task":null}"#, status: 200)
        let task = try await extractor.extract(transcript: "uh hello")
        XCTAssertNil(task, "task=null in the response should surface as Swift nil")
    }

    func testMissingTokenThrowsNotSignedIn() async {
        let extractor = TaskExtractor(
            endpoint: URL(string: "https://reed.example/api/extract/task")!,
            tokenProvider: { nil }
        )
        do {
            _ = try await extractor.extract(transcript: "hello")
            XCTFail("expected an error")
        } catch let error as TaskExtractor.ExtractionError {
            if case .notSignedIn = error { /* ok */ } else {
                XCTFail("expected notSignedIn, got \(error)")
            }
        } catch {
            XCTFail("expected ExtractionError, got \(error)")
        }
    }

    func testHTTPErrorSurfacesAsExtractionError() async {
        let extractor = makeExtractor(responseBody: #"{"detail":"forbidden"}"#, status: 403)
        do {
            _ = try await extractor.extract(transcript: "hello")
            XCTFail("expected an error")
        } catch let error as TaskExtractor.ExtractionError {
            if case .http(let message) = error {
                XCTAssertTrue(message.contains("403"))
            } else {
                XCTFail("expected .http, got \(error)")
            }
        } catch {
            XCTFail("expected ExtractionError, got \(error)")
        }
    }

    // MARK: - Helpers

    private func makeExtractor(responseBody: String, status: Int) -> TaskExtractor {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        StubProtocol.next = (Data(responseBody.utf8), status)
        let session = URLSession(configuration: config)
        return TaskExtractor(
            endpoint: URL(string: "https://reed.example/api/extract/task")!,
            tokenProvider: { "jwt" },
            session: session
        )
    }
}

/// Single-shot URL protocol: returns whatever was set in `next`. Reset
/// per test by assigning before each call.
private final class StubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var next: (Data, Int)?

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let (data, status) = StubProtocol.next else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
