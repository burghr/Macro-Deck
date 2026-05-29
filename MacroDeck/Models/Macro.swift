import Foundation

enum MacroKind: String, Codable {
    case keys, text, cmd, media
}

struct KeyEvent: Codable, Hashable {
    var t: String   // "p" press / "r" release
    var k: String   // key string (pynput-style)
    var d: Double   // delay before event (seconds)
}

struct Macro: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var kind: MacroKind = .keys
    var events: [KeyEvent] = []
    var text: String = ""
    var cmd: String = ""
    var media: String = ""
    var symbol: String = ""     // SF Symbol name
    var tint: String = ""       // named ("blue") or hex ("#1E88E5")
    var keepOpen: Bool = false

    enum CodingKeys: String, CodingKey {
        case id, name, kind, events, text, cmd, media, symbol, tint
        case keepOpen = "keep_open"
    }

    init(id: String = UUID().uuidString, name: String = "New Macro") {
        self.id = id
        self.name = name
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id        = try c.decodeIfPresent(String.self,     forKey: .id)     ?? UUID().uuidString
        self.name      = try c.decodeIfPresent(String.self,     forKey: .name)   ?? "Macro"
        self.kind      = try c.decodeIfPresent(MacroKind.self,  forKey: .kind)   ?? .keys
        self.events    = try c.decodeIfPresent([KeyEvent].self, forKey: .events) ?? []
        self.text      = try c.decodeIfPresent(String.self,     forKey: .text)   ?? ""
        self.cmd       = try c.decodeIfPresent(String.self,     forKey: .cmd)    ?? ""
        self.media     = try c.decodeIfPresent(String.self,     forKey: .media)  ?? ""
        self.symbol    = try c.decodeIfPresent(String.self,     forKey: .symbol) ?? ""
        self.tint      = try c.decodeIfPresent(String.self,     forKey: .tint)   ?? ""
        self.keepOpen  = try c.decodeIfPresent(Bool.self,       forKey: .keepOpen) ?? false
    }
}
