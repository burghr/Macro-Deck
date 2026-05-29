import SwiftUI

struct EditorView: View {
    let slot: Int
    @State private var draft: Macro
    @StateObject private var recorder = Recorder()
    @State private var showSymbolPicker = false
    @State private var showBulkDelay    = false
    @State private var bulkDelayMs      = 50

    let onSave:   (Macro) -> Void
    let onCancel: () -> Void
    let onDelete: (() -> Void)?

    init(
        slot:     Int,
        initial:  Macro,
        onSave:   @escaping (Macro) -> Void,
        onCancel: @escaping () -> Void,
        onDelete: (() -> Void)? = nil
    ) {
        self.slot     = slot
        self._draft   = State(initialValue: initial)
        self.onSave   = onSave
        self.onCancel = onCancel
        self.onDelete = onDelete
    }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $draft.name)
                Picker("Kind", selection: $draft.kind) {
                    Text("Keys").tag(MacroKind.keys)
                    Text("Text").tag(MacroKind.text)
                    Text("Command").tag(MacroKind.cmd)
                    Text("Media").tag(MacroKind.media)
                }
                .pickerStyle(.segmented)
            }

            Section(headerForKind) {
                switch draft.kind {
                case .text:
                    TextEditor(text: $draft.text)
                        .frame(minHeight: 100)
                        .font(.system(.body, design: .monospaced))
                case .cmd:
                    TextField("Shell command", text: $draft.cmd,
                              prompt: Text("e.g. open -a Safari"))
                        .font(.system(.body, design: .monospaced))
                case .media:
                    Picker("Action", selection: $draft.media) {
                        ForEach(Self.mediaActions, id: \.0) { value, label in
                            Text(label).tag(value)
                        }
                    }
                case .keys:
                    keysPanel
                }
            }

            Section("Appearance") {
                symbolRow
                TextField("Tint", text: $draft.tint,
                          prompt: Text("blue, #1E88E5, …"))
            }

            Section {
                Toggle("Keep popup open after running", isOn: $draft.keepOpen)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 560)
        .safeAreaInset(edge: .bottom) {
            HStack {
                if let del = onDelete {
                    Button(role: .destructive, action: del) {
                        Text("Delete")
                    }
                }
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.escape, modifiers: [])
                Button("Save") {
                    if recorder.isRecording { recorder.stop() }
                    onSave(draft)
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.bar)
        }
        .onDisappear { recorder.stop() }
    }

    // ── keys panel ────────────────────────────────────────────────────────────

    private var keysPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button {
                    if recorder.isRecording {
                        recorder.stop()
                        draft.events = recorder.events
                    } else {
                        draft.events = []
                        recorder.start()
                    }
                } label: {
                    Label(
                        recorder.isRecording ? "Stop" : "Record",
                        systemImage: recorder.isRecording ? "stop.circle.fill" : "record.circle.fill"
                    )
                    .foregroundStyle(recorder.isRecording ? .red : .accentColor)
                }

                if !displayedEvents.isEmpty {
                    Button("Clear") {
                        recorder.clear()
                        draft.events = []
                    }
                }

                if !recorder.isRecording && !draft.events.isEmpty {
                    Button {
                        showBulkDelay = true
                    } label: {
                        Label("Set all delays…", systemImage: "clock.arrow.circlepath")
                    }
                    .popover(isPresented: $showBulkDelay, arrowEdge: .bottom) {
                        bulkDelayPopover
                    }
                }

                Spacer()

                Text("\(displayedEvents.count) event(s)")
                    .foregroundStyle(.secondary)
                    .font(.system(.body, design: .monospaced))
            }

            if recorder.isRecording {
                Label(
                    "Recording — switch to the target app and type. Requires Input Monitoring permission.",
                    systemImage: "info.circle"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }

            eventList
        }
    }

    private var displayedEvents: [KeyEvent] {
        recorder.isRecording ? recorder.events : draft.events
    }

    private var bulkDelayPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Set delay on every event")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                TextField("ms", value: $bulkDelayMs, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 70)
                Text("ms").foregroundStyle(.secondary)
                Spacer()
                Button("Apply") {
                    let d = max(0, Double(bulkDelayMs)) / 1000.0
                    for i in draft.events.indices {
                        draft.events[i].d = d
                    }
                    showBulkDelay = false
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: [])
            }
        }
        .padding(12)
        .frame(width: 240)
    }

    @ViewBuilder
    private var eventList: some View {
        let events = displayedEvents
        if events.isEmpty {
            Text("No events yet — click Record and type.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        } else {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Text("").frame(width: 18)
                    Text("Key")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Delay (ms)")
                        .frame(width: 78, alignment: .trailing)
                    if !recorder.isRecording {
                        Text("").frame(width: 20)
                    }
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                Divider()
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if recorder.isRecording {
                            // Live, read-only view while recording.
                            ForEach(Array(recorder.events.enumerated()), id: \.offset) { idx, ev in
                                EventRowReadOnly(event: ev)
                                if idx < recorder.events.count - 1 { Divider() }
                            }
                        } else {
                            // Bound view: delete + edit delay live.
                            ForEach(Array(draft.events.enumerated()), id: \.offset) { idx, _ in
                                EventRowEditable(
                                    event: $draft.events[idx],
                                    onDelete: { draft.events.remove(at: idx) }
                                )
                                if idx < draft.events.count - 1 { Divider() }
                            }
                        }
                    }
                }
                .frame(maxHeight: 180)
            }
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
    }

    // ── symbol row ────────────────────────────────────────────────────────────

    private var symbolRow: some View {
        HStack {
            Button {
                showSymbolPicker = true
            } label: {
                HStack(spacing: 8) {
                    if draft.symbol.isEmpty {
                        Image(systemName: "square.dashed")
                            .foregroundStyle(.tertiary)
                    } else {
                        Image(systemName: draft.symbol)
                            .foregroundStyle(.primary)
                    }
                    Text(draft.symbol.isEmpty ? "Choose SF Symbol…" : draft.symbol)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(draft.symbol.isEmpty ? .secondary : .primary)
                }
            }
            .buttonStyle(.bordered)
            .popover(isPresented: $showSymbolPicker, arrowEdge: .bottom) {
                SymbolPickerView(selection: $draft.symbol) {
                    showSymbolPicker = false
                }
            }
            Spacer()
            if !draft.symbol.isEmpty {
                Button { draft.symbol = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Clear symbol")
            }
        }
    }

    // ── helpers ───────────────────────────────────────────────────────────────

    private var headerForKind: String {
        switch draft.kind {
        case .keys:  return "Recorded keys"
        case .text:  return "Text to type"
        case .cmd:   return "Command"
        case .media: return "Media action"
        }
    }

    private static let mediaActions: [(String, String)] = [
        ("vol_up",          "Volume up"),
        ("vol_down",        "Volume down"),
        ("mute",            "Mute toggle"),
        ("play_pause",      "Play / Pause"),
        ("next",            "Next track"),
        ("prev",            "Previous track"),
        ("brightness_up",   "Brightness up"),
        ("brightness_down", "Brightness down"),
    ]
}

