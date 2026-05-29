import AppKit
import SwiftUI
import Combine

/// Owns the menu bar status item, the popover, the global hotkey listener,
/// the editor window, and the settings window.
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private(set) var store    = MacroStore()
    private(set) var settings = AppSettings()

    private var statusItem:     NSStatusItem!
    private var popover:        NSPopover!
    private var hotkeys:        HotkeyListener?
    private var editorWindow:   NSWindow?
    private var settingsWindow: NSWindow?
    private var observers:      Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupPopover()
        setupHotkeys()
        observeSettings()
        promptForAccessibilityIfNeeded()
    }

    // ── status item ───────────────────────────────────────────────────────────

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let btn = statusItem.button {
            applyMenuBarIcon(settings.menuBarIcon)
            btn.action = #selector(statusItemClicked(_:))
            btn.target = self
            btn.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    private func applyMenuBarIcon(_ symbol: String) {
        guard let btn = statusItem?.button else { return }
        btn.image = NSImage(systemSymbolName: symbol,
                            accessibilityDescription: "MacroDeck")
            ?? NSImage(systemSymbolName: "square.grid.2x2",
                       accessibilityDescription: "MacroDeck")
        btn.image?.isTemplate = true
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover(sender)
        }
    }

    // ── context menu ──────────────────────────────────────────────────────────

    private func showContextMenu() {
        let menu = NSMenu()

        let settingsItem = NSMenuItem(title: "Settings…",
                                      action: #selector(openSettings),
                                      keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let permsItem = NSMenuItem(title: "Permissions", action: nil, keyEquivalent: "")
        let permsSub = NSMenu()
        let ax = NSMenuItem(title: "Accessibility…",
                            action: #selector(openAccessibility),
                            keyEquivalent: "")
        ax.target = self
        let im = NSMenuItem(title: "Input Monitoring…",
                            action: #selector(openInputMonitoring),
                            keyEquivalent: "")
        im.target = self
        permsSub.items = [ax, im]
        permsItem.submenu = permsSub
        menu.addItem(permsItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit MacroDeck",
                                  action: #selector(NSApp.terminate(_:)),
                                  keyEquivalent: "q")
        quitItem.target = NSApp
        menu.addItem(quitItem)

        // Standard NSStatusItem context-menu pattern: assign menu, re-click to
        // pop it, clear so future left-clicks fall through to the action again.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        DispatchQueue.main.async { [weak self] in
            self?.statusItem.menu = nil
        }
    }

    @objc private func openAccessibility() {
        Permissions.openSecurityPane("Accessibility")
    }

    @objc private func openInputMonitoring() {
        Permissions.openSecurityPane("ListenEvent")
    }

    // ── popover ───────────────────────────────────────────────────────────────

    private func setupPopover() {
        popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        let host = NSHostingController(rootView:
            PopupView(
                onDismissRequested: { [weak self] in
                    self?.popover.performClose(nil)
                },
                onEditRequested: { [weak self] slot in
                    self?.openEditor(slot: slot)
                }
            )
            .environmentObject(store)
            .environmentObject(settings)
        )
        popover.contentViewController = host
    }

    @objc func togglePopover(_ sender: Any?) {
        guard let btn = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            // Show without making the popover's window key. NSPopover.transient
            // doesn't need key status to receive clicks or auto-dismiss, and
            // leaving the previously-active app key means macro hotkeys
            // (⌃1..⌃0) fire keystrokes into that app — not into MacroDeck.
            popover.show(relativeTo: btn.bounds, of: btn, preferredEdge: .minY)
        }
    }

    // ── hotkeys ───────────────────────────────────────────────────────────────

    private func setupHotkeys() {
        hotkeys = HotkeyListener(
            toggleHotkey: settings.toggleHotkey,
            onSlot: { [weak self] slot in
                guard let self, let macro = self.store.get(slot: slot) else { return }
                Player.shared.run(macro: macro)
                // If the popover is up when a slot hotkey fires, dismiss it
                // the same way a click would. Without this, the popover stays
                // open after the hotkey path (which doesn't go through the
                // SwiftUI tile-click handler).
                if !macro.keepOpen, self.popover.isShown {
                    self.popover.performClose(nil)
                }
            },
            onToggle: { [weak self] in
                self?.togglePopover(nil)
            }
        )
    }

    // ── settings observation ──────────────────────────────────────────────────

    private func observeSettings() {
        settings.$menuBarIcon
            .removeDuplicates()
            .sink { [weak self] icon in self?.applyMenuBarIcon(icon) }
            .store(in: &observers)

        settings.$toggleHotkey
            .removeDuplicates()
            .sink { [weak self] hk in self?.hotkeys?.updateToggleHotkey(hk) }
            .store(in: &observers)
    }

    // ── editor window ─────────────────────────────────────────────────────────

    func openEditor(slot: Int) {
        if let w = editorWindow {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let existing = store.get(slot: slot)
        let initial  = existing ?? Macro(name: "New Macro")

        let view = EditorView(
            slot: slot,
            initial: initial,
            onSave: { [weak self] updated in
                self?.store.set(slot: slot, updated)
                self?.closeEditor()
            },
            onCancel: { [weak self] in self?.closeEditor() },
            onDelete: existing == nil ? nil : { [weak self] in
                self?.store.delete(slot: slot)
                self?.closeEditor()
            }
        )

        let host = NSHostingController(rootView: view)
        let win = NSWindow(contentViewController: host)
        win.title       = "Macro Editor — Slot \(slot)"
        win.styleMask   = [.titled, .closable]
        win.isReleasedWhenClosed = false
        win.setContentSize(NSSize(width: 480, height: 560))
        win.center()
        win.delegate = self
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        editorWindow = win
    }

    private func closeEditor() {
        editorWindow?.close()
        editorWindow = nil
    }

    // ── settings window ───────────────────────────────────────────────────────

    @objc private func openSettings() {
        if let w = settingsWindow {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let host = NSHostingController(
            rootView: SettingsView().environmentObject(settings)
        )
        let win = NSWindow(contentViewController: host)
        win.title = "MacroDeck Settings"
        win.styleMask = [.titled, .closable]
        win.isReleasedWhenClosed = false
        win.setContentSize(NSSize(width: 460, height: 420))
        win.center()
        win.delegate = self
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = win
    }

    // Clear references when the user closes a managed window from the title bar.
    func windowWillClose(_ notification: Notification) {
        guard let w = notification.object as? NSWindow else { return }
        if w === editorWindow   { editorWindow   = nil }
        if w === settingsWindow { settingsWindow = nil }
    }

    // ── permissions ───────────────────────────────────────────────────────────

    private func promptForAccessibilityIfNeeded() {
        if !Permissions.hasAccessibility() {
            Permissions.requestAccessibility()
        }
    }
}
