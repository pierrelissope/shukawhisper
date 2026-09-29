import Foundation

/// A saved rewrite applied to selected text with `⌥` + slot number.
public struct Transform: Codable, Sendable, Identifiable, Equatable, Hashable {
    public var id: UUID
    /// Keyboard slot 1–9 (`⌥1` … `⌥9`). `nil` means unassigned.
    public var slot: Int?
    public var name: String
    public var instructions: String
    /// Optional examples of the desired output.
    public var samples: [String]
    public var isBuiltIn: Bool

    public init(
        id: UUID = UUID(),
        slot: Int?,
        name: String,
        instructions: String,
        samples: [String] = [],
        isBuiltIn: Bool = false
    ) {
        self.id = id
        self.slot = slot
        self.name = name
        self.instructions = instructions
        self.samples = samples
        self.isBuiltIn = isBuiltIn
    }

    public static let slots = 1...9
    /// `⌥0` is reserved for the voice transform (speak your own instruction).
    public static let voiceSlot = 0
}

public extension Transform {
    static let defaults: [Transform] = [
        Transform(
            slot: 1, name: "Polish",
            instructions: """
            Fix grammar, spelling and punctuation. Remove repetitions and filler. Make sentences flow naturally \
            while keeping the author's voice, meaning, language and level of formality. Do not add content.
            """,
            isBuiltIn: true
        ),
        Transform(
            slot: 2, name: "Prompt Engineer",
            instructions: """
            Rewrite the text into a clear, well-structured prompt for an AI coding assistant. Start with the goal in one \
            sentence, then give the relevant context, the concrete requirements or steps (as a list when there are \
            several), constraints, and what a good result looks like. Keep every technical detail from the original. \
            Do not invent requirements. Write in the same language as the original.
            """,
            isBuiltIn: true
        ),
        Transform(
            slot: 3, name: "Translate to English",
            instructions: """
            Translate the text into natural, idiomatic English as a native speaker would write it, keeping the tone \
            and formatting. If it is already in English, improve its phrasing so it sounds native.
            """,
            isBuiltIn: true
        ),
        Transform(
            slot: 4, name: "Make concise",
            instructions: "Make the text shorter and more direct without losing any important information. Keep the language and tone.",
            isBuiltIn: true
        ),
    ]
}
