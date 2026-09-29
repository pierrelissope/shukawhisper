import Foundation

/// Stores the Gemini API key in `~/.config/shukawhisper/key`, readable only by the user (0600).
///
/// Why not the Keychain: without an Apple Developer ID, the Keychain ties access to the
/// binary's signature, which changes on every build. macOS then asks for the login password
/// again and again. A private file (like `gh`, `gcloud` or `aws` use) avoids that entirely.
///
/// `GEMINI_API_KEY` in the environment takes precedence over the file.
enum APIKeyStore {
    static let fileURL = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: ".config/shukawhisper/key")

    static func load() -> String? {
        let fromEnvironment = ProcessInfo.processInfo.environment["GEMINI_API_KEY"]
        let fromFile = try? String(contentsOf: fileURL, encoding: .utf8)
        guard let key = (fromEnvironment ?? fromFile)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !key.isEmpty else { return nil }
        return key
    }

    @discardableResult
    static func save(_ key: String) -> Bool {
        let manager = FileManager.default
        do {
            try manager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            // Create the file with owner-only permissions before writing the secret into it.
            if !manager.fileExists(atPath: fileURL.path) {
                manager.createFile(atPath: fileURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
            }
            try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
            try Data(key.utf8).write(to: fileURL)
            return true
        } catch {
            Log.info("could not save API key: \(error)")
            return false
        }
    }

    static func delete() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
