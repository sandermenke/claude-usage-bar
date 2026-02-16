import SwiftUI
import AppKit

@MainActor
final class AppController: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private let model = UsageModel()
    private var eventMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let btn = statusItem.button {
            btn.image = StatusBarIcon.spark(for: 0)
            btn.action = #selector(handleClick)
            btn.sendAction(on: [.leftMouseUp, .rightMouseUp])
            btn.target = self
        }

        popover = NSPopover()
        popover.contentSize = NSSize(width: 340, height: 300)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: PopoverView(model: model))

        // Observe model changes to update icon
        model.$session
            .receive(on: RunLoop.main)
            .sink { [weak self] bucket in
                self?.updateIcon(pct: bucket.utilization)
            }
            .store(in: &cancellables)

        // Initial fetch + auto-refresh
        if model.hasCookie {
            model.fetch()
        }
        model.startAutoRefresh()
    }

    private var cancellables = Set<AnyCancellable>()

    private func updateIcon(pct: Double) {
        guard let btn = statusItem.button else { return }
        btn.image = StatusBarIcon.spark(for: pct)
        btn.title = " \(Int(pct))%"
    }

    @objc private func handleClick() {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        if popover.isShown {
            closePopover()
        } else {
            openPopover()
        }
    }

    private func openPopover() {
        // Refresh on every open
        if model.hasCookie { model.fetch() }

        guard let btn = statusItem.button else { return }
        popover.show(relativeTo: btn.bounds, of: btn, preferredEdge: .minY)
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closePopover()
        }
    }

    private func closePopover() {
        popover.performClose(nil)
        if let m = eventMonitor {
            NSEvent.removeMonitor(m)
            eventMonitor = nil
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Refresh", action: #selector(doRefresh), keyEquivalent: "r"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit ClaudeUsageBar", action: #selector(doQuit), keyEquivalent: "q"))
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func doRefresh() { model.fetch() }
    @objc private func doQuit() { NSApplication.shared.terminate(nil) }
}

import Combine

@main
struct ClaudeUsageBarApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppController()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)  // menu-bar only, no dock icon
        app.run()
    }
}
