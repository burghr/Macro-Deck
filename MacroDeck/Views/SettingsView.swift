import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings

    @State private var showIconPicker = false

    var body: some View {
        Form {
            Section("Menu bar") {
                HStack {
                    Text("Icon")
                    Spacer()
                    Button {
                        showIconPicker = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: settings.menuBarIcon)
                                .font(.system(size: 14))
                            Text(settings.menuBarIcon)
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.bordered)
                    .popover(isPresented: $showIconPicker, arrowEdge: .bottom) {
                        SymbolPickerView(selection: $settings.menuBarIcon) {
                            showIconPicker = false
                        }
                    }
                }
            }

            Section("Popover") {
                HStack {
                    Text("Toggle hotkey")
                    Spacer()
                    HotkeyField(hotkey: $settings.toggleHotkey)
                }
            }

            Section("Grid") {
                Stepper("Columns: \(settings.gridCols)",
                        value: $settings.gridCols, in: 1...10)
                Stepper("Rows: \(settings.gridRows)",
                        value: $settings.gridRows, in: 1...10)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 420)
    }
}
