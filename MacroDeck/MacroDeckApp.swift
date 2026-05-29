import SwiftUI

@main
struct MacroDeckApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // No SwiftUI Scenes — the menu bar status item + popover are managed
        // by AppDelegate. The Settings scene is required by the App protocol
        // but emits no window.
        Settings { EmptyView() }
    }
}
