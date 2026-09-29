import SwiftUI

/// First-run setup: API key → microphone → accessibility → try it.
struct OnboardingView: View {
    @Environment(AppModel.self) private var app
    let onFinish: () -> Void
    @State private var tryText = ""

    private enum Step: Int, CaseIterable { case key, microphone, accessibility, tryIt }

    private var step: Step {
        if app.apiKey == nil { return .key }
        if !app.microphoneGranted { return .microphone }
        if !app.accessibilityGranted { return .accessibility }
        return .tryIt
    }

    var body: some View {
        VStack(spacing: 28) {
            header
            progress
            Group {
                switch step {
                case .key: keyStep
                case .microphone: microphoneStep
                case .accessibility: accessibilityStep
                case .tryIt: tryStep
                }
            }
            .frame(maxWidth: 480)
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)))
            .id(step)
            Spacer(minLength: 0)
        }
        .padding(40)
        .frame(minWidth: 640, minHeight: 560)
        .animation(Theme.Motion.morph, value: step)
        .task {
            while !Task.isCancelled {
                app.refreshPermissions()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            AppLogo(size: 72)
            Text("Welcome to ShukaWhisper")
                .font(.system(size: 26, weight: .semibold, design: .rounded))
            Text("Speak anywhere on your Mac. Get clean, well-formatted text.")
                .foregroundStyle(.secondary)
        }
    }

    private var progress: some View {
        HStack(spacing: 6) {
            ForEach(Step.allCases, id: \.self) { item in
                Capsule()
                    .fill(item.rawValue <= step.rawValue ? Theme.accent : Color.secondary.opacity(0.25))
                    .frame(width: item == step ? 28 : 8, height: 8)
            }
        }
    }

    private var keyStep: some View {
        APIKeySection()
    }

    private var microphoneStep: some View {
        stepCard(
            symbol: "mic.fill",
            title: "Allow microphone access",
            text: "Audio is streamed to Gemini only while you hold the dictation key. Nothing is recorded to disk.",
            button: "Allow microphone"
        ) {
            if Permissions.microphoneDenied {
                Permissions.openMicrophoneSettings()
            } else {
                Task {
                    _ = await Permissions.requestMicrophone()
                    app.refreshPermissions()
                }
            }
        }
    }

    private var accessibilityStep: some View {
        stepCard(
            symbol: "accessibility",
            title: "Allow Accessibility",
            text: "Needed to notice the dictation key anywhere, read selected text for transforms, and type the result for you. Turn on ShukaWhisper in the list that opens.",
            button: "Open System Settings"
        ) {
            Permissions.requestAccessibility()
            Permissions.openAccessibilitySettings()
        }
    }

    private var tryStep: some View {
        VStack(spacing: 16) {
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Text("Hold")
                        KeyCaps(keys: [app.settings.dictationKey == .fn ? "fn" : app.settings.dictationKey.title])
                        Text("and say something, then release.")
                    }
                    .font(.headline)
                    TextField("Click here, then hold the key and speak…", text: $tryText, axis: .vertical)
                        .lineLimit(3...6)
                        .textFieldStyle(.roundedBorder)
                    if app.settings.dictationKey == .fn {
                        Text("If the emoji picker or dictation pops up, set System Settings › Keyboard › \"Press 🌐 key to\" to Do Nothing.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Button("Done", action: onFinish)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
    }

    private func stepCard(symbol: String, title: String, text: String, button: String, action: @escaping () -> Void) -> some View {
        Card(padding: 24) {
            VStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 26))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 56, height: 56)
                    .background(Theme.accentSoft, in: .circle)
                Text(title).font(.title3.weight(.semibold))
                Text(text)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(button, action: action)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

/// The app icon.
struct AppLogo: View {
    var size: CGFloat

    var body: some View {
        Image(nsImage: NSImage(named: "AppIcon") ?? NSApp.applicationIconImage)
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
    }
}
