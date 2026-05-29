import SwiftUI

struct PopupView: View {
    @EnvironmentObject var store:    MacroStore
    @EnvironmentObject var settings: AppSettings

    /// Called by tiles that ask to dismiss (i.e. macro ran with keep_open == false).
    /// Injected by AppDelegate; SwiftUI's @Environment(\.dismiss) isn't wired
    /// up to NSPopover.
    var onDismissRequested: () -> Void = {}
    var onEditRequested:    (Int) -> Void = { _ in }

    private let tileSize: CGFloat = 110
    private let spacing:  CGFloat = 8

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.fixed(tileSize), spacing: spacing),
            count: settings.gridCols
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("MacroDeck")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)

            LazyVGrid(columns: columns, spacing: spacing) {
                ForEach(1...(settings.gridCols * settings.gridRows), id: \.self) { slot in
                    MacroTile(
                        slot:     slot,
                        macro:    store.get(slot: slot),
                        onRun:    { run(slot: slot) },
                        onEdit:   { edit(slot: slot) },
                        onDelete: { store.delete(slot: slot) }
                    )
                    .frame(width: tileSize, height: tileSize * 0.74)
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
        }
        .frame(width: CGFloat(settings.gridCols) * tileSize
                    + CGFloat(settings.gridCols - 1) * spacing
                    + 20)
    }

    private func run(slot: Int) {
        guard let m = store.get(slot: slot) else { return }
        Player.shared.run(macro: m)
        if !m.keepOpen { onDismissRequested() }
    }

    private func edit(slot: Int) {
        onDismissRequested()
        onEditRequested(slot)
    }
}
