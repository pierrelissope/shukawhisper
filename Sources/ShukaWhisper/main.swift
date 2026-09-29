import AppKit

// Developer mode: `ShukaWhisper --transcribe file.wav` runs the pipeline headless and exits.
// `ShukaWhisper --snapshots dir` renders the UI to PNG files and exits.
if await DevCommand.runIfRequested() || Snapshots.runIfRequested() {
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
