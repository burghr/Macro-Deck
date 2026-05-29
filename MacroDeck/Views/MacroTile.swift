import SwiftUI

struct MacroTile: View {
    let slot:     Int
    let macro:    Macro?
    let onRun:    () -> Void
    let onEdit:   () -> Void
    let onDelete: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: { macro != nil ? onRun() : onEdit() }) {
            VStack(spacing: 4) {
                Spacer(minLength: 0)
                content
                Spacer(minLength: 0)
                shortcut
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.vertical, 6)
            .padding(.horizontal, 6)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(fillColor)
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(borderColor, lineWidth: 1)
                    }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .contextMenu {
            if macro != nil {
                Button("Run",    action: onRun)
                Divider()
                Button("Edit…",  action: onEdit)
                Button("Delete", role: .destructive, action: onDelete)
            } else {
                Button("Add Macro…", action: onEdit)
            }
        }
    }

    // ── pieces ────────────────────────────────────────────────────────────────

    @ViewBuilder
    private var content: some View {
        if let m = macro {
            icon(for: m)
                .padding(.bottom, 2)
            Text(m.name)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 2)
        } else {
            Image(systemName: "plus")
                .font(.system(size: 16, weight: .light))
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private func icon(for m: Macro) -> some View {
        if !m.symbol.isEmpty {
            Image(systemName: m.symbol)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(tintColor(m.tint))
                .symbolRenderingMode(.hierarchical)
        }
    }

    private var shortcut: some View {
        let label: String
        if slot <= 10 {
            label = "⌃\(slot % 10)"
        } else {
            label = "#\(slot)"
        }
        return Text(label)
            .font(.system(size: 10, design: .rounded))
            .foregroundStyle(.tertiary)
    }

    // ── styling ───────────────────────────────────────────────────────────────

    private var fillColor: Color {
        if macro == nil {
            return Color.white.opacity(hovering ? 0.06 : 0.03)
        }
        return Color.white.opacity(hovering ? 0.12 : 0.07)
    }

    private var borderColor: Color {
        if macro == nil {
            return Color.white.opacity(0.08)
        }
        return Color.white.opacity(hovering ? 0.22 : 0.12)
    }

    private func tintColor(_ name: String) -> Color {
        if name.isEmpty { return .secondary }
        switch name.lowercased() {
        case "red":    return .red
        case "orange": return .orange
        case "yellow": return .yellow
        case "green":  return .green
        case "mint":   return .mint
        case "teal":   return .teal
        case "cyan":   return .cyan
        case "blue":   return .blue
        case "indigo": return .indigo
        case "purple": return .purple
        case "pink":   return .pink
        case "brown":  return .brown
        default:       break
        }
        if let c = Color(hex: name) { return c }
        return .secondary
    }
}

private extension Color {
    init?(hex: String) {
        var s = hex
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt64(s, radix: 16) else { return nil }
        self.init(
            red:   Double((v >> 16) & 0xff) / 255,
            green: Double((v >>  8) & 0xff) / 255,
            blue:  Double( v        & 0xff) / 255
        )
    }
}
