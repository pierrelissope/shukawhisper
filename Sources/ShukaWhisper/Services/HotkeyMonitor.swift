import AppKit
import CoreGraphics
import ShukaCore

/// Listens to the keyboard system-wide through a `CGEventTap` (requires Accessibility).
///
/// Emits:
/// - the dictation key going down / up (`fn` by default),
/// - any other key pressed while the dictation key is held (it was used as a modifier),
/// - `Esc` (swallowed only while a session is active),
/// - transform shortcuts (`⌃⌥1`…`⌃⌥9` by default) and voice-transform press / release on digit 0
///   (swallowed; any other modifier combination passes through, so `⌥` + digit still types symbols).
@MainActor
final class HotkeyMonitor {
    enum Event {
        case dictationKey(isDown: Bool, time: TimeInterval)
        case otherKeyWhileDictating
        case escape
        case transform(slot: Int)
        case voiceTransform(isDown: Bool)
    }

    var onEvent: ((Event) -> Void)?
    var dictationKey: DictationKey = .fn
    var transformModifier: TransformModifier = .controlOption
    /// Swallow `Esc` so it cancels dictation instead of reaching the frontmost app.
    var interceptsEscape = false

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var dictationKeyIsDown = false
    private var voiceKeyIsDown = false

    var isRunning: Bool { tap != nil }

    /// Installs the event tap. Returns `false` when Accessibility permission is missing.
    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        let mask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: hotkeyTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.runLoopSource = source
        return true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        tap = nil
        runLoopSource = nil
    }

    /// Returns `true` when the event should be swallowed.
    fileprivate func handle(type: CGEventType, event: CGEvent) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // macOS disables slow taps; turn it straight back on.
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        case .flagsChanged:
            return handleFlagsChanged(event)
        case .keyDown, .keyUp:
            return handleKey(event, isDown: type == .keyDown)
        default:
            return false
        }
    }

    private func handleFlagsChanged(_ event: CGEvent) -> Bool {
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        guard keyCode == dictationKey.keyCode else { return false }

        let isDown = event.flags.rawValue & dictationKey.deviceFlag != 0
        guard isDown != dictationKeyIsDown else { return false }
        dictationKeyIsDown = isDown
        onEvent?(.dictationKey(isDown: isDown, time: ProcessInfo.processInfo.systemUptime))
        return false
    }

    private func handleKey(_ event: CGEvent, isDown: Bool) -> Bool {
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0

        if keyCode == KeyCode.escape {
            guard interceptsEscape else { return false }
            if isDown, !isRepeat { onEvent?(.escape) }
            return true
        }

        // Digit 0 is held like a push-to-talk key; release is reported even if the modifiers were let go first.
        if keyCode == KeyCode.digit0, voiceKeyIsDown, !isDown {
            voiceKeyIsDown = false
            onEvent?(.voiceTransform(isDown: false))
            return true
        }

        if let digit = KeyCode.digits[keyCode], transformModifier.matches(event.flags), !dictationKeyIsDown {
            if isDown, !isRepeat {
                if digit == Transform.voiceSlot {
                    voiceKeyIsDown = true
                    onEvent?(.voiceTransform(isDown: true))
                } else {
                    onEvent?(.transform(slot: digit))
                }
            }
            return true
        }

        if isDown, dictationKeyIsDown {
            onEvent?(.otherKeyWhileDictating)
        }
        return false
    }

}

private extension TransformModifier {
    /// Exactly this modifier combination: extra ⌘ / ⇧ (or ⌃ for `.option`) lets the key through.
    func matches(_ flags: CGEventFlags) -> Bool {
        guard flags.contains(.maskAlternate), !flags.contains(.maskCommand), !flags.contains(.maskShift) else {
            return false
        }
        switch self {
        case .controlOption: return flags.contains(.maskControl)
        case .option: return !flags.contains(.maskControl)
        }
    }
}

private enum KeyCode {
    static let escape: UInt16 = 53
    static let digit0: UInt16 = 29
    /// Layout-independent key codes for the number row (works on AZERTY too).
    static let digits: [UInt16: Int] = [
        29: 0, 18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9,
    ]
}

private extension DictationKey {
    /// Device-dependent modifier bit identifying this specific key (left vs right).
    var deviceFlag: UInt64 {
        switch self {
        case .fn: CGEventFlags.maskSecondaryFn.rawValue
        case .rightOption: 0x40   // NX_DEVICERALTKEYMASK
        case .rightCommand: 0x10  // NX_DEVICERCMDKEYMASK
        }
    }
}

private func hotkeyTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
    // The tap's run loop source is on the main run loop, so this runs on the main thread.
    nonisolated(unsafe) let event = event
    let swallow = MainActor.assumeIsolated { monitor.handle(type: type, event: event) }
    return swallow ? nil : Unmanaged.passUnretained(event)
}
