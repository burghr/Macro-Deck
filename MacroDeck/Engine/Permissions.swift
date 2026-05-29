import Foundation
import AppKit
import ApplicationServices

enum Permissions {
    static func hasAccessibility() -> Bool {
        AXIsProcessTrustedWithOptions(nil)
    }

    /// Triggers the system prompt for Accessibility.
    static func requestAccessibility() {
        let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    /// Opens System Settings → Privacy & Security → <pane>.
    /// pane = "Accessibility" or "ListenEvent" (Input Monitoring).
    static func openSecurityPane(_ pane: String) {
        let raw = "x-apple.systempreferences:com.apple.preference.security?Privacy_\(pane)"
        guard let url = URL(string: raw) else { return }
        NSWorkspace.shared.open(url)
    }
}
