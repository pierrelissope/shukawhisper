import Foundation

/// Interprets presses of the dictation key (`Fn`) as push-to-talk gestures.
///
/// - **Hold** the key, speak, release → dictation is processed.
/// - **Double-tap** → hands-free mode; the next press finishes.
/// - A **single short tap**, or using the key as a modifier (`Fn` + another key), cancels silently.
/// - **Esc** cancels at any time.
///
/// Recording starts on the very first press so no speech is lost while we find out
/// which gesture the user is making. This type is pure logic: the caller feeds it
/// timestamped inputs and performs the returned actions.
public struct PushToTalkGesture: Sendable {
    public enum Input: Sendable, Equatable {
        case keyDown(at: TimeInterval)
        case keyUp(at: TimeInterval)
        /// Any other key pressed while the dictation key is involved.
        case otherKey
        case escape
        /// The caller's timer fired after a `.scheduleTapTimeout` action.
        case tapTimeout
    }

    public enum Action: Sendable, Equatable {
        case startRecording
        /// Switch the UI to hands-free mode; recording continues.
        case lock
        case finish
        case cancel
        /// Call back with `.tapTimeout` after this delay unless another input arrives first.
        case scheduleTapTimeout(TimeInterval)
    }

    public enum State: Sendable, Equatable {
        case idle
        case holding(since: TimeInterval)
        case awaitingSecondTap
        case locked
    }

    /// Presses shorter than this count as taps.
    public var tapThreshold: TimeInterval = 0.3
    /// Maximum gap between the two taps of a double-tap.
    public var doubleTapWindow: TimeInterval = 0.35

    public private(set) var state: State = .idle

    public init() {}

    public mutating func handle(_ input: Input) -> [Action] {
        switch (state, input) {
        case let (.idle, .keyDown(time)):
            state = .holding(since: time)
            return [.startRecording]

        case let (.holding(since), .keyUp(time)):
            if time - since < tapThreshold {
                state = .awaitingSecondTap
                return [.scheduleTapTimeout(doubleTapWindow)]
            }
            state = .idle
            return [.finish]

        case (.awaitingSecondTap, .keyDown):
            state = .locked
            return [.lock]

        case (.awaitingSecondTap, .tapTimeout),
             (.awaitingSecondTap, .otherKey),
             (.holding, .otherKey):
            state = .idle
            return [.cancel]

        case (.locked, .keyDown):
            state = .idle
            return [.finish]

        case (.idle, .escape):
            return []

        case (_, .escape):
            state = .idle
            return [.cancel]

        default:
            // e.g. key-up after the locking tap, other keys while hands-free, stale timeouts.
            return []
        }
    }

    /// Forces the gesture back to idle (e.g. when the session ends because of an error).
    public mutating func reset() {
        state = .idle
    }
}
