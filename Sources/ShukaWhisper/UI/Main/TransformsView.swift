import ShukaCore
import SwiftUI

/// Nine keyboard slots that rewrite the selected text, plus the voice transform.
struct TransformsView: View {
    @Environment(AppModel.self) private var app
    @State private var editingSlot: Int?

    var body: some View {
        Page(title: "Transforms", subtitle: "Select text in any app, then press a shortcut to rewrite it in place. ⌘Z undoes it.") {
            voiceCard

            VStack(spacing: 8) {
                ForEach(Array(Transform.slots), id: \.self) { slot in
                    SlotRow(slot: slot, transform: app.configuration.transform(inSlot: slot)) {
                        editingSlot = slot
                    }
                }
            }
        }
        .sheet(item: $editingSlot) { slot in
            TransformEditor(slot: slot, original: app.configuration.transform(inSlot: slot)) { result in
                save(result, slot: slot)
                editingSlot = nil
            } onCancel: {
                editingSlot = nil
            }
        }
    }

    private var voiceCard: some View {
        Card {
            HStack(spacing: 14) {
                Image(systemName: "mic.and.signal.meter")
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 40, height: 40)
                    .background(Theme.accentSoft, in: .circle)
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text("Voice transform").font(.headline)
                        KeyCaps(keys: ["⌥", "0"])
                        Text("hold").font(.caption).foregroundStyle(.secondary)
                    }
                    Text("Select text, hold ⌥0 and say what to do: \"make this friendlier\", \"translate to Spanish\". With nothing selected, it writes what you ask for.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func save(_ result: TransformEditor.Result, slot: Int) {
        var transforms = app.configuration.transforms
        transforms.removeAll { $0.slot == slot }
        if case let .save(transform) = result {
            transforms.append(transform)
        }
        app.configuration.transforms = transforms.sorted { ($0.slot ?? 99) < ($1.slot ?? 99) }
    }
}

extension Int: @retroactive Identifiable {
    public var id: Int { self }
}

private struct SlotRow: View {
    let slot: Int
    let transform: Transform?
    let onEdit: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onEdit) {
            HStack(spacing: 14) {
                KeyCaps(keys: ["⌥", "\(slot)"])
                if let transform {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(transform.name).font(.headline)
                        Text(transform.instructions)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                } else {
                    Text("Empty slot").foregroundStyle(.tertiary)
                }
                Spacer()
                Image(systemName: transform == nil ? "plus" : "pencil")
                    .foregroundStyle(hovering ? Theme.accent : .secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.background.secondary, in: .rect(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(hovering ? Theme.accent.opacity(0.5) : Color.secondary.opacity(0.18), lineWidth: 0.5)
            }
            .contentShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

private struct TransformEditor: View {
    enum Result { case save(Transform), delete }

    let slot: Int
    let original: Transform?
    let onDone: (Result) -> Void
    let onCancel: () -> Void

    @State private var name: String
    @State private var instructions: String
    @State private var samples: [String]

    init(slot: Int, original: Transform?, onDone: @escaping (Result) -> Void, onCancel: @escaping () -> Void) {
        self.slot = slot
        self.original = original
        self.onDone = onDone
        self.onCancel = onCancel
        _name = State(initialValue: original?.name ?? "")
        _instructions = State(initialValue: original?.instructions ?? "")
        _samples = State(initialValue: original?.samples ?? [])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(original == nil ? "New transform" : "Edit transform").font(.title2.weight(.semibold))
                Spacer()
                KeyCaps(keys: ["⌥", "\(slot)"])
            }

            TextField("Name, e.g. Friendly reply", text: $name)
                .textFieldStyle(.roundedBorder)

            VStack(alignment: .leading, spacing: 6) {
                Text("Instructions").font(.headline)
                TextEditor(text: $instructions)
                    .frame(minHeight: 120)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(.background.secondary, in: .rect(cornerRadius: 10))
                    .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(.separator.opacity(0.6), lineWidth: 0.5) }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Examples of the output (optional)").font(.headline)
                    Spacer()
                    if samples.count < 5 {
                        Button { samples.append("") } label: { Label("Add example", systemImage: "plus") }
                            .buttonStyle(.borderless)
                    }
                }
                ForEach(samples.indices, id: \.self) { index in
                    HStack(alignment: .top) {
                        TextEditor(text: $samples[index])
                            .frame(height: 60)
                            .scrollContentBackground(.hidden)
                            .padding(6)
                            .background(.background.secondary, in: .rect(cornerRadius: 8))
                        Button { samples.remove(at: index) } label: { Image(systemName: "minus.circle.fill") }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            HStack {
                if original != nil {
                    Button("Clear slot", role: .destructive) { onDone(.delete) }
                }
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    onDone(.save(Transform(
                        id: original?.id ?? UUID(),
                        slot: slot,
                        name: name.trimmingCharacters(in: .whitespaces),
                        instructions: instructions.trimmingCharacters(in: .whitespacesAndNewlines),
                        samples: samples.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty },
                        isBuiltIn: original?.isBuiltIn ?? false
                    )))
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty
                    || instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 520)
        .tint(Theme.accent)
    }
}
