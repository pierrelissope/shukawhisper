import Foundation

/// A word the transcriber and formatter should always spell a certain way.
public struct DictionaryEntry: Codable, Sendable, Identifiable, Equatable, Hashable {
    public var id: UUID
    /// Canonical spelling, e.g. `Supabase`.
    public var term: String
    /// Common mis-hearings, e.g. `super base`. Optional.
    public var aliases: [String]

    public init(id: UUID = UUID(), term: String, aliases: [String] = []) {
        self.id = id
        self.term = term
        self.aliases = aliases
    }
}
