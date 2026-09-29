import Foundation
import Security

/// Stores the Gemini API key in the user's login Keychain.
enum KeychainStore {
    private static let service = "dev.shukawhisper.gemini"
    private static let account = "api-key"

    static func apiKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    @discardableResult
    static func setAPIKey(_ key: String) -> Bool {
        deleteAPIKey()
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrLabel as String: "ShukaWhisper Gemini API key",
            kSecValueData as String: Data(key.utf8),
        ]
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }

    static func deleteAPIKey() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

/// Finds the API key: Keychain first, then `GEMINI_API_KEY`, then `~/.config/shukawhisper/key`.
/// Keys found outside the Keychain are imported into it.
enum APIKeyProvider {
    static let fileURL = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".config/shukawhisper/key")

    static func load() -> String? {
        if let key = KeychainStore.apiKey(), !key.isEmpty { return key }
        let fromEnvironment = ProcessInfo.processInfo.environment["GEMINI_API_KEY"]
        let fromFile = try? String(contentsOf: fileURL, encoding: .utf8)
        guard let key = (fromEnvironment ?? fromFile)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !key.isEmpty else { return nil }
        KeychainStore.setAPIKey(key)
        return key
    }
}
