import Foundation
import AppKit

final class Player {
    static let shared = Player()
    private init() {}

    func run(macro m: Macro) {
        switch m.kind {
        case .text:  typeText(m.text)
        case .cmd:   runShell(m.cmd)
        case .media: MediaKey.post(action: m.media)
        case .keys:  playKeys(m.events)
        }
    }

    // ── text ──────────────────────────────────────────────────────────────────
    // osascript keystroke handles per-line typing and key code 36 = Return.

    func typeText(_ text: String) {
        let lines = text.components(separatedBy: "\n")
        var parts: [String] = []
        for (i, line) in lines.enumerated() {
            if !line.isEmpty {
                let escaped = line
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "\"", with: "\\\"")
                parts.append("keystroke \"\(escaped)\"")
            }
            if i < lines.count - 1 {
                parts.append("key code 36")
            }
        }
        guard !parts.isEmpty else { return }
        let body = parts.joined(separator: "\n    ")
        let script = "tell application \"System Events\"\n    \(body)\nend tell"
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
            self.runOsascript(script)
        }
    }

    private func runOsascript(_ script: String) {
        let proc = Process()
        proc.launchPath = "/usr/bin/osascript"
        proc.arguments  = ["-e", script]
        try? proc.run()
    }

    // ── shell ─────────────────────────────────────────────────────────────────

    func runShell(_ cmd: String) {
        let proc = Process()
        proc.launchPath = "/bin/bash"
        proc.arguments  = ["-c", cmd]
        try? proc.run()
    }

    // ── recorded keys ─────────────────────────────────────────────────────────
    // Posts CGEvents directly. Tracks modifier state so non-modifier events
    // carry the right CGEvent.flags — without this, ⌃/ posts as plain "/" and
    // the target app beeps.

    func playKeys(_ events: [KeyEvent]) {
        DispatchQueue.global().async {
            Thread.sleep(forTimeInterval: 0.1)
            var modFlags: CGEventFlags = []
            for e in events {
                if e.d > 0.005 {
                    Thread.sleep(forTimeInterval: e.d)
                }
                guard let code = KeyMap.cgKeyCode(for: e.k) else { continue }
                let down = e.t == "p"

                // Update modifier state BEFORE posting so the modifier-key
                // event itself reflects the new flags.
                if let mod = Self.modifierFlag(forKeyCode: code) {
                    if down { modFlags.insert(mod) } else { modFlags.remove(mod) }
                }

                let src = CGEventSource(stateID: .combinedSessionState)
                guard let ev = CGEvent(keyboardEventSource: src,
                                       virtualKey: code, keyDown: down) else { continue }
                ev.flags = modFlags
                ev.post(tap: .cghidEventTap)
            }
        }
    }

    private static func modifierFlag(forKeyCode code: CGKeyCode) -> CGEventFlags? {
        switch code {
        case 0x38, 0x3C: return .maskShift
        case 0x3B, 0x3E: return .maskControl
        case 0x3A, 0x3D: return .maskAlternate
        case 0x37, 0x36: return .maskCommand
        case 0x39:       return .maskAlphaShift   // caps lock
        default:         return nil
        }
    }
}
