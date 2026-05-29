import SwiftUI
import AppKit

/// SwiftUI wrapper around NSVisualEffectView. Use as `.background(VibrancyView())`
/// or in a ZStack to give content real macOS blur.
struct VibrancyView: NSViewRepresentable {
    var material: NSVisualEffectView.Material         = .popover
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var state: NSVisualEffectView.State               = .active

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material      = material
        v.blendingMode  = blendingMode
        v.state         = state
        v.isEmphasized  = true
        return v
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material     = material
        view.blendingMode = blendingMode
        view.state        = state
    }
}
