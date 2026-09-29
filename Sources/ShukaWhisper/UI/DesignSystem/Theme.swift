import SwiftUI

/// Shared visual language: one warm accent, calm neutrals, generous spacing.
enum Theme {
    /// Brand accent (warm tangerine).
    static let accent = Color(red: 1.0, green: 0.42, blue: 0.24)
    static let accentSoft = accent.opacity(0.14)

    static let cornerRadius: CGFloat = 14
    static let pagePadding: CGFloat = 28
    static let sectionSpacing: CGFloat = 22

    /// Springs used across the app so motion feels consistent.
    enum Motion {
        /// Shape changes of the pill (expand, morph, collapse).
        static let morph = Animation.spring(response: 0.36, dampingFraction: 0.78)
        /// Content swaps inside the pill.
        static let content = Animation.spring(response: 0.28, dampingFraction: 0.9)
        /// Waveform bars following the voice.
        static let bars = Animation.interpolatingSpring(stiffness: 420, damping: 22)
        /// Selection changes in lists and cards.
        static let select = Animation.spring(response: 0.3, dampingFraction: 0.82)
    }
}

/// A rounded, subtly bordered container used for grouped content.
struct Card<Content: View>: View {
    var padding: CGFloat = 18
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.secondary, in: .rect(cornerRadius: Theme.cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.cornerRadius)
                    .strokeBorder(.separator.opacity(0.6), lineWidth: 0.5)
            }
    }
}

/// Large title + subtitle at the top of each page.
struct PageHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
            Text(subtitle)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Scrollable page scaffold with consistent padding and width.
struct Page<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                PageHeader(title: title, subtitle: subtitle)
                content
            }
            .padding(Theme.pagePadding)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollContentBackground(.hidden)
    }
}

/// Small rounded label, e.g. a shortcut or a domain.
struct Chip: View {
    let text: String
    var systemImage: String?
    var prominent = false

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage).imageScale(.small) }
            Text(text)
        }
        .font(.system(size: 11.5, weight: .medium))
        .padding(.horizontal, 8)
        .padding(.vertical, 3.5)
        .foregroundStyle(prominent ? Theme.accent : .secondary)
        .background(prominent ? Theme.accentSoft : Color.primary.opacity(0.06), in: .capsule)
    }
}

/// Keyboard shortcut rendered as key caps.
struct KeyCaps: View {
    let keys: [String]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(keys, id: \.self) { key in
                Text(key)
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .frame(minWidth: 20)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2.5)
                    .background(.background, in: .rect(cornerRadius: 5))
                    .overlay {
                        RoundedRectangle(cornerRadius: 5).strokeBorder(.separator, lineWidth: 0.5)
                    }
                    .shadow(color: .black.opacity(0.08), radius: 0, y: 1)
            }
        }
    }
}
