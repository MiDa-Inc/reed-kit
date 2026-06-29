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

    func testEncodesClientTodayInLocalTime() throws {
        // The kit always sends client_today so the backend can resolve
        // relative dates against the user's wall clock. Format pinned: the
        // server's regex is ^\d{4}-\d{2}-\d{2}$.
        let extractor = TaskExtractor(
            endpoint: URL(string: "https://reed.example/api/extract/task")!,
            tokenProvider: { "jwt" }
        )
        let data = try extractor.body(transcript: "x")
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let today = try XCTUnwrap(json["client_today"] as? String)
        XCTAssertNotNil(today.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression),
                        "client_today must match YYYY-MM-DD, got: \(today)")
    }

    func testEmptyTranscriptReturnsNilWithoutHittingNetwork() async throws {
        // No request should leave the device for an empty/whitespace input —
        // the extractor early-returns nil before any URLSession call. Using a
        // tokenProvider that fatalErrors would catch a regression here.
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        StubProtocol.next = nil  // would crash if a request actually fires
        let extractor = TaskExtractor(
            endpoint: URL(string: "https://reed.example/api/extract/task")!,
            tokenProvider: { "jwt" },
            session: URLSession(configuration: config)
        )

        let empty = try await extractor.extract(transcript: "")
        XCTAssertNil(empty)
        let whitespace = try await extractor.extract(transcript: "   \n\t  ")
        XCTAssertNil(whitespace)
    }

    func testMalformedJSONBodyThrows() async {
        // A truncated/garbage JSON body must throw rather than silently
        // turning into TaskExtraction(nil). Any decode failure is real
        // operator information; swallowing it would hide schema drift.
        let extractor = makeExtractor(responseBody: #"{"task":"#, status: 200)
        do {
            _ = try await extractor.extract(transcript: "hello")
            XCTFail("expected a decode error")
        } catch is DecodingError {
            // ok — the JSONDecoder raised a structured error
        } catch {
            XCTFail("expected DecodingError, got \(type(of: error)): \(error)")
        }
    }

    func testHTTPErrorMessageIsTruncated() async {
        // A backend echoing a huge body in an error payload must not poison
        // host logs. 200-char cap on the body in the error string.
        let huge = String(repeating: "x", count: 5_000)
        let extractor = makeExtractor(responseBody: huge, status: 500)
        do {
            _ = try await extractor.extract(transcript: "hello")
            XCTFail("expected an error")
        } catch let error as TaskExtractor.ExtractionError {
            if case .http(let message) = error {
                // Status line + at most 200 chars of body + a few formatting chars.
                XCTAssertLessThan(message.count, 260,
                                  "error message must be bounded; got \(message.count) chars")
                XCTAssertTrue(message.contains("500"), "status code must be present")
            } else {
                XCTFail("expected .http, got \(error)")
            }
        } catch {
            XCTFail("expected ExtractionError, got \(error)")
        }
    }

    func testDecoderSurvivesUnknownSnakeCaseField() async throws {
        // Defends the .convertFromSnakeCase decoder strategy: a future
        // backend field (here: "completion_eta") that the kit doesn't yet
        // know about must not break decoding of the fields it does know.
        let response = """
        {"task":{"title":"Ship","completion_eta":"2026-12-01","due_date":"2026-07-04"}}
        """
        let extractor = makeExtractor(responseBody: response, status: 200)
        let task = try await extractor.extract(transcript: "create task ship by July 4")
        XCTAssertEqual(task?.title, "Ship")
        XCTAssertEqual(task?.dueDate, "2026-07-04")
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
