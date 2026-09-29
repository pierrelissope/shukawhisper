import Foundation
import Observation

/// State shown by the floating pill.
@MainActor
@Observable
final class PillModel {
    enum Phase: Equatable {
        /// Resting: a small dot, or nothing if the idle indicator is off.
        case idle
        case recording
        /// Hands-free recording (double-tap). Shows a timer and buttons.
        case locked
        case processing
        case success
        case error(String)
    }

    static let barCount = 15

    var phase: Phase = .idle
    /// Audio levels, oldest first, used to draw the waveform.
    private(set) var levels = Array(repeating: Float(0), count: barCount)
    private(set) var recordingStartedAt: Date?
    /// Name of the style category or transform being applied.
    var label: String?
    var showsIdleIndicator = true

    /// Called from the lock-mode buttons.
    var onStop: (() -> Void)?
    var onCancel: (() -> Void)?

    private var smoothed: Float = 0

    func beginRecording() {
        levels = Array(repeating: 0, count: Self.barCount)
        smoothed = 0
        recordingStartedAt = Date()
        phase = .recording
    }

    /// Fast attack, slow release, so the waveform looks alive without jitter.
    func push(level: Float) {
        let factor: Float = level > smoothed ? 0.6 : 0.25
        smoothed += (level - smoothed) * factor
        levels.removeFirst()
        levels.append(smoothed)
    }
}
