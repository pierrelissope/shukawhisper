import Foundation

/// How text is formatted: the tone presets offered for every style category.
///
/// Presets only change capitalization, punctuation and energy — never wording.
/// Anything more specific goes in `StyleCategory.customInstructions`.
public enum StylePreset: String, Codable, CaseIterable, Sendable, Identifiable {
    case veryCasual, casual, formal, excited

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .veryCasual: "Very casual"
        case .casual: "Casual"
        case .formal: "Formal"
        case .excited: "Excited"
        }
    }

    public var summary: String {
        switch self {
        case .veryCasual: "all lowercase, barely any punctuation"
        case .casual: "Sentence case, relaxed punctuation"
        case .formal: "Proper capitalization and full punctuation."
        case .excited: "Energetic, with exclamation marks!"
        }
    }

    /// Rendered example shown on the style cards.
    public var example: String {
        switch self {
        case .veryCasual: "hey are we still on for lunch tomorrow, i can do noon"
        case .casual: "Hey, are we still on for lunch tomorrow? I can do noon"
        case .formal: "Hey, are we still on for lunch tomorrow? I can do noon."
        case .excited: "Hey, are we still on for lunch tomorrow? I can do noon!"
        }
    }

    /// Instruction given to the formatter model.
    var rule: String {
        switch self {
        case .veryCasual:
            "Very casual: write everything in lowercase (except proper nouns, acronyms and code identifiers), use minimal punctuation, keep question marks, and never end with a period."
        case .casual:
            "Casual: sentence case, natural punctuation, but no period at the very end of the text."
        case .formal:
            "Formal: proper capitalization and complete punctuation, including a final period."
        case .excited:
            "Excited: sentence case and natural punctuation; end sentences that express enthusiasm with an exclamation mark. Do not add words."
        }
    }
}

/// A group of apps and websites sharing a writing style (e.g. "Email").
public struct StyleCategory: Codable, Sendable, Identifiable, Equatable, Hashable {
    public var id: String
    public var name: String
    /// SF Symbol name shown in the UI.
    public var symbol: String
    public var preset: StylePreset
    /// Free-form extra rules ("Put the greeting on its own line").
    public var customInstructions: String
    /// Optional example of the user's own writing, used to match tone.
    public var writingSample: String
    /// Bundle identifiers. A trailing `*` matches a prefix (`com.jetbrains.*`).
    public var apps: [String]
    /// Website hosts. Subdomains match too (`slack.com` matches `app.slack.com`).
    public var domains: [String]
    /// The fallback category used when nothing else matches. Exactly one should exist.
    public var isFallback: Bool
    public var isBuiltIn: Bool

    public init(
        id: String = UUID().uuidString,
        name: String,
        symbol: String = "text.bubble",
        preset: StylePreset = .casual,
        customInstructions: String = "",
        writingSample: String = "",
        apps: [String] = [],
        domains: [String] = [],
        isFallback: Bool = false,
        isBuiltIn: Bool = false
    ) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.preset = preset
        self.customInstructions = customInstructions
        self.writingSample = writingSample
        self.apps = apps
        self.domains = domains
        self.isFallback = isFallback
        self.isBuiltIn = isBuiltIn
    }
}

public extension StyleCategory {
    static let defaults: [StyleCategory] = [
        StyleCategory(
            id: "personal", name: "Personal messages", symbol: "heart.text.square",
            preset: .casual,
            apps: ["com.apple.MobileSMS", "net.whatsapp.WhatsApp", "ru.keepcoder.Telegram",
                   "org.telegram.desktop", "com.hnc.Discord", "com.facebook.archon", "org.whispersystems.signal-desktop"],
            domains: ["web.whatsapp.com", "web.telegram.org", "discord.com", "messenger.com", "instagram.com"],
            isBuiltIn: true
        ),
        StyleCategory(
            id: "work", name: "Work messages", symbol: "bubble.left.and.text.bubble.right",
            preset: .casual,
            apps: ["com.tinyspeck.slackmacgap", "com.microsoft.teams2", "com.microsoft.teams", "com.linear"],
            domains: ["app.slack.com", "teams.microsoft.com", "linkedin.com", "linear.app"],
            isBuiltIn: true
        ),
        StyleCategory(
            id: "email", name: "Email", symbol: "envelope",
            preset: .formal,
            customInstructions: "If the text opens with a greeting (\"Hi Anna\", \"Bonjour Paul\"), put it on its own line followed by a blank line. Put a closing (\"Best\", \"Cordialement\") and the name after it on their own lines. Split long text into short paragraphs.",
            apps: ["com.apple.mail", "com.superhuman.electron", "com.microsoft.Outlook",
                   "com.readdle.smartemail-Mac", "com.google.Gmail"],
            domains: ["mail.google.com", "outlook.live.com", "outlook.office.com", "outlook.office365.com",
                      "mail.superhuman.com", "app.hey.com", "mail.proton.me"],
            isBuiltIn: true
        ),
        StyleCategory(
            id: "ai", name: "AI prompts & code", symbol: "chevron.left.forwardslash.chevron.right",
            preset: .casual,
            customInstructions: "The text is a prompt for an AI assistant or a terminal. Keep the speaker's sentences and phrasing. Write file names, commands, code identifiers and technical terms in their canonical spelling (package.json, useEffect, git rebase). Use plain text, no markdown. Only use a numbered list when the speaker explicitly enumerates three or more separate items (\"first…, second…, third…\").",
            apps: ["com.anthropic.claudefordesktop", "com.openai.chat", "com.apple.Terminal", "com.googlecode.iterm2",
                   "com.mitchellh.ghostty", "dev.warp.Warp-Stable", "com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92",
                   "dev.zed.Zed", "com.jetbrains.*", "com.exafunction.windsurf", "net.kovidgoyal.kitty", "com.github.wez.wezterm"],
            domains: ["claude.ai", "chatgpt.com", "gemini.google.com", "aistudio.google.com", "github.com", "v0.dev"],
            isBuiltIn: true
        ),
        StyleCategory(
            id: "other", name: "Other", symbol: "square.grid.2x2",
            preset: .formal,
            isFallback: true, isBuiltIn: true
        ),
    ]
}
