import Foundation
import CoreGraphics

/// Convert pynput-style key names (as stored by the Python recorder) into
/// CGKeyCode for CGEvent playback. Incomplete — covers common keys; recorded
/// macros with rare keys may not replay until extended.
enum KeyMap {
    static func cgKeyCode(for name: String) -> CGKeyCode? {
        // pynput dumps things like "Key.shift" or "'a'" — normalise.
        var s = name
        if s.hasPrefix("Key.") { s.removeFirst(4) }
        if s.count == 3, s.first == "'", s.last == "'" {
            s = String(s.dropFirst().dropLast())
        }

        switch s.lowercased() {
        case "shift", "shift_l":            return 0x38
        case "shift_r":                     return 0x3C
        case "ctrl", "ctrl_l":              return 0x3B
        case "ctrl_r":                      return 0x3E
        case "alt", "alt_l", "option":      return 0x3A
        case "alt_r", "option_r":           return 0x3D
        case "cmd", "cmd_l", "command":     return 0x37
        case "cmd_r":                       return 0x36
        case "space":                       return 0x31
        case "enter", "return":             return 0x24
        case "tab":                         return 0x30
        case "esc", "escape":               return 0x35
        case "backspace":                   return 0x33
        case "delete":                      return 0x75
        case "up":                          return 0x7E
        case "down":                        return 0x7D
        case "left":                        return 0x7B
        case "right":                       return 0x7C
        case "caps_lock":                   return 0x39
        case "f1":                          return 0x7A
        case "f2":                          return 0x78
        case "f3":                          return 0x63
        case "f4":                          return 0x76
        case "f5":                          return 0x60
        case "f6":                          return 0x61
        case "f7":                          return 0x62
        case "f8":                          return 0x64
        case "f9":                          return 0x65
        case "f10":                         return 0x6D
        case "f11":                         return 0x67
        case "f12":                         return 0x6F
        default: break
        }

        if s.count == 1, let c = s.lowercased().first {
            return charCode(c)
        }
        return nil
    }

    // Built once at first call; keeps the literal small enough for the
    // type-checker (the all-in-one literal was hitting the "unable to
    // type-check this expression in reasonable time" wall).
    private static let charMap: [Character: CGKeyCode] = {
        var m: [Character: CGKeyCode] = [:]
        let pairs: [(Character, CGKeyCode)] = [
            ("a", 0x00), ("s", 0x01), ("d", 0x02), ("f", 0x03),
            ("h", 0x04), ("g", 0x05), ("z", 0x06), ("x", 0x07),
            ("c", 0x08), ("v", 0x09), ("b", 0x0B), ("q", 0x0C),
            ("w", 0x0D), ("e", 0x0E), ("r", 0x0F), ("y", 0x10),
            ("t", 0x11), ("1", 0x12), ("2", 0x13), ("3", 0x14),
            ("4", 0x15), ("6", 0x16), ("5", 0x17), ("=", 0x18),
            ("9", 0x19), ("7", 0x1A), ("-", 0x1B), ("8", 0x1C),
            ("0", 0x1D), ("]", 0x1E), ("o", 0x1F), ("u", 0x20),
            ("[", 0x21), ("i", 0x22), ("p", 0x23), ("l", 0x25),
            ("j", 0x26), ("'", 0x27), ("k", 0x28), (";", 0x29),
            ("\\", 0x2A), (",", 0x2B), ("/", 0x2C), ("n", 0x2D),
            ("m", 0x2E), (".", 0x2F), ("`", 0x32),
        ]
        for (c, code) in pairs { m[c] = code }
        return m
    }()

    private static func charCode(_ c: Character) -> CGKeyCode? {
        charMap[c]
    }
}
