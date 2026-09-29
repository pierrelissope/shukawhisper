import AppKit

/// Subtle audio cues for starting and finishing a dictation.
@MainActor
enum SoundPlayer {
    enum Cue: String {
        case start = "Tink"
        case stop = "Pop"
        case error = "Basso"
    }

    private static var cache: [Cue: NSSound] = [:]

    static func play(_ cue: Cue, enabled: Bool) {
        guard enabled else { return }
        let sound = cache[cue] ?? NSSound(named: cue.rawValue)
        cache[cue] = sound
        sound?.volume = 0.25
        sound?.stop()
        sound?.play()
    }
}
