import AppKit
import SwiftUI

/// Hosts the pill in a borderless panel that floats above everything and never takes focus.
@MainActor
final class PillWindowController {
    private let panel: NSPanel
    private let model: PillModel
    private static let panelSize = NSSize(width: 420, height: 110)

    init(model: PillModel) {
        self.model = model
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none

        let hosting = NSHostingView(rootView: PillView(model: model))
        hosting.sizingOptions = []
        panel.contentView = hosting

        position()
        panel.orderFrontRegardless()
        observe()
    }

    /// Bottom-center of the screen the user is working on, just above the Dock.
    private func position() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let origin = NSPoint(x: visible.midX - Self.panelSize.width / 2, y: visible.minY + 4)
        panel.setFrameOrigin(origin)
    }

    private func observe() {
        withObservationTracking {
            _ = model.phase
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.phaseChanged()
                self?.observe()
            }
        }
    }

    private func phaseChanged() {
        if model.phase == .recording { position() }
        // Only the hands-free controls need clicks; otherwise let clicks pass through.
        panel.ignoresMouseEvents = model.phase != .locked
        panel.orderFrontRegardless()
    }
}
