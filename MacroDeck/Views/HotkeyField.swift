import SwiftUI
import AppKit

/// A small recorder field that captures the next modifier+key press and
/// writes the result as a "ctrl+shift+m"-style string into a binding.
struct HotkeyField: View {
    @Binding var hotkey: String

    @State private var recording = false
    @State private var monitor:   Any?

    var body: some View {
        Button {
            if recording { stop() } else { start() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "keyboard")
                Text(recording
                     ? "Type combo… (Esc to cancel)"
                     : prettyShortcut(hotkey))
                    .frame(minWidth: 120, alignment: .leading)
                    .foregroundStyle(recording ? .orange : .primary)
                    .font(.system(.body, design: .monospaced))
            }
        }
        .buttonStyle(.bordered)
        .onDisappear { stop() }
    }

    // ── capture ───────────────────────────────────────────────────────────────

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { ev in
            // Escape cancels without changing the hotkey.
            if ev.keyCode == 0x35 {
                stop()
                return nil
            }
            let mods = ev.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let hasMod = mods.contains(.command) || mods.contains(.control)
                      || mods.contains(.option)  || mods.contains(.shift)
            // Require at least one modifier so we don't trap a plain letter.
            guard hasMod, let combo = combo(from: ev, mods: mods) else { return nil }
            hotkey = combo
            stop()
            return nil
        }
    }

    private func stop() {
        recording = false
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
    }

    private func combo(from event: NSEvent, mods: NSEvent.ModifierFlags) -> String? {
        var parts: [String] = []
        if mods.contains(.control) { parts.append("ctrl") }
        if mods.contains(.option)  { parts.append("alt") }
        if mods.contains(.shift)   { parts.append("shift") }
        if mods.contains(.command) { parts.append("cmd") }

        if let special = specialName(for: event.keyCode) {
            parts.append(special)
        } else if let chars = event.charactersIgnoringModifiers,
                  let c = chars.first,
                  c.isLetter || c.isNumber || "-=[]\\;',./`".contains(c) {
            parts.append(String(c).lowercased())
        } else {
            return nil
        }
        return parts.joined(separator: "+")
    }

    private func specialName(for kc: UInt16) -> String? {
        switch kc {
        case 0x24: return "enter"
        case 0x30: return "tab"
        case 0x31: return "space"
        case 0x7A: return "f1"; case 0x78: return "f2"; case 0x63: return "f3"
        case 0x76: return "f4"; case 0x60: return "f5"; case 0x61: return "f6"
        case 0x62: return "f7"; case 0x64: return "f8"; case 0x65: return "f9"
        case 0x6D: return "f10"; case 0x67: return "f11"; case 0x6F: return "f12"
        default:   return nil
        }
    }
}

/// "ctrl+shift+m" → "⌃⇧M" for display.
func prettyShortcut(_ s: String) -> String {
    let parts = s.lowercased().split(separator: "+").map(String.init)
    var out = ""
    var key = ""
    for p in parts {
        switch p {
        case "ctrl", "control":  out += "⌃"
        case "alt",  "option":   out += "⌥"
        case "shift":            out += "⇧"
        case "cmd",  "command":  out += "⌘"
        default: key = p
        }
    }
    return out + key.uppercased()
}
