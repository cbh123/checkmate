import AppKit
import Combine
import SwiftUI

@main
@MainActor
struct CheckmateApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.mainMenu = makeMainMenu()
        withExtendedLifetime(delegate) {
            app.run()
        }
    }

    private static func makeMainMenu() -> NSMenu {
        let menu = NSMenu()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Checkmate", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        menu.addItem(appItem)

        // AppKit-hosted text fields need an Edit menu for standard keyboard shortcuts.
        let editMenu = NSMenu(title: "Edit")
        for (title, action, key) in [
            ("Undo", "undo:", "z"),
            ("Redo", "redo:", "Z"),
            ("Cut", "cut:", "x"),
            ("Copy", "copy:", "c"),
            ("Paste", "paste:", "v"),
            ("Select All", "selectAll:", "a"),
        ] {
            editMenu.addItem(withTitle: title, action: NSSelectorFromString(action), keyEquivalent: key)
        }
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        editItem.submenu = editMenu
        menu.addItem(editItem)
        return menu
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store: Store
    private let popover = NSPopover()
    private var statusItem: NSStatusItem?
    private var storeObservation: AnyCancellable?

    override init() {
        store = Store()
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(togglePopover)
        item.button?.imagePosition = .imageLeading
        item.button?.font = .monospacedDigitSystemFont(ofSize: NSFont.menuBarFont(ofSize: 0).pointSize, weight: .regular)
        statusItem = item

        let host = NSHostingController(rootView: PopoverView(startInSettings: !store.isConfigured).environmentObject(store))
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host
        popover.behavior = .transient

        // objectWillChange fires before the new value lands, so read it on the next run loop pass.
        storeObservation = store.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateStatusItem() }
        updateStatusItem()
        store.start()
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        NSApp.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        Task { await store.refresh() }
    }

    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }
        let display = store.statusDisplay
        button.image = display.image
        button.title = display.title.isEmpty ? "" : " " + display.title
    }
}
