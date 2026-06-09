import XCTest
@testable import ReedKit

final class ReedKitTests: XCTestCase {
    func testWavHeaderAndSize() {
        let pcm = Data(count: 320)   // 160 int16 samples
        let wav = WAVWriter.wrap(pcm: pcm, sampleRate: 16_000, channels: 1, bitsPerSample: 16)
        XCTAssertEqual(Array(wav.prefix(4)), Array("RIFF".utf8))
        XCTAssertEqual(wav.count, 44 + pcm.count)   // 44-byte header
    }

    func testConfigDefaults() {
        let config = DictationConfig(groqKey: "k")
        XCTAssertEqual(config.groqModel, "whisper-large-v3-turbo")
        XCTAssertTrue(config.enableCleanup)
        XCTAssertNil(config.anthropicKey)
        XCTAssertEqual(config.silenceFloorDB, -45)
        XCTAssertFalse(config.autoStopOnSilence)
    }
}