// Read-only row used while recording (events arrive live, can't be mutated yet).
private struct EventRowReadOnly: View {
    let event: KeyEvent
    var body: some View {
        HStack(spacing: 8) {
            EventArrow(t: event.t)
            Text(prettyKey(event.k))
                .font(.system(.caption, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
            Text("\(Int(event.d * 1000))")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 78, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
    }
}

// Editable row used after recording. Delay is bound; edits flow back into
// the macro draft via the array element binding.
private struct EventRowEditable: View {
    @Binding var event: KeyEvent
    let onDelete: () -> Void

    private var delayMs: Binding<Int> {
        Binding(
            get: { Int((event.d * 1000).rounded()) },
            set: { event.d = max(0, Double($0)) / 1000.0 }
        )
    }

    var body: some View {
        HStack(spacing: 8) {
            EventArrow(t: event.t)
            Text(prettyKey(event.k))
                .font(.system(.caption, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
            TextField("", value: delayMs, format: .number)
                .textFieldStyle(.plain)
                .font(.system(.caption, design: .monospaced))
                .multilineTextAlignment(.trailing)
                .frame(width: 78)
            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .frame(width: 20)
            .help("Delete row")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
    }
}

private struct EventArrow: View {
    let t: String
    var body: some View {
        Image(systemName: t == "p" ? "arrow.down" : "arrow.up")
            .frame(width: 18)
            .font(.caption.weight(.semibold))
            .foregroundStyle(t == "p" ? Color.green : Color.red)
    }
}

private func prettyKey(_ s: String) -> String {
    if s.hasPrefix("Key.") { return String(s.dropFirst(4)) }
    if s.count == 3, s.first == "'", s.last == "'" {
        return String(s.dropFirst().dropLast())
    }
    return s
}
