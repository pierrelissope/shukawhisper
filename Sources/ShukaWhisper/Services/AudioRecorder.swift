@preconcurrency import AVFoundation

/// Captures the default microphone as 16 kHz mono PCM16 and reports input levels.
///
/// A fresh `AVAudioEngine` is created for each recording so device changes
/// (AirPods connecting, USB mic unplugged) never leave us with a stale configuration.
final class AudioRecorder: @unchecked Sendable {
    enum RecorderError: LocalizedError {
        case noInputDevice
        case converterUnavailable

        var errorDescription: String? {
            switch self {
            case .noInputDevice: "No microphone available"
            case .converterUnavailable: "Unsupported microphone format"
            }
        }
    }

    static let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true
    )!

    private var engine: AVAudioEngine?

    /// Starts recording.
    /// - Parameters:
    ///   - onChunk: Converted audio (~20 ms per call), on the audio thread.
    ///   - onLevel: Normalized input level 0…1, on the audio thread.
    func start(
        onChunk: @escaping @Sendable (Data) -> Void,
        onLevel: @escaping @Sendable (Float) -> Void
    ) throws {
        stop()
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let inputFormat = input.inputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else { throw RecorderError.noInputDevice }
        guard let converter = AVAudioConverter(from: inputFormat, to: Self.targetFormat) else {
            throw RecorderError.converterUnavailable
        }

        let ratio = Self.targetFormat.sampleRate / inputFormat.sampleRate
        input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { buffer, _ in
            onLevel(Self.level(of: buffer))
            if let data = Self.convert(buffer, with: converter, ratio: ratio) {
                onChunk(data)
            }
        }

        engine.prepare()
        try engine.start()
        self.engine = engine
    }

    func stop() {
        guard let engine else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        self.engine = nil
    }

    // MARK: - DSP

    private static func convert(_ buffer: AVAudioPCMBuffer, with converter: AVAudioConverter, ratio: Double) -> Data? {
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return nil }

        nonisolated(unsafe) var consumed = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, output.frameLength > 0, let samples = output.int16ChannelData else { return nil }
        return Data(bytes: samples[0], count: Int(output.frameLength) * MemoryLayout<Int16>.size)
    }

    /// RMS of the first channel mapped from roughly -55 dB…-12 dB to 0…1.
    private static func level(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channel = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        let count = Int(buffer.frameLength)
        var sum: Float = 0
        for i in 0..<count { sum += channel[i] * channel[i] }
        let rms = (sum / Float(count)).squareRoot()
        let decibels = 20 * log10(max(rms, 1e-7))
        return min(1, max(0, (decibels + 55) / 43))
    }
}
