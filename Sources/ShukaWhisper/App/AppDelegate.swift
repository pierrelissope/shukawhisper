import AppKit
import ShukaCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    private let model = AppModel()
    private var statusItem: NSStatusItem?
    private var pillController: PillWindowController?
    private var mainWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        Log.info("launched v\(version), parent pid \(getppid()), microphone \(Permissions.microphoneGranted), accessibility \(Permissions.accessibilityGranted)")
        model.showMainWindow = { [weak self] in self?.showMainWindow() }
        model.start()
        pillController = PillWindowController(model: model.pill)
        setUpStatusItem()
        if !model.isReady { showMainWindow() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.configurationStore.saveNow()
    }

    // MARK: - Main window

    func showMainWindow() {
        if mainWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 960, height: 680),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = "ShukaWhisper"
            window.titlebarAppearsTransparent = true
            window.toolbarStyle = .unified
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: MainView().environment(model))
            window.setFrameAutosaveName("MainWindow")
            if !window.setFrameUsingName("MainWindow") { window.center() }
            window.delegate = self
            mainWindow = window
        }
        // Show in the Dock and app switcher while the window is open.
        NSApp.setActivationPolicy(.regular)
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    // MARK: - Menu bar

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "ShukaWhisper")
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    /// Rebuilt each time it opens so it always reflects the current state.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let status = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())

        menu.addItem(item("Open ShukaWhisper…", action: #selector(openMain), key: ","))
        menu.addItem(item("Copy Last Dictation", action: #selector(copyLast), key: ""))

        let transforms = NSMenuItem(title: "Transforms", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for slot in Transform.slots {
            guard let transform = model.configuration.transform(inSlot: slot) else { continue }
            let entry = NSMenuItem(title: transform.name, action: nil, keyEquivalent: "\(slot)")
            entry.keyEquivalentModifierMask = .option
            entry.isEnabled = false
            submenu.addItem(entry)
        }
        transforms.submenu = submenu
        menu.addItem(transforms)

        menu.addItem(.separator())
        menu.addItem(item("Quit ShukaWhisper", action: #selector(quit), key: "q"))
    }

    private var statusTitle: String {
        if model.apiKey == nil { return "Add a Gemini API key to start" }
        if !model.microphoneGranted { return "Microphone access needed" }
        if !model.accessibilityGranted { return "Accessibility access needed" }
        return "Hold \(model.settings.dictationKey.title) to dictate"
    }

    private func item(_ title: String, action: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func openMain() { showMainWindow() }

    @objc private func copyLast() {
        Task {
            guard let last = try? await model.history.recent(limit: 1).first else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(last.finalText, forType: .string)
        }
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
