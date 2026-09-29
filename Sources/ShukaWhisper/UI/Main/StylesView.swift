import ShukaCore
import SwiftUI
import UniformTypeIdentifiers

/// Per-category writing styles: preset, custom instructions, sample, and app/website assignment.
struct StylesView: View {
    @Environment(AppModel.self) private var app
    @State private var selectedID = StyleCategory.defaults[0].id

    var body: some View {
        @Bindable var store = app.configurationStore
        let categories = store.configuration.categories

        Page(title: "Styles", subtitle: "Choose how your words are formatted in each kind of app. The style is picked automatically from the app or website you're typing in.") {
            CategoryTabs(categories: categories, selectedID: $selectedID) { addCategory() }

            if let index = categories.firstIndex(where: { $0.id == selectedID }) {
                CategoryEditor(category: $store.configuration.categories[index]) {
                    deleteCategory(at: index)
                }
                .id(selectedID)
            }
        }
        .onAppear {
            if !categories.contains(where: { $0.id == selectedID }) { selectedID = categories.first?.id ?? "" }
        }
    }

    private func addCategory() {
        let category = StyleCategory(name: "New category", symbol: "sparkles")
        // Insert before the fallback so it stays last.
        let index = app.configuration.categories.firstIndex(where: \.isFallback) ?? app.configuration.categories.endIndex
        app.configuration.categories.insert(category, at: index)
        withAnimation(Theme.Motion.select) { selectedID = category.id }
    }

    private func deleteCategory(at index: Int) {
        app.configuration.categories.remove(at: index)
        withAnimation(Theme.Motion.select) { selectedID = app.configuration.categories.first?.id ?? "" }
    }
}

private struct CategoryTabs: View {
    let categories: [StyleCategory]
    @Binding var selectedID: String
    let onAdd: () -> Void
    @Namespace private var namespace

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(categories) { category in
                    let selected = category.id == selectedID
                    Button {
                        withAnimation(Theme.Motion.select) { selectedID = category.id }
                    } label: {
                        Label(category.name, systemImage: category.symbol)
                            .font(.system(size: 13, weight: selected ? .semibold : .regular))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .foregroundStyle(selected ? Theme.accent : .primary)
                            .background {
                                if selected {
                                    Capsule().fill(Theme.accentSoft)
                                        .matchedGeometryEffect(id: "tab", in: namespace)
                                }
                            }
                            .contentShape(.capsule)
                    }
                    .buttonStyle(.plain)
                }
                Button(action: onAdd) {
                    Image(systemName: "plus")
                        .padding(8)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Add a category")
            }
        }
    }
}

private struct CategoryEditor: View {
    @Binding var category: StyleCategory
    let onDelete: () -> Void
    @State private var showSample = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
            if !category.isBuiltIn {
                HStack {
                    TextField("Category name", text: $category.name)
                        .textFieldStyle(.roundedBorder)
                        .font(.title3)
                        .frame(maxWidth: 280)
                    Spacer()
                    Button("Delete category", role: .destructive, action: onDelete)
                }
            }

            presetGrid

            VStack(alignment: .leading, spacing: 8) {
                SectionTitle(title: "Custom instructions", detail: "Extra rules for this category, in plain words.")
                TextEditor(text: $category.customInstructions)
                    .font(.body)
                    .frame(minHeight: 80)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(.background.secondary, in: .rect(cornerRadius: 10))
                    .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(.separator.opacity(0.6), lineWidth: 0.5) }
                    .overlay(alignment: .topLeading) {
                        if category.customInstructions.isEmpty {
                            Text("e.g. \"Always use British spelling\" or \"Never use emojis\"")
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 13)
                                .padding(.vertical, 8)
                                .allowsHitTesting(false)
                        }
                    }

                DisclosureGroup("Writing sample", isExpanded: $showSample) {
                    TextEditor(text: $category.writingSample)
                        .frame(minHeight: 80)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(.background.secondary, in: .rect(cornerRadius: 10))
                        .padding(.top, 6)
                    Text("Paste something you wrote. Its formatting habits (not its content) will be matched.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)
            }

            if category.isFallback {
                Card {
                    Label("Used for every app and website not listed in another category.", systemImage: "info.circle")
                        .foregroundStyle(.secondary)
                }
            } else {
                AppsEditor(bundleIDs: $category.apps)
                DomainsEditor(domains: $category.domains)
            }
        }
    }

    private var presetGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle(title: "Style", detail: "Only punctuation and capitalization change — never your words.")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 10)], spacing: 10) {
                ForEach(StylePreset.allCases) { preset in
                    PresetCard(preset: preset, isSelected: category.preset == preset) {
                        withAnimation(Theme.Motion.select) { category.preset = preset }
                    }
                }
            }
        }
    }
}

