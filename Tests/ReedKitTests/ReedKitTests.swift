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
        XCTAssertNil(config.language)   // auto-detect by default
    }

    func testLanguageModelRouting() {
        XCTAssertEqual(LanguageSupport.modelByLanguage["hy"], "whisper-large-v3")
        XCTAssertNil(LanguageSupport.modelByLanguage["ru"])   // ru verified fine on turbo
        XCTAssertNil(LanguageSupport.modelByLanguage["en"])
    }

    func testCleanupPromptVariants() {
        XCTAssertTrue(LanguageSupport.cleanupPrompt(language: "hy").contains("։"))
        XCTAssertTrue(LanguageSupport.cleanupPrompt(language: "ru").contains("как бы"))
        XCTAssertTrue(LanguageSupport.cleanupPrompt(language: "en").contains("um, uh"))
        for language in ["en", "hy", "ru", nil] {
            XCTAssertTrue(LanguageSupport.cleanupPrompt(language: language).contains("NEVER translate"))
        }
        XCTAssertTrue(LanguageSupport.cleanupPrompt(language: nil)
            .contains("equivalents in the transcript's language"))
    }

    func testWhisperPromptsPerLanguage() {
        XCTAssertEqual(LanguageSupport.promptByLanguage["en"], "Um, ah, like, you know, so.")
        XCTAssertTrue(LanguageSupport.promptByLanguage["ru"]?.contains("как бы") ?? false)
        XCTAssertTrue(LanguageSupport.promptByLanguage["hy"]?.contains("դե") ?? false)
    }
}
