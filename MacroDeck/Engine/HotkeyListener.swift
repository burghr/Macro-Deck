import Foundation
import AppKit
import Carbon.HIToolbox

/// Global hotkey listener using the Carbon EventHotKey API.
/// Doesn't require Input Monitoring permission (Carbon hotkeys are delivered
/// through the Carbon event manager, not the HID system).
final class HotkeyListener {
    private var refs: [EventHotKeyRef?] = []
    private var handler: EventHandlerRef?
    private let onSlot:   (Int) -> Void
    private let onToggle: () -> Void
    private var toggleHotkey: String

    // Keyboard codes for Ctrl+1 .. Ctrl+0, in slot order (slot 1..10).
    private static let slotKeyCodes: [UInt32] = [
        0x12, 0x13, 0x14, 0x15, 0x17,
        0x16, 0x1A, 0x1C, 0x19, 0x1D,
    ]

    init(
        toggleHotkey: String,
        onSlot:   @escaping (Int) -> Void,
        onToggle: @escaping () -> Void
    ) {
        self.toggleHotkey = toggleHotkey
        self.onSlot       = onSlot
        self.onToggle     = onToggle
        installHandler()
        registerAll()
    }

    deinit {
        unregisterAll()
        if let h = handler { RemoveEventHandler(h) }
    }

    /// Tears down all hotkey registrations and re-registers with a new toggle
    /// combo. Slot bindings are unchanged.
    func updateToggleHotkey(_ newValue: String) {
        guard newValue != toggleHotkey else { return }
        toggleHotkey = newValue
        unregisterAll()
        registerAll()
    }

    private func unregisterAll() {
        for ref in refs {
            if let r = ref { UnregisterEventHotKey(r) }
        }
        refs.removeAll()
    }

    // ── handler ───────────────────────────────────────────────────────────────

    private func installHandler() {
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind:  UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, userData) -> OSStatus in
                guard let event = event, let userData = userData else { return noErr }
                var hid = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hid
                )
                let listener = Unmanaged<HotkeyListener>.fromOpaque(userData).takeUnretainedValue()
                listener.dispatch(id: hid.id)
                return noErr
            },
            1, &spec, selfPtr, &handler
        )
    }

    private func dispatch(id: UInt32) {
        if id == 1 {
            DispatchQueue.main.async { self.onToggle() }
        } else if (101...110).contains(id) {
            let slot = Int(id - 100)
            DispatchQueue.main.async { self.onSlot(slot) }
        }
    }

    // ── registration ──────────────────────────────────────────────────────────

    private func registerAll() {
        if let (keyCode, mods) = Self.parse(toggleHotkey) {
            register(keyCode: keyCode, modifiers: mods, id: 1)
        }
        // Slot hotkeys: Ctrl+1..0 → slot 1..10 (id = 101..110)
        for (i, code) in HotkeyListener.slotKeyCodes.enumerated() {
            register(keyCode: code, modifiers: UInt32(controlKey), id: UInt32(101 + i))
        }
    }

    /// "ctrl+shift+m" → (keyCode, Carbon modifier mask).
    static func parse(_ s: String) -> (keyCode: UInt32, modifiers: UInt32)? {
        let parts = s.lowercased().split(separator: "+").map(String.init)
        var mods: UInt32 = 0
        var keyCode: UInt32?
        for p in parts {
            switch p {
            case "ctrl", "control":  mods |= UInt32(controlKey)
            case "alt",  "option":   mods |= UInt32(optionKey)
            case "shift":            mods |= UInt32(shiftKey)
            case "cmd",  "command":  mods |= UInt32(cmdKey)
            default:
                if let code = KeyMap.cgKeyCode(for: p)
                    ?? KeyMap.cgKeyCode(for: "Key.\(p)") {
                    keyCode = UInt32(code)
                }
            }
        }
        guard let kc = keyCode else { return nil }
        return (kc, mods)
    }

    private func register(keyCode: UInt32, modifiers: UInt32, id: UInt32) {
        var ref: EventHotKeyRef?
        let hid = EventHotKeyID(signature: OSType(0x4D414352), id: id)  // 'MACR'
        let status = RegisterEventHotKey(
            keyCode, modifiers, hid,
            GetApplicationEventTarget(), 0, &ref
        )
        if status == noErr {
            refs.append(ref)
        }
    }
}
