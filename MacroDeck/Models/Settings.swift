import Foundation
import Combine

final class AppSettings: ObservableObject {
    @Published var toggleHotkey: String = "ctrl+shift+m"    { didSet { save() } }
    @Published var gridCols: Int        = 4                 { didSet { save() } }
    @Published var gridRows: Int        = 3                 { didSet { save() } }
    @Published var cardOpacity: Double  = 0.72              { didSet { save() } }
    @Published var tileOpacity: Double  = 1.0               { didSet { save() } }
    @Published var menuBarIcon: String  = "square.grid.2x2" { didSet { save() } }

    private let url: URL

    // On-disk shape — snake_case keys match the legacy format so existing
    // settings.json files load unchanged.
    private struct Persist: Codable {
        var toggle_hotkey: String?
        var grid_cols: Int?
        var grid_rows: Int?
        var card_opacity: Double?
        var tile_opacity: Double?
        var menu_bar_icon: String?
    }

    init() {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".mac-macro", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.url = dir.appendingPathComponent("settings.json")
        load()
    }

    private func load() {
        guard let data = try? Data(contentsOf: url),
              let p = try? JSONDecoder().decode(Persist.self, from: data) else { return }
        if let v = p.toggle_hotkey { toggleHotkey = v }
        if let v = p.grid_cols     { gridCols     = v }
        if let v = p.grid_rows     { gridRows     = v }
        if let v = p.card_opacity  { cardOpacity  = v }
        if let v = p.tile_opacity  { tileOpacity  = v }
        if let v = p.menu_bar_icon { menuBarIcon  = v }
    }

    private func save() {
        let p = Persist(
            toggle_hotkey: toggleHotkey,
            grid_cols:     gridCols,
            grid_rows:     gridRows,
            card_opacity:  cardOpacity,
            tile_opacity:  tileOpacity,
            menu_bar_icon: menuBarIcon
        )
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? enc.encode(p) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
