import AppKit

// Developer commands run headless and exit:
//   ShukaWhisper --transcribe file.wav   runs the dictation pipeline on a recording
//   ShukaWhisper --snapshots dir         renders the UI to PNG files
let developerFlags = ["--transcribe", "--snapshots"]

if CommandLine.arguments.contains(where: developerFlags.contains) {
    Task { @MainActor in
        _ = await DevCommand.runIfRequested()
        _ = await Snapshots.runIfRequested()
        exit(0)
    }
    // Drive the main run loop on the real main thread (AppKit requires it); the task exits.
    MainActor.assumeIsolated {
        NSApplication.shared.setActivationPolicy(.accessory)
        NSApplication.shared.run()
    }
}

// Keep this top-level code synchronous: running `NSApplication.run()` from inside an
// async task would block the main actor, so no `Task` in the app could ever execute.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) {
        app.run()
    }
}
