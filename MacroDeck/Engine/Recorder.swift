import Foundation
import AppKit
import Combine

/// Captures key events globally and emits pynput-compatible KeyEvent records
/// so the existing macros.json format and KeyMap stay compatible.
/// Requires Input Monitoring permission for global capture; without it the
/// monitor installs but no events are delivered.
final class Recorder: ObservableObject {
    @Published private(set) var events:      [KeyEvent] = []
    @Published private(set) var isRecording: Bool       = false

    private var globalMonitor: Any?
    private var localMonitor:  Any?
    private var lastTime:      Date?
    private var lastFlags:     NSEvent.ModifierFlags = []

    func start() {
        guard !isRecording else { return }
        events.removeAll()
        lastTime  = nil
        lastFlags = []
        let mask: NSEvent.EventTypeMask = [.keyDown, .keyUp, .flagsChanged]
        // Global monitor: events in *other* apps (Input Monitoring required).
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] ev in
            self?.handle(ev)
        }
        // Local monitor: events in our own app. Return nil to consume so keys
        // pressed in the editor window get recorded instead of typed into
        // whichever text field happens to have focus.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] ev in
            self?.handle(ev)
            return nil
        }
        isRecording = true
    }

    func stop() {
        if let m = globalMonitor { NSEvent.removeMonitor(m) }
        if let m = localMonitor  { NSEvent.removeMonitor(m) }
        globalMonitor = nil
        localMonitor  = nil
        isRecording   = false
    }

    func clear() {
        events.removeAll()
    }

    // ── handling ──────────────────────────────────────────────────────────────

    private func handle(_ event: NSEvent) {
        let now   = Date()
        let delay = lastTime.map { now.timeIntervalSince($0) } ?? 0
        lastTime  = now

        var produced: [KeyEvent] = []

        switch event.type {
        case .keyDown:
            produced.append(KeyEvent(t: "p", k: keyName(event), d: delay))
        case .keyUp:
            produced.append(KeyEvent(t: "r", k: keyName(event), d: delay))
        case .flagsChanged:
            let changed = event.modifierFlags.symmetricDifference(lastFlags)
            for mod in [NSEvent.ModifierFlags.shift, .control, .option, .command, .capsLock] {
                if changed.contains(mod) {
                    let isDown = event.modifierFlags.contains(mod)
                    let name   = modifierName(mod, keyCode: event.keyCode)
                    if !name.isEmpty {
                        produced.append(KeyEvent(t: isDown ? "p" : "r", k: name, d: delay))
                    }
                }
            }
            lastFlags = event.modifierFlags
        default:
            break
        }

        guard !produced.isEmpty else { return }
        DispatchQueue.main.async {
            self.events.append(contentsOf: produced)
        }
    }

    // ── pynput-style key naming ───────────────────────────────────────────────

    private func keyName(_ event: NSEvent) -> String {
        if let s = specialKey(for: event.keyCode) { return s }
        if let chars = event.charactersIgnoringModifiers, let c = chars.first {
            return "'\(c)'"
        }
        return "<keycode \(event.keyCode)>"
    }

    private func specialKey(for keyCode: UInt16) -> String? {
        switch keyCode {
        case 0x24: return "Key.enter"
        case 0x30: return "Key.tab"
        case 0x31: return "Key.space"
        case 0x33: return "Key.backspace"
        case 0x35: return "Key.esc"
        case 0x75: return "Key.delete"
        case 0x7E: return "Key.up"
        case 0x7D: return "Key.down"
        case 0x7B: return "Key.left"
        case 0x7C: return "Key.right"
        case 0x7A: return "Key.f1"
        case 0x78: return "Key.f2"
        case 0x63: return "Key.f3"
        case 0x76: return "Key.f4"
        case 0x60: return "Key.f5"
        case 0x61: return "Key.f6"
        case 0x62: return "Key.f7"
        case 0x64: return "Key.f8"
        case 0x65: return "Key.f9"
        case 0x6D: return "Key.f10"
        case 0x67: return "Key.f11"
        case 0x6F: return "Key.f12"
        default:   return nil
        }
    }

    private func modifierName(_ mod: NSEvent.ModifierFlags, keyCode: UInt16) -> String {
        switch mod {
        case .shift:    return keyCode == 0x3C ? "Key.shift_r" : "Key.shift"
        case .control:  return keyCode == 0x3E ? "Key.ctrl_r"  : "Key.ctrl"
        case .option:   return keyCode == 0x3D ? "Key.alt_r"   : "Key.alt"
        case .command:  return keyCode == 0x36 ? "Key.cmd_r"   : "Key.cmd"
        case .capsLock: return "Key.caps_lock"
        default:        return ""
        }
    }
}
