import AppKit
import SwiftUI

/// Keep the bundle and Keychain identifiers stable so renaming preserves pairing.
enum AppIdentity {
    static let name = "Sofa"
    static let panelSize = NSSize(width: 356, height: 640)
}

@main
struct SofaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene { Settings { EmptyView() } }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    static var shared: AppDelegate!
    var model: RemoteModel!
    var statusItem: NSStatusItem!
    var popover: NSPopover!

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self
        NSApp.setActivationPolicy(.accessory)
        model = RemoteModel()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "tv", accessibilityDescription: AppIdentity.name)
            button.action = #selector(togglePopover)
            button.target = self
            button.toolTip = "Sofa · Your TV, within reach"
            button.setAccessibilityLabel("Open Sofa TV remote")
        }
        popover = NSPopover()
        popover.behavior = .transient
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        popover.delegate = self
        popover.contentSize = AppIdentity.panelSize
        popover.contentViewController = NSHostingController(rootView: RemoteView(model: model))
        // The status item's view must be attached to the menu bar before anchoring.
        DispatchQueue.main.async { [weak self] in self?.showPopover() }
    }

    @objc func togglePopover() {
        if popover.isShown { popover.performClose(nil) }
        else { showPopover() }
    }

    func showPopover() {
        guard let button = statusItem?.button, button.window != nil else { return }
        NSApp.activate(ignoringOtherApps: true)
        if !popover.isShown {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
        popover.contentViewController?.view.window?.makeKey()
    }

    func popoverShouldDetach(_ popover: NSPopover) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPopover()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) { model?.shutdown() }
}
