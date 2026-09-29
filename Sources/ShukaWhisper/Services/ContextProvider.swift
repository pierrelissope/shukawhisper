import AppKit
import ShukaCore

/// Figures out where the user is typing: frontmost app and, for browsers, the tab's host.
enum ContextProvider {
    /// Browsers whose active tab URL can be read over AppleScript, with the script to do it.
    private static let browserScripts: [String: String] = {
        let chromium = "get URL of active tab of front window"
        var scripts: [String: String] = [
            "com.apple.Safari": "get URL of front document",
            "com.apple.SafariTechnologyPreview": "get URL of front document",
        ]
        for id in ["com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.canary", "com.brave.Browser",
                   "com.microsoft.edgemac", "company.thebrowser.Browser", "company.thebrowser.dia",
                   "com.vivaldi.Vivaldi", "com.operasoftware.Opera", "org.chromium.Chromium"] {
            scripts[id] = chromium
        }
        return scripts
    }()

    private static let scriptQueue = DispatchQueue(label: "dev.shukawhisper.applescript")

    /// Snapshot of the frontmost app. Cheap; call when a session starts.
    @MainActor
    static func frontmostApp() -> AppContext {
        let app = NSWorkspace.shared.frontmostApplication
        return AppContext(bundleID: app?.bundleIdentifier, appName: app?.localizedName)
    }

    /// Adds the active tab's host when the app is a supported browser.
    /// Gives up after `timeout` so a busy browser never delays dictation.
    static func resolveHost(for context: AppContext, timeout: TimeInterval = 0.6) async -> AppContext {
        guard let bundleID = context.bundleID, let command = browserScripts[bundleID] else { return context }
        let source = "tell application id \"\(bundleID)\" to \(command)"

        let url: String? = await withTaskGroup(of: String?.self) { group in
            group.addTask {
                await withCheckedContinuation { continuation in
                    scriptQueue.async {
                        var error: NSDictionary?
                        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
                        continuation.resume(returning: result?.stringValue)
                    }
                }
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(timeout))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }

        var resolved = context
        resolved.host = url.flatMap { URL(string: $0)?.host() }
        return resolved
    }

    @MainActor
    static func icon(forBundleID bundleID: String?) -> NSImage? {
        guard let bundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}
