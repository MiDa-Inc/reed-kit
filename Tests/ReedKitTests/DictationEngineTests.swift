import XCTest
@testable import ReedKit

@MainActor
final class DictationEngineTests: XCTestCase {
    final class MockRecorder: Recording {
        var onAutoStop: (() -> Void)?
        var silenceFloorDB: Double = -45
        var wav = Data(count: 16_000 * 2)   // 1 s of int16 @ 16 kHz
        var startError: Error?
        func start(autoStop: Bool) async throws {
            if let startError { throw startError }
        }
        func stop() -> Data { wav }
    }

    struct MockGroq: Transcribing {
        var result: Result<String, Error> = .success("raw text")
        func transcribe(wav: Data) async throws -> String { try result.get() }
    }

    struct MockCleanup: Polishing {
        var transform: (String) -> String = { "polished: \($0)" }
        func polish(transcript: String) async throws -> String { transform(transcript) }
    }

    private func makeEngine(
        recorder: MockRecorder = MockRecorder(),
        groq: MockGroq = MockGroq(),
        cleanup: MockCleanup = MockCleanup()
    ) -> DictationEngine {
        DictationEngine(
            config: DictationConfig(groqKey: "k"),
            recorder: recorder, groq: groq, cleanup: cleanup
        )
    }

    func testHappyPathPolishesAndEmitsResult() async {
        let engine = makeEngine()
        var emitted: String?
        engine.onResult = { emitted = $0 }

        await engine.start()
        XCTAssertEqual(engine.state, .recording)
        await engine.stop()
        XCTAssertEqual(engine.state, .done)
        XCTAssertEqual(engine.transcript, "polished: raw text")
        XCTAssertEqual(emitted, "polished: raw text")
    }

    func testShortTakeEndsSilentlyIdle() async {
        let recorder = MockRecorder()
        recorder.wav = Data(count: 100)   // « 0.3 s — "said nothing"
        let engine = makeEngine(recorder: recorder)
        var emitted: String?
        engine.onResult = { emitted = $0 }

        await engine.start()
        await engine.stop()
        XCTAssertEqual(engine.state, .idle)
        XCTAssertNil(emitted)
    }

    func testTranscriptionFailureSurfacesError() async {
        let engine = makeEngine(groq: MockGroq(result: .failure(DictationError.transcription("HTTP 500"))))
        await engine.start()
        await engine.stop()
        XCTAssertEqual(engine.state, .error("HTTP 500"))
    }

    func testRecorderStartFailureSurfacesError() async {
        let recorder = MockRecorder()
        recorder.startError = DictationError.micDenied
        let engine = makeEngine(recorder: recorder)
        await engine.start()
        XCTAssertEqual(engine.state, .error(DictationError.micDenied.localizedDescription))
    }

    func testStopWithoutRecordingIsANoOp() async {
        let engine = makeEngine()
        await engine.stop()
        XCTAssertEqual(engine.state, .idle)
    }

    func testStartWhileRecordingIsIgnored() async {
        let engine = makeEngine()
        await engine.start()
        await engine.start()   // second press while recording
        XCTAssertEqual(engine.state, .recording)
        await engine.stop()
        XCTAssertEqual(engine.state, .done)
    }
}
