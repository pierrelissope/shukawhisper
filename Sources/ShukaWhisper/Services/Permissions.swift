import AppKit
import ApplicationServices
import AVFoundation

/// Microphone and Accessibility permission helpers.
@MainActor
enum Permissions {
    static var microphoneGranted: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    /// Asks for microphone access. Shows the system prompt the first time; if access was
    /// already refused (or the prompt can't be shown), opens the Microphone settings pane instead.
    static func requestMicrophone() async {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        Log.info("microphone status before request = \(status.rawValue)")
        switch status {
        case .authorized:
            return
        case .notDetermined:
            // The prompt only appears reliably when the app is frontmost.
            NSApp.activate()
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            Log.info("microphone request granted = \(granted)")
            if !granted { openMicrophoneSettings() }
        default:
            openMicrophoneSettings()
        }
    }

    /// Needed to listen to global hotkeys, read selected text and paste.
    static var accessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    /// Shows the system prompt that adds the app to the Accessibility list.
    static func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        openPrivacyPane("Privacy_Accessibility")
    }

    static func openMicrophoneSettings() {
        openPrivacyPane("Privacy_Microphone")
    }

    static func openKeyboardSettings() {
        open("x-apple.systempreferences:com.apple.Keyboard-Settings.extension")
    }

    /// macOS 13+ uses the `PrivacySecurity.extension` URL; older systems the legacy one.
    private static func openPrivacyPane(_ anchor: String) {
        let modern = "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?\(anchor)"
        let legacy = "x-apple.systempreferences:com.apple.preference.security?\(anchor)"
        let opened = open(modern) || open(legacy)
        Log.info("open settings pane \(anchor): \(opened)")
    }

    @discardableResult
    private static func open(_ url: String) -> Bool {
        guard let url = URL(string: url) else { return false }
        return NSWorkspace.shared.open(url)
    }
}
