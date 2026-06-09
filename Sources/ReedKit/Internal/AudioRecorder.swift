import AVFoundation
import Foundation
import QuartzCore

/// Records mic audio → 16 kHz mono 16-bit WAV (what Groq's Whisper endpoint
/// wants). Configures an AVAudioSession, taps the engine, optionally auto-stops
/// on trailing silence, and treats a too-quiet take as "said nothing".
final class AudioRecorder {
    private let engine = AVAudioEngine()
    private let bufferQueue = DispatchQueue(label: "reedkit.audio.buffer")
    private var pcmBuffer = Data()
    private var isCapturing = false
    private var converter: AVAudioConverter?

    var onAutoStop: (() -> Void)?
    private var autoStopEnabled = false
    private var autoStopFired = false
    private var heardSpeech = false
    private var lastVoiceAt: CFTimeInterval = 0
    private var startedAt: CFTimeInterval = 0
    private let speechPeak: Float = 0.03
    private let silenceSeconds: CFTimeInterval = 1.8
    private let maxSeconds: CFTimeInterval = 60

    /// Average level (dBFS) below which the take counts as silence in `stop()`.
    var silenceFloorDB: Double = -45

    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true
    )!

    func requestPermission() async -> Bool {
        await withCheckedContinuation { cont in
            AVAudioApplication.requestRecordPermission { cont.resume(returning: $0) }
        }
    }

    func start(autoStop: Bool) async throws {
        guard await requestPermission() else { throw DictationError.micDenied }

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.duckOthers, .allowBluetooth])
            try session.setActive(true)
        } catch {
            throw DictationError.audio("Audio session: \((error as NSError).domain) \((error as NSError).code)")
        }

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0 else { throw DictationError.audio("No audio input") }
        guard let conv = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw DictationError.audio("Converter unavailable")
        }
        converter = conv
        let ratio = targetFormat.sampleRate / inputFormat.sampleRate

        bufferQueue.sync {
            pcmBuffer = Data()
            isCapturing = true
            autoStopEnabled = autoStop
            autoStopFired = false
            heardSpeech = false
            lastVoiceAt = CACurrentMediaTime()
            startedAt = CACurrentMediaTime()
        }

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.handleTap(buffer, ratio: ratio, converter: conv)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            throw DictationError.audio("Engine: \((error as NSError).domain) \((error as NSError).code)")
        }
    }

    private func handleTap(_ buffer: AVAudioPCMBuffer, ratio: Double, converter conv: AVAudioConverter) {
        guard isCapturing else { return }
        let peak = inputPeak(of: buffer)
        guard let data = convertToInt16(buffer, ratio: ratio, converter: conv) else { return }
        bufferQueue.async {
            guard self.isCapturing else { return }
            self.pcmBuffer.append(data)
            self.evaluateAutoStop(peak: peak)
        }
    }

    private func inputPeak(of buffer: AVAudioPCMBuffer) -> Float {
        guard let ch0 = buffer.floatChannelData?[0] else { return 0 }
        var peak: Float = 0
        for i in 0..<Int(buffer.frameLength) where abs(ch0[i]) > peak { peak = abs(ch0[i]) }
        return peak
    }

    private func convertToInt16(_ buffer: AVAudioPCMBuffer, ratio: Double, converter conv: AVAudioConverter) -> Data? {
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 1)
        guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return nil }
        var fed = false
        var error: NSError?
        let status = conv.convert(to: out, error: &error) { _, statusPtr in
            if fed { statusPtr.pointee = .noDataNow; return nil }
            fed = true; statusPtr.pointee = .haveData; return buffer
        }
        guard status != .error, error == nil, let channel = out.int16ChannelData?[0] else { return nil }
        return Data(bytes: channel, count: Int(out.frameLength) * MemoryLayout<Int16>.size)
    }

    private func evaluateAutoStop(peak: Float) {
        guard autoStopEnabled, !autoStopFired else { return }
        let now = CACurrentMediaTime()
        if peak > speechPeak { heardSpeech = true; lastVoiceAt = now }
        let silenceEnded = heardSpeech && (now - lastVoiceAt) > silenceSeconds
        let cappedOut = (now - startedAt) > maxSeconds
        if silenceEnded || cappedOut {
            autoStopFired = true
            if let callback = onAutoStop { DispatchQueue.main.async(execute: callback) }
        }
    }

    /// Stops and returns the WAV — or **empty** Data if the take was silence.
    func stop() -> Data {
        let wasCapturing: Bool = bufferQueue.sync {
            let was = isCapturing; isCapturing = false; return was
        }
        guard wasCapturing else { return Data() }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        let pcm = bufferQueue.sync { () -> Data in let data = pcmBuffer; pcmBuffer = Data(); return data }
        if isSilent(pcm) { return Data() }
        return WAVWriter.wrap(pcm: pcm, sampleRate: 16_000, channels: 1, bitsPerSample: 16)
    }

    /// "Said nothing" guard: RMS below the floor → silence. RMS (not peak) so a
    /// stray click/breath doesn't count as speech.
    private func isSilent(_ pcm: Data) -> Bool {
        let count = pcm.count / MemoryLayout<Int16>.size
        guard count > 0 else { return true }
        var sumSquares = 0.0
        pcm.withUnsafeBytes { raw in
            guard let ptr = raw.baseAddress?.assumingMemoryBound(to: Int16.self) else { return }
            for i in 0..<count { sumSquares += Double(ptr[i]) * Double(ptr[i]) }
        }
        let rms = (sumSquares / Double(count)).squareRoot()
        let rmsDB = rms > 0 ? 20 * Foundation.log10(rms / 32768.0) : -120.0
        return rmsDB < silenceFloorDB
    }
}

enum WAVWriter {
    static func wrap(pcm: Data, sampleRate: UInt32, channels: UInt16, bitsPerSample: UInt16) -> Data {
        var data = Data()
        let byteRate = sampleRate * UInt32(channels) * UInt32(bitsPerSample / 8)
        let blockAlign = channels * (bitsPerSample / 8)
        let dataSize = UInt32(pcm.count)
        data.append(Data("RIFF".utf8)); data.append(le32(36 + dataSize)); data.append(Data("WAVE".utf8))
        data.append(Data("fmt ".utf8)); data.append(le32(16)); data.append(le16(1)); data.append(le16(channels))
        data.append(le32(sampleRate)); data.append(le32(byteRate)); data.append(le16(blockAlign)); data.append(le16(bitsPerSample))
        data.append(Data("data".utf8)); data.append(le32(dataSize)); data.append(pcm)
        return data
    }
    private static func le16(_ value: UInt16) -> Data { var le = value.littleEndian; return Data(bytes: &le, count: 2) }
    private static func le32(_ value: UInt32) -> Data { var le = value.littleEndian; return Data(bytes: &le, count: 4) }
}