private struct PresetCard: View {
    let preset: StylePreset
    let isSelected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(preset.title).font(.headline)
                    Spacer()
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? Theme.accent : Color.secondary.opacity(0.5))
                        .contentTransition(.symbolEffect(.replace))
                }
                Text(preset.example)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 50, alignment: .topLeading)
                    .multilineTextAlignment(.leading)
            }
            .padding(14)
            .background(.background.secondary, in: .rect(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isSelected ? Theme.accent : Color.secondary.opacity(hovering ? 0.35 : 0.18),
                                  lineWidth: isSelected ? 1.5 : 0.5)
            }
            .scaleEffect(hovering && !isSelected ? 1.01 : 1)
            .contentShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

struct SectionTitle: View {
    let title: String
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.headline)
            if let detail {
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Apps & websites

private struct AppsEditor: View {
    @Binding var bundleIDs: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionTitle(title: "Apps")
                Spacer()
                Menu {
                    ForEach(runningApps, id: \.bundleIdentifier) { app in
                        Button(app.localizedName ?? app.bundleIdentifier ?? "App") {
                            add(app.bundleIdentifier)
                        }
                    }
                    Divider()
                    Button("Choose from Applications…", action: chooseApp)
                } label: {
                    Label("Add app", systemImage: "plus")
                }
                .fixedSize()
            }
            Card(padding: 6) {
                if bundleIDs.isEmpty {
                    Text("No apps yet").foregroundStyle(.secondary).padding(10)
                } else {
                    VStack(spacing: 0) {
                        ForEach(bundleIDs, id: \.self) { bundleID in
                            AppRow(bundleID: bundleID) {
                                withAnimation(Theme.Motion.select) { bundleIDs.removeAll { $0 == bundleID } }
                            }
                        }
                    }
                }
            }
        }
    }

    private var runningApps: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil && !bundleIDs.contains($0.bundleIdentifier!) }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    private func add(_ bundleID: String?) {
        guard let bundleID, !bundleIDs.contains(bundleID) else { return }
        withAnimation(Theme.Motion.select) { bundleIDs.append(bundleID) }
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(filePath: "/Applications")
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls { add(Bundle(url: url)?.bundleIdentifier) }
    }
}

private struct AppRow: View {
    let bundleID: String
    let onRemove: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            if let icon = ContextProvider.icon(forBundleID: bundleID.hasSuffix("*") ? nil : bundleID) {
                Image(nsImage: icon).resizable().frame(width: 22, height: 22)
            } else {
                Image(systemName: "app.dashed").font(.system(size: 17)).frame(width: 22, height: 22).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(displayName)
                Text(bundleID).font(.caption).foregroundStyle(.tertiary)
            }
            Spacer()
            Button(action: onRemove) { Image(systemName: "minus.circle.fill") }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .opacity(hovering ? 1 : 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .onHover { hovering = $0 }
    }

    private var displayName: String {
        if bundleID.hasSuffix("*") { return "All \(bundleID.dropLast(2)) apps" }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }
}

private struct DomainsEditor: View {
    @Binding var domains: [String]
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle(title: "Websites", detail: "Detected in Safari, Chrome, Arc, Brave, Edge and other Chromium browsers.")
            FlowLayout(spacing: 6) {
                ForEach(domains, id: \.self) { domain in
                    HStack(spacing: 4) {
                        Text(domain)
                        Button {
                            withAnimation(Theme.Motion.select) { domains.removeAll { $0 == domain } }
                        } label: {
                            Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                    .font(.system(size: 12.5))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.primary.opacity(0.06), in: .capsule)
                }
                TextField("add website…", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .frame(width: 140)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .overlay { Capsule().strokeBorder(.separator, style: StrokeStyle(lineWidth: 0.5, dash: [3])) }
                    .onSubmit(add)
            }
        }
    }

    private func add() {
        var domain = draft.trimmingCharacters(in: .whitespaces).lowercased()
        if let host = URL(string: domain.contains("://") ? domain : "https://\(domain)")?.host() { domain = host }
        draft = ""
        guard !domain.isEmpty, !domains.contains(domain) else { return }
        withAnimation(Theme.Motion.select) { domains.append(domain) }
    }
}

/// Wraps children onto multiple lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y + (row.height - size.height) / 2),
                                      proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row { var indices: [Int] = []; var y: CGFloat = 0; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !rows[rows.count - 1].indices.isEmpty, rows[rows.count - 1].width + spacing + size.width > width {
                let last = rows[rows.count - 1]
                rows.append(Row(y: last.y + last.height + spacing))
            }
            var row = rows[rows.count - 1]
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}
