import AppKit

// Developer commands run headless and exit:
//   ShukaWhisper --transcribe file.wav   runs the dictation pipeline on a recording
//   ShukaWhisper --snapshots dir         renders the UI to PNG files
if await DevCommand.runIfRequested() {
    exit(0)
}
if await Snapshots.runIfRequested() {
    exit(0)
}

await MainActor.run {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) {
        app.run()
    }
}
