import Foundation

/// Picks the style category for the app (and website) the user is typing in.
///
/// Resolution order:
/// 1. A category listing the active website host (so Gmail in Chrome is "Email").
/// 2. A category listing the app's bundle identifier.
/// 3. The fallback category ("Other").
public enum StyleResolver {
    public static func category(for context: AppContext, in categories: [StyleCategory]) -> StyleCategory {
        if let host = context.host?.lowercased(),
           let match = categories.first(where: { $0.domains.contains { matches(host: host, domain: $0) } }) {
            return match
        }
        if let bundleID = context.bundleID,
           let match = categories.first(where: { $0.apps.contains { matches(bundleID: bundleID, pattern: $0) } }) {
            return match
        }
        return categories.first(where: \.isFallback)
            ?? categories.last
            ?? StyleCategory.defaults.first(where: \.isFallback)!
    }

    /// `slack.com` matches `slack.com` and `app.slack.com`, but not `notslack.com`.
    static func matches(host: String, domain: String) -> Bool {
        let domain = domain.lowercased().trimmingCharacters(in: .whitespaces)
        guard !domain.isEmpty else { return false }
        return host == domain || host.hasSuffix("." + domain)
    }

    /// Exact match, or prefix match when the pattern ends with `*`.
    static func matches(bundleID: String, pattern: String) -> Bool {
        if pattern.hasSuffix("*") {
            return bundleID.lowercased().hasPrefix(pattern.dropLast().lowercased())
        }
        return bundleID.caseInsensitiveCompare(pattern) == .orderedSame
    }
}
