import Foundation
import Combine

final class MacroStore: ObservableObject {
    @Published private(set) var macros: [Int: Macro] = [:]

    private let url: URL

    init() {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".mac-macro", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.url = dir.appendingPathComponent("macros.json")
        load()
    }

    func get(slot: Int) -> Macro? { macros[slot] }

    func set(slot: Int, _ macro: Macro) {
        macros[slot] = macro
        save()
    }

    func delete(slot: Int) {
        macros.removeValue(forKey: slot)
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: url) else { return }
        // JSON shape: { "1": Macro, "2": Macro, ... }
        guard let raw = try? JSONDecoder().decode([String: Macro].self, from: data) else {
            return
        }
        var out: [Int: Macro] = [:]
        for (k, v) in raw {
            if let n = Int(k) { out[n] = v }
        }
        self.macros = out
    }

    private func save() {
        let strKeyed: [String: Macro] = Dictionary(
            uniqueKeysWithValues: macros.map { (String($0.key), $0.value) }
        )
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? enc.encode(strKeyed) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
