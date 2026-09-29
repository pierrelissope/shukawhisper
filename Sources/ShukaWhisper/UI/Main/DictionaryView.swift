import ShukaCore
import SwiftUI

/// Words, names and jargon that should always be spelled a certain way.
struct DictionaryView: View {
    @Environment(AppModel.self) private var app
    @State private var term = ""
    @State private var aliases = ""
    @FocusState private var termFocused: Bool

    var body: some View {
        let entries = app.configuration.dictionary

        Page(title: "Dictionary", subtitle: "Teach ShukaWhisper names, products and jargon. They're used as hints for recognition and enforced when cleaning up your text.") {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        TextField("Word or phrase, e.g. Supabase", text: $term)
                            .focused($termFocused)
                        TextField("Often heard as (optional, comma separated)", text: $aliases)
                        Button("Add", action: add)
                            .keyboardShortcut(.defaultAction)
                            .disabled(term.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(add)
                    Text("Tip: about 100 well-chosen words works best.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if entries.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "character.book.closed")
                        .font(.system(size: 28))
                        .foregroundStyle(Theme.accent)
                    Text("Your dictionary is empty").font(.headline)
                    Text("Add the words speech recognition usually gets wrong.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(entries.count) \(entries.count == 1 ? "word" : "words")")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    FlowLayout(spacing: 8) {
                        ForEach(entries) { entry in
                            DictionaryChip(entry: entry) { remove(entry) }
                                .transition(.scale(scale: 0.8).combined(with: .opacity))
                        }
                    }
                }
            }
        }
        .onAppear { termFocused = true }
    }

    private func add() {
        let cleaned = term.trimmingCharacters(in: .whitespaces)
        guard !cleaned.isEmpty else { return }
        let aliasList = aliases.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        withAnimation(Theme.Motion.select) {
            if let index = app.configuration.dictionary.firstIndex(where: { $0.term.lowercased() == cleaned.lowercased() }) {
                app.configuration.dictionary[index].term = cleaned
                app.configuration.dictionary[index].aliases = aliasList
            } else {
                app.configuration.dictionary.insert(DictionaryEntry(term: cleaned, aliases: aliasList), at: 0)
            }
        }
        term = ""
        aliases = ""
    }

    private func remove(_ entry: DictionaryEntry) {
        withAnimation(Theme.Motion.select) {
            app.configuration.dictionary.removeAll { $0.id == entry.id }
        }
    }
}

private struct DictionaryChip: View {
    let entry: DictionaryEntry
    let onRemove: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            Text(entry.term).font(.system(size: 13, weight: .medium))
            if !entry.aliases.isEmpty {
                Text("← " + entry.aliases.joined(separator: ", "))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Button(action: onRemove) {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .opacity(hovering ? 1 : 0.35)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.background.secondary, in: .capsule)
        .overlay { Capsule().strokeBorder(hovering ? Theme.accent.opacity(0.6) : Color.secondary.opacity(0.2), lineWidth: 0.5) }
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}
