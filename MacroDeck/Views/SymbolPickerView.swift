import SwiftUI

struct SymbolPickerView: View {
    @Binding var selection: String
    var onPick: () -> Void = {}

    @State private var search: String = ""

    private let columns = [GridItem(.adaptive(minimum: 44, maximum: 44), spacing: 4)]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search", text: $search)
                    .textFieldStyle(.plain)
                if !search.isEmpty {
                    Button { search = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.bar)
            Divider()
            ScrollView {
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(filtered, id: \.self) { sym in
                        Button {
                            selection = sym
                            onPick()
                        } label: {
                            Image(systemName: sym)
                                .font(.system(size: 18))
                                .frame(width: 40, height: 40)
                                .background {
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(sym == selection
                                              ? Color.accentColor.opacity(0.35)
                                              : Color.white.opacity(0.04))
                                }
                        }
                        .buttonStyle(.plain)
                        .help(sym)
                    }
                }
                .padding(10)
            }
        }
        .frame(width: 360, height: 420)
    }

    private var filtered: [String] {
        if search.isEmpty { return Self.curated }
        let q = search.lowercased()
        return Self.curated.filter { $0.contains(q) }
    }

    // Curated selection — common macro icons across actions, media, system,
    // communication, files, text, navigation, status, numerics and symbols.
    static let curated: [String] = [
        // Playback / media
        "play.fill", "pause.fill", "stop.fill", "forward.fill", "backward.fill",
        "forward.end.fill", "backward.end.fill", "playpause.fill", "repeat", "shuffle",
        "speaker.wave.3.fill", "speaker.wave.2.fill", "speaker.wave.1.fill",
        "speaker.fill", "speaker.slash.fill",
        "mic.fill", "mic.slash.fill", "music.note", "music.quarternote.3", "headphones",
        "camera.fill", "video.fill", "photo.fill", "film.fill",

        // Communication
        "envelope.fill", "message.fill", "phone.fill", "phone.down.fill",
        "bubble.left.fill", "bubble.right.fill", "paperplane.fill", "bell.fill",
        "bell.slash.fill", "megaphone.fill",

        // Tools
        "hammer.fill", "wrench.and.screwdriver.fill", "screwdriver.fill", "wrench.fill",
        "scissors", "paintbrush.fill", "ruler.fill", "pencil", "pencil.tip", "eyedropper",
        "magnifyingglass",

        // System
        "gear", "gearshape.fill", "gearshape.2.fill", "terminal.fill", "command",
        "option", "control", "capslock", "escape", "keyboard", "keyboard.fill",
        "mouse.fill", "cursorarrow.click", "cursorarrow", "power", "lock.fill",
        "lock.open.fill", "eye.fill", "eye.slash.fill", "hand.raised.fill",

        // Files & storage
        "folder.fill", "folder.fill.badge.plus", "doc.fill", "doc.text.fill",
        "doc.on.doc.fill", "doc.richtext.fill", "square.and.arrow.up",
        "square.and.arrow.down", "archivebox.fill", "tray.fill", "trash.fill",
        "paperclip",

        // Web / network
        "globe", "link", "network", "wifi", "antenna.radiowaves.left.and.right",
        "arrow.up.right.square.fill", "safari.fill", "cloud.fill", "icloud.fill",

        // Text formatting
        "textformat", "textformat.size", "textformat.abc", "text.alignleft",
        "text.alignright", "text.aligncenter", "character.cursor.ibeam",
        "paragraphsign", "list.bullet", "list.number", "checkmark",

        // Status
        "checkmark.circle.fill", "xmark.circle.fill", "exclamationmark.triangle.fill",
        "info.circle.fill", "questionmark.circle.fill", "star.fill", "heart.fill",
        "flag.fill", "bookmark.fill", "tag.fill",

        // Navigation / UI
        "plus", "minus", "plus.circle.fill", "minus.circle.fill",
        "plus.square.fill", "minus.square.fill", "arrow.up", "arrow.down",
        "arrow.left", "arrow.right", "arrow.clockwise", "arrow.counterclockwise",
        "arrow.uturn.left", "arrow.uturn.right", "chevron.up", "chevron.down",
        "chevron.left", "chevron.right", "square.and.pencil", "ellipsis",
        "ellipsis.circle.fill",

        // Layouts / grids
        "square.grid.2x2", "square.grid.3x3", "rectangle.grid.2x2.fill",
        "list.dash", "sidebar.left", "sidebar.right", "macwindow",

        // Effects / fun
        "bolt.fill", "bolt.slash.fill", "flame.fill", "drop.fill", "sparkles",
        "wand.and.stars", "sun.max.fill", "moon.fill", "lightbulb.fill",
        "lightbulb.slash.fill", "brain", "brain.head.profile",

        // People / location
        "person.fill", "person.2.fill", "person.circle.fill", "person.crop.circle.fill",
        "location.fill", "mappin.circle.fill", "map.fill",

        // Time
        "calendar", "clock.fill", "timer", "alarm.fill", "hourglass",

        // Commerce
        "gift.fill", "cart.fill", "creditcard.fill", "dollarsign.circle.fill",

        // Numbers
        "1.circle.fill", "2.circle.fill", "3.circle.fill", "4.circle.fill",
        "5.circle.fill", "6.circle.fill", "7.circle.fill", "8.circle.fill",
        "9.circle.fill", "0.circle.fill",
    ]
}
