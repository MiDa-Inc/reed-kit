import Foundation

/// Seams for testing `DictationEngine` without hardware or network.
/// Production conformers: `AudioRecorder`, `GroqClient`, `CleanupClient`.

protocol Recording: AnyObject {
    var onAutoStop: (() -> Void)? { get set }
    var silenceFloorDB: Double { get set }
    func start(autoStop: Bool) async throws
    func stop() -> Data
}

protocol Transcribing {
    func transcribe(wav: Data) async throws -> String
}

protocol Polishing {
    func polish(transcript: String) async throws -> String
}

extension AudioRecorder: Recording {}
extension GroqClient: Transcribing {}
extension CleanupClient: Polishing {}

/// Backend mode: cleanup already happened server-side.
struct NoopPolisher: Polishing {
    func polish(transcript: String) async throws -> String { transcript }
}
