import SwiftUI

/// The floating dictation pill. One glass capsule morphs between states:
///
/// ```
/// idle ·──·  →  recording ⟨ ▂▅▇▅▂ ⟩  →  processing ⟨ • • • ⟩  →  success ( ✓ )  →  idle
///                     ↘ locked ⟨ ✕  ▂▅▇▅▂  0:12  ■ ⟩
/// ```
struct PillView: View {
    @Bindable var model: PillModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 8) {
            label
            capsule
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, 6)
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : Theme.Motion.morph, value: model.phase)
    }

    // MARK: Capsule

    private var capsule: some View {
        ZStack {
            content
                .transition(reduceMotion
                    ? .opacity
                    : .asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.6)).animation(Theme.Motion.content.delay(0.05)),
                        removal: .opacity.animation(.easeOut(duration: 0.1))
                    ))
                .id(contentID)
        }
        .frame(width: size.width, height: size.height)
        .glassEffect(.regular.tint(tint), in: .capsule)
        .opacity(opacity)
        .scaleEffect(isHidden ? 0.4 : 1, anchor: .bottom)
        .modifier(Shake(trigger: isError ? 1 : 0))
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .idle:
            Color.clear
        case .recording:
            Waveform(levels: model.levels)
        case .locked:
            LockedControls(model: model)
        case .processing:
            ThinkingDots()
        case .success:
            Image(systemName: "checkmark")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .symbolEffect(.bounce, options: .nonRepeating, value: model.phase)
        case let .error(message):
            HStack(spacing: 7) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                Text(message)
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            .font(.system(size: 12.5, weight: .medium))
            .padding(.horizontal, 14)
        }
    }

    /// Changes whenever the content should cross-fade (not on every level update).
    private var contentID: String {
        switch model.phase {
        case .idle: "idle"
        case .recording: "recording"
        case .locked: "locked"
        case .processing: "processing"
        case .success: "success"
        case let .error(message): "error-\(message)"
        }
    }

    // MARK: Label above the pill

    @ViewBuilder
    private var label: some View {
        if showsLabel, let text = model.label {
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .glassEffect(.regular.tint(.black.opacity(0.35)), in: .capsule)
                .environment(\.colorScheme, .dark)
                .transition(.opacity.combined(with: .offset(y: 6)))
        }
    }

    private var showsLabel: Bool {
        switch model.phase {
        case .recording, .locked, .processing: true
        default: false
        }
    }

    // MARK: Geometry

    private var isHidden: Bool { model.phase == .idle && !model.showsIdleIndicator }
    private var isError: Bool { if case .error = model.phase { true } else { false } }

    private var size: CGSize {
        switch model.phase {
        case .idle: CGSize(width: 38, height: 8)
        case .recording, .processing: CGSize(width: 118, height: 34)
        case .locked: CGSize(width: 218, height: 40)
        case .success: CGSize(width: 38, height: 38)
        case let .error(message):
            CGSize(width: min(380, CGFloat(message.count) * 7 + 64), height: 34)
        }
    }

    private var opacity: Double {
        switch model.phase {
        case .idle: model.showsIdleIndicator ? 0.55 : 0
        default: 1
        }
    }

    private var tint: Color {
        switch model.phase {
        case .error: Color(red: 0.55, green: 0.1, blue: 0.08).opacity(0.75)
        case .success: Theme.accent.opacity(0.85)
        default: .black.opacity(0.62)
        }
    }
}

// MARK: - Pieces

/// Symmetric bars: the newest level sits in the middle and ripples outwards.
private struct Waveform: View {
    let levels: [Float]

    var body: some View {
        HStack(alignment: .center, spacing: 2.5) {
            ForEach(Array(barHeights.enumerated()), id: \.offset) { _, height in
                Capsule()
                    .fill(.white)
                    .frame(width: 3, height: height)
            }
        }
        .animation(Theme.Motion.bars, value: levels)
        .frame(height: 24)
    }

    private var barHeights: [CGFloat] {
        let half = Array(levels.suffix(8).reversed()) // newest first
        let mirrored = half.dropFirst().reversed() + half
        return mirrored.enumerated().map { index, level in
            let distance = abs(Double(index) - Double(mirrored.count - 1) / 2) / Double(mirrored.count / 2)
            let envelope = 1 - 0.55 * distance * distance
            return 3 + CGFloat(level) * 21 * CGFloat(envelope)
        }
    }
}

private struct ThinkingDots: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 6) {
                ForEach(0..<3) { index in
                    let phase = sin(t * 5.5 - Double(index) * 0.75)
                    Circle()
                        .fill(.white)
                        .frame(width: 6, height: 6)
                        .scaleEffect(0.7 + 0.3 * (phase + 1) / 2)
                        .opacity(0.45 + 0.55 * (phase + 1) / 2)
                        .offset(y: -2.5 * phase)
                }
            }
        }
    }
}

private struct LockedControls: View {
    let model: PillModel

    var body: some View {
        HStack(spacing: 10) {
            button(systemImage: "xmark", help: "Cancel (Esc)", action: model.onCancel)
            Waveform(levels: model.levels)
                .frame(maxWidth: .infinity)
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                Text(elapsed(at: timeline.date))
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.8))
            }
            button(systemImage: "stop.fill", help: "Finish (fn)", prominent: true, action: model.onStop)
        }
        .padding(.horizontal, 6)
    }

    private func elapsed(at date: Date) -> String {
        let seconds = Int(date.timeIntervalSince(model.recordingStartedAt ?? date))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func button(systemImage: String, help: String, prominent: Bool = false, action: (() -> Void)?) -> some View {
        Button {
            action?()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(prominent ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.white.opacity(0.14)), in: .circle)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// Horizontal shake used for errors.
private struct Shake: ViewModifier {
    var trigger: Int

    func body(content: Content) -> some View {
        content.keyframeAnimator(initialValue: 0.0, trigger: trigger) { view, offset in
            view.offset(x: offset)
        } keyframes: { _ in
            KeyframeTrack {
                SpringKeyframe(-7, duration: 0.07)
                SpringKeyframe(6, duration: 0.08)
                SpringKeyframe(-4, duration: 0.08)
                SpringKeyframe(2, duration: 0.08)
                SpringKeyframe(0, duration: 0.1)
            }
        }
    }
}
