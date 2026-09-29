import Foundation

/// Wraps raw PCM samples in a minimal RIFF/WAVE container.
public enum WAVEncoder {
    public static func wav(fromPCM16 pcm: Data, sampleRate: Int, channels: Int = 1) -> Data {
        let bitsPerSample = 16
        let byteRate = sampleRate * channels * bitsPerSample / 8
        let blockAlign = channels * bitsPerSample / 8

        var header = Data()
        header.append(contentsOf: Array("RIFF".utf8))
        header.appendLittleEndian(UInt32(36 + pcm.count))
        header.append(contentsOf: Array("WAVE".utf8))
        header.append(contentsOf: Array("fmt ".utf8))
        header.appendLittleEndian(UInt32(16))            // fmt chunk size
        header.appendLittleEndian(UInt16(1))             // PCM
        header.appendLittleEndian(UInt16(channels))
        header.appendLittleEndian(UInt32(sampleRate))
        header.appendLittleEndian(UInt32(byteRate))
        header.appendLittleEndian(UInt16(blockAlign))
        header.appendLittleEndian(UInt16(bitsPerSample))
        header.append(contentsOf: Array("data".utf8))
        header.appendLittleEndian(UInt32(pcm.count))
        return header + pcm
    }
}

private extension Data {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}
