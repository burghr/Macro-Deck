import Foundation
import AppKit

/// Posts NSSystemDefined HID consumer events for the media keys, so playing
/// vol_up etc. triggers the on-screen HUD + feedback tink just like pressing
/// the physical key on the keyboard.
enum MediaKey {
    private static let codes: [String: Int32] = [
        "vol_up":           0,
        "vol_down":         1,
        "brightness_up":    2,
        "brightness_down":  3,
        "mute":             7,
        "play_pause":      16,
        "next":            17,
        "prev":            18,
    ]

    static func post(action: String) {
        guard let code = codes[action] else { return }
        for down in [0xa, 0xb] {           // 0xa = key down, 0xb = key up
            let data1 = (Int(code) << 16) | (down << 8)
            let flags = NSEvent.ModifierFlags(rawValue: UInt(down << 8))
            guard let ev = NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: flags,
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                subtype: 8,                // NX_SUBTYPE_AUX_CONTROL_BUTTONS
                data1: data1,
                data2: -1
            ) else { continue }
            ev.cgEvent?.post(tap: .cghidEventTap)
        }
    }
}
