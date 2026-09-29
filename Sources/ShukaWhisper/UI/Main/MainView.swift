import SwiftUI

enum Section: String, CaseIterable, Identifiable {
    case home, styles, dictionary, transforms, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .styles: "Styles"
        case .dictionary: "Dictionary"
        case .transforms: "Transforms"
        case .settings: "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house"
        case .styles: "textformat"
        case .dictionary: "character.book.closed"
        case .transforms: "wand.and.sparkles"
        case .settings: "gearshape"
        }
    }
}

/// Root of the main window: onboarding until everything is set up, then the sidebar app.
struct MainView: View {
    @Environment(AppModel.self) private var app
    @State private var section: Section = .home
    @State private var finishedOnboarding = false

    var body: some View {
        Group {
            if app.isReady || finishedOnboarding {
                NavigationSplitView {
                    List(Section.allCases, selection: $section) { section in
                        Label(section.title, systemImage: section.symbol)
                            .tag(section)
                    }
                    .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
                    .safeAreaInset(edge: .bottom) { SidebarStatus() }
                } detail: {
                    detail
                        .frame(minWidth: 560, minHeight: 520)
                }
            } else {
                OnboardingView { finishedOnboarding = true }
            }
        }
        .tint(Theme.accent)
        .onAppear { app.refreshPermissions() }
    }

    @ViewBuilder
    private var detail: some View {
        switch section {
        case .home: HomeView()
        case .styles: StylesView()
        case .dictionary: DictionaryView()
        case .transforms: TransformsView()
        case .settings: SettingsView()
        }
    }
}

/// Shows at a glance whether dictation is ready, at the bottom of the sidebar.
private struct SidebarStatus: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(app.isReady ? Color.green : Color.orange)
                .frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 1) {
                Text(app.isReady ? "Ready" : "Setup needed")
                    .font(.system(size: 12, weight: .medium))
                if app.isReady {
                    Text("Hold \(app.settings.dictationKey.title) to dictate")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(14)
    }
}
