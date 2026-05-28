from PyQt6.QtWidgets import (
    QDialog, QVBoxLayout, QHBoxLayout, QGridLayout, QLabel, QLineEdit,
    QPushButton, QTextEdit, QRadioButton, QButtonGroup, QWidget,
    QTableWidget, QTableWidgetItem, QHeaderView, QAbstractItemView,
    QApplication, QCheckBox, QComboBox,
)
from PyQt6.QtCore import Qt, pyqtSignal, QObject, QEvent
from PyQt6.QtGui import QFont, QColor

from store import MacroStore, Macro, KeyEvent
from engine import Recorder, HAVE_PYNPUT, check_input_monitoring

DIALOG_STYLE = """
QDialog        { background: #1a1a2e; color: #e0e0e0; }
QWidget        { background: #1a1a2e; color: #e0e0e0; }
QLabel         { color: #e0e0e0; font-size: 13px; background: transparent; }
QLineEdit, QTextEdit {
    background: #0d1117; color: #e0e0e0;
    border: 1px solid #333; border-radius: 6px;
    padding: 6px; font-size: 12px; font-family: monospace;
}
QRadioButton   { color: #c0c0c0; font-size: 12px; spacing: 6px; }
QRadioButton::indicator { width: 14px; height: 14px; }
QCheckBox      { color: #c0c0c0; font-size: 12px; spacing: 6px; }
QCheckBox::indicator { width: 14px; height: 14px; }
QComboBox {
    background: #0d1117; color: #e0e0e0;
    border: 1px solid #333; border-radius: 6px;
    padding: 5px 8px; font-size: 12px;
}
QComboBox QAbstractItemView {
    background: #0d1117; color: #e0e0e0;
    border: 1px solid #333; selection-background-color: #2a2a4a;
}
QPushButton {
    background: #2a2a4a; color: #e0e0e0;
    border: none; border-radius: 6px;
    padding: 7px 16px; font-size: 12px;
}
QPushButton:hover  { background: #3a3a6a; }
QPushButton#save   { background: #1E88E5; }
QPushButton#save:hover { background: #2196F3; }
QPushButton#rec    { background: #E53935; color: white; }
QPushButton#rec:hover  { background: #EF5350; }
QTableWidget {
    background: #0d1117; color: #e0e0e0;
    border: 1px solid #333; border-radius: 4px;
    gridline-color: #1e1e3a;
}
QTableWidget::item          { padding: 2px 4px; font-size: 11px; font-family: monospace; }
QTableWidget::item:selected { background: #2a2a4a; color: #e0e0e0; }
QHeaderView::section {
    background: #0d1117; color: #666;
    border: none; border-bottom: 1px solid #2e2e5a;
    padding: 3px 6px; font-size: 10px;
}
"""

EMOJIS = [
    "🚀", "⭐", "🔥", "💡", "🎯", "✅", "❌", "🔔", "⚡", "🔑",
    "📋", "📝", "🔍", "📧", "📞", "🖥️", "⌨️", "🔒", "💬", "📢",
    "😀", "👍", "👎", "🙏", "💪", "🤝", "👋", "👀", "🤔", "⚠️",
    "📁", "📊", "📈", "💻", "🛠️", "🧪", "🎮", "🎵", "📱", "🔧",
    "➡️", "⬅️", "⬆️", "⬇️", "🔄", "↩️", "⏩", "⏪", "▶️", "⏹️",
    "🐛", "🧹", "📌", "🏷️", "🗑️", "📤", "📥", "💾", "📎", "✂️",
]

_EMOJI_BTN = (
    "QPushButton{background:#0d1117;border:1px solid #2e2e5a;border-radius:6px;"
    "font-size:18px;padding:2px;min-width:34px;min-height:34px;}"
    "QPushButton:hover{background:#2a2a4a;border-color:#5a5a9a;}"
)
_CLEAR_BTN = (
    "QPushButton{background:#0d1117;border:1px solid #2e2e5a;border-radius:6px;"
    "color:#555;font-size:11px;padding:2px;min-width:34px;min-height:34px;}"
    "QPushButton:hover{background:#2a2a4a;border-color:#5a5a9a;color:#e0e0e0;}"
)


class EmojiPickerDialog(QDialog):
    def __init__(self, parent=None):
        super().__init__(parent)
        self.setWindowTitle("Pick an icon")
        self.setModal(True)
        self.chosen = None
        self.setStyleSheet("QDialog{background:#1a1a2e;}")
        self._build()

    def _build(self):
        lay = QVBoxLayout(self)
        lay.setContentsMargins(10, 10, 10, 10)
        lay.setSpacing(6)

        grid = QGridLayout()
        grid.setSpacing(4)

        cols = 10
        none_btn = QPushButton("✕ none")
        none_btn.setStyleSheet(_CLEAR_BTN)
        none_btn.setFixedSize(56, 34)
        none_btn.clicked.connect(lambda: self._pick(""))
        grid.addWidget(none_btn, 0, 0, 1, 2)

        for i, em in enumerate(EMOJIS):
            # offset by 2 cells for the none button
            pos = i + 2
            r, c = divmod(pos, cols)
            btn = QPushButton(em)
            btn.setStyleSheet(_EMOJI_BTN)
            btn.setFixedSize(34, 34)
            btn.clicked.connect(lambda _, e=em: self._pick(e))
            grid.addWidget(btn, r, c)

        lay.addLayout(grid)

    def _pick(self, emoji: str):
        self.chosen = emoji
        self.accept()


class _Sig(QObject):
    event_captured = pyqtSignal(object)


class MacroEditorDialog(QDialog):
    def __init__(self, slot: int, store: MacroStore,
                 record_start=None, record_stop=None, parent=None):
        super().__init__(parent)
        self.slot  = slot
        self.store = store
        self.macro = store.get(slot) or store.new_macro()
        self._events: list[KeyEvent] = [
            KeyEvent(**e) if isinstance(e, dict) else e for e in self.macro.events
        ]
        self._recording       = False
        self._recorder        = None
        self._record_start_cb = record_start
        self._record_stop_cb  = record_stop
        self._selected_icon   = self.macro.icon
        self._sig = _Sig()
        self._sig.event_captured.connect(self._on_event)

        QApplication.instance().installEventFilter(self)

        self.setWindowTitle(f"Macro Editor — Slot {slot}")
        self.setMinimumWidth(480)
        self.setModal(True)
        self.setStyleSheet(DIALOG_STYLE)
        self._build()

    # ── Layout ───────────────────────────────────────────────────────────────

    def _build(self):
        root = QVBoxLayout(self)
        root.setSpacing(12)
        root.setContentsMargins(20, 20, 20, 20)

        root.addLayout(self._name_row())
        root.addLayout(self._type_row())
        root.addLayout(self._options_row())

        self._keys_panel  = self._build_keys_panel()
        self._text_panel  = self._build_text_panel()
        self._cmd_panel   = self._build_cmd_panel()
        self._media_panel = self._build_media_panel()
        root.addWidget(self._keys_panel)
        root.addWidget(self._text_panel)
        root.addWidget(self._cmd_panel)
        root.addWidget(self._media_panel)
        self._refresh_panels()

        root.addLayout(self._btn_row())

    def _name_row(self):
        row = QHBoxLayout()
        self._icon_btn = QPushButton(self._selected_icon or "⊕")
        self._icon_btn.setFixedSize(34, 34)
        self._icon_btn.setAutoDefault(False)
        self._icon_btn.setToolTip("Pick an emoji icon")
        self._icon_btn.setStyleSheet(
            "QPushButton{background:#0d1117;border:1px solid #333;border-radius:6px;"
            "font-size:18px;padding:0px;}"
            "QPushButton:hover{background:#2a2a4a;border-color:#5a5a9a;}"
        )
        self._icon_btn.clicked.connect(self._pick_icon)
        row.addWidget(self._icon_btn)
        row.addSpacing(6)
        row.addWidget(QLabel("Name:"))
        self._name_edit = QLineEdit(self.macro.name)
        self._name_edit.setPlaceholderText("Macro name…")
        row.addWidget(self._name_edit)
        return row

    def _pick_icon(self):
        dlg = EmojiPickerDialog(self)
        if dlg.exec():
            self._selected_icon = dlg.chosen
            self._icon_btn.setText(self._selected_icon if self._selected_icon else "⊕")

    def _type_row(self):
        row = QHBoxLayout()
        row.addWidget(QLabel("Type:"))
        self._type_grp = QButtonGroup(self)
        for label, val in [("Key Sequence", "keys"), ("Type Text", "text"),
                           ("Command", "cmd"), ("Media Key", "media")]:
            rb = QRadioButton(label)
            rb.setProperty("kind", val)
            rb.setChecked(self.macro.kind == val)
            rb.toggled.connect(self._refresh_panels)
            self._type_grp.addButton(rb)
            row.addWidget(rb)
        row.addStretch()
        return row

    def _options_row(self):
        row = QHBoxLayout()
        self._keep_open_chk = QCheckBox("Keep popup open after running")
        self._keep_open_chk.setChecked(self.macro.keep_open)
        row.addWidget(self._keep_open_chk)
        row.addStretch()
        return row

    def _build_keys_panel(self):
        p = QWidget()
        lay = QVBoxLayout(p)
        lay.setContentsMargins(0, 0, 0, 0)
        lay.setSpacing(8)

        self._events_table = QTableWidget()
        self._events_table.setColumnCount(3)
        self._events_table.setHorizontalHeaderLabels(["", "Key", "Delay (ms)"])
        hdr = self._events_table.horizontalHeader()
        hdr.setSectionResizeMode(0, QHeaderView.ResizeMode.Fixed)
        hdr.setSectionResizeMode(1, QHeaderView.ResizeMode.Stretch)
        hdr.setSectionResizeMode(2, QHeaderView.ResizeMode.Fixed)
        self._events_table.setColumnWidth(0, 22)
        self._events_table.setColumnWidth(2, 76)
        self._events_table.verticalHeader().setVisible(False)
        self._events_table.setSelectionBehavior(QAbstractItemView.SelectionBehavior.SelectRows)
        self._events_table.setEditTriggers(
            QAbstractItemView.EditTrigger.DoubleClicked |
            QAbstractItemView.EditTrigger.AnyKeyPressed
        )
        self._events_table.setMinimumHeight(140)
        self._events_table.setMaximumHeight(210)
        self._refresh_events_table()
        lay.addWidget(self._events_table)

        ctrl = QHBoxLayout()
        self._rec_btn = QPushButton("● Record")
        self._rec_btn.setAutoDefault(False)
        self._rec_btn.clicked.connect(self._toggle_record)
        ctrl.addWidget(self._rec_btn)

        clear_btn = QPushButton("Clear")
        clear_btn.setAutoDefault(False)
        clear_btn.clicked.connect(self._clear_events)
        ctrl.addWidget(clear_btn)

        del_btn = QPushButton("Delete Row")
        del_btn.setAutoDefault(False)
        del_btn.clicked.connect(self._delete_selected_rows)
        ctrl.addWidget(del_btn)

        ctrl.addStretch()
        self._rec_hint = QLabel("")
        self._rec_hint.setStyleSheet("color: #E53935; font-size: 11px;")
        ctrl.addWidget(self._rec_hint)
        lay.addLayout(ctrl)

        if not HAVE_PYNPUT:
            w = QLabel("⚠  pynput not available — recording disabled")
            w.setStyleSheet("color: #FF9800; font-size: 11px;")
            lay.addWidget(w)
        elif not check_input_monitoring():
            w = QLabel(
                "⚠  Input Monitoring permission required.\n"
                "System Settings → Privacy & Security → Input Monitoring → enable this app."
            )
            w.setWordWrap(True)
            w.setStyleSheet("color: #FF9800; font-size: 11px;")
            lay.addWidget(w)

        return p

    def _build_text_panel(self):
        p = QWidget()
        lay = QVBoxLayout(p)
        lay.setContentsMargins(0, 0, 0, 0)
        lay.addWidget(QLabel("Text to type:"))
        self._text_edit = QTextEdit()
        self._text_edit.setPlainText(self.macro.text)
        self._text_edit.setMinimumHeight(110)
        lay.addWidget(self._text_edit)
        note = QLabel("Typed into the focused window after a 0.1 s delay.")
        note.setStyleSheet("color: #666; font-size: 10px;")
        lay.addWidget(note)
        return p

    def _build_cmd_panel(self):
        p = QWidget()
        lay = QVBoxLayout(p)
        lay.setContentsMargins(0, 0, 0, 0)
        lay.addWidget(QLabel("Shell command:"))
        self._cmd_edit = QLineEdit(self.macro.cmd)
        self._cmd_edit.setPlaceholderText("e.g.  open -a Safari   or   say 'hello'")
        lay.addWidget(self._cmd_edit)
        return p

    _MEDIA_ACTIONS = [
        ("Volume up",       "vol_up"),
        ("Volume down",     "vol_down"),
        ("Mute toggle",     "mute"),
        ("Play / Pause",    "play_pause"),
        ("Next track",      "next"),
        ("Previous track",  "prev"),
        ("Brightness up",   "brightness_up"),
        ("Brightness down", "brightness_down"),
    ]

    def _build_media_panel(self):
        p = QWidget()
        lay = QVBoxLayout(p)
        lay.setContentsMargins(0, 0, 0, 0)
        lay.addWidget(QLabel("Action:"))
        self._media_combo = QComboBox()
        for label, val in self._MEDIA_ACTIONS:
            self._media_combo.addItem(label, val)
        # restore selection
        for i in range(self._media_combo.count()):
            if self._media_combo.itemData(i) == self.macro.media:
                self._media_combo.setCurrentIndex(i)
                break
        lay.addWidget(self._media_combo)
        note = QLabel("Posts the same HID event as the keyboard's media keys, "
                      "so the on-screen HUD and feedback sound both fire.")
        note.setStyleSheet("color: #666; font-size: 10px;")
        note.setWordWrap(True)
        lay.addWidget(note)
        return p

    def _btn_row(self):
        row = QHBoxLayout()
        row.addStretch()
        cancel = QPushButton("Cancel")
        cancel.setAutoDefault(False)
        cancel.clicked.connect(self.reject)
        row.addWidget(cancel)
        save = QPushButton("Save")
        save.setObjectName("save")
        save.setAutoDefault(False)
        save.setDefault(False)
        save.clicked.connect(self._save)
        row.addWidget(save)
        return row

    # ── Logic ────────────────────────────────────────────────────────────────

    def _current_kind(self) -> str:
        for b in self._type_grp.buttons():
            if b.isChecked():
                return b.property("kind")
        return "keys"

    def _refresh_panels(self):
        kind = self._current_kind()
        self._keys_panel.setVisible(kind == "keys")
        self._text_panel.setVisible(kind == "text")
        self._cmd_panel.setVisible(kind == "cmd")
        self._media_panel.setVisible(kind == "media")
        self.adjustSize()

    # ── Events table ──────────────────────────────────────────────────────────

    def _refresh_events_table(self):
        self._events_table.setRowCount(0)
        for e in self._events:
            self._append_table_row(e)

    def _append_table_row(self, e: KeyEvent):
        row = self._events_table.rowCount()
        self._events_table.insertRow(row)

        arrow = "↓" if e.t == "p" else "↑"
        a_item = QTableWidgetItem(arrow)
        a_item.setFlags(Qt.ItemFlag.ItemIsEnabled | Qt.ItemFlag.ItemIsSelectable)
        a_item.setForeground(QColor("#4CAF50" if e.t == "p" else "#EF5350"))
        a_item.setTextAlignment(Qt.AlignmentFlag.AlignCenter)

        k_item = QTableWidgetItem(e.k)
        k_item.setFlags(Qt.ItemFlag.ItemIsEnabled | Qt.ItemFlag.ItemIsSelectable)

        d_item = QTableWidgetItem(str(int(e.d * 1000)))

        self._events_table.setItem(row, 0, a_item)
        self._events_table.setItem(row, 1, k_item)
        self._events_table.setItem(row, 2, d_item)
        self._events_table.scrollToBottom()

    def _delete_selected_rows(self):
        rows = sorted({i.row() for i in self._events_table.selectedItems()}, reverse=True)
        for r in rows:
            self._events_table.removeRow(r)
            if r < len(self._events):
                del self._events[r]

    # ── Recording ─────────────────────────────────────────────────────────────

    def _toggle_record(self):
        if self._recording:
            self._stop_record()
        else:
            self._start_record()

    def _start_record(self):
        cb = lambda e: self._sig.event_captured.emit(e)
        if self._record_start_cb:
            self._record_start_cb(cb)
        elif HAVE_PYNPUT:
            self._recorder = Recorder(cb)
            err = self._recorder.start()
            if err:
                self._recorder = None
                self._rec_hint.setText(f"⚠ {err}")
                return
        else:
            return
        self._recording = True
        self._rec_btn.setText("■ Stop")
        self._rec_btn.setObjectName("rec")
        self._rec_btn.setStyleSheet(
            "QPushButton{background:#E53935;color:white;border:none;border-radius:6px;padding:7px 16px;}"
            "QPushButton:hover{background:#EF5350;}"
        )
        self._rec_hint.setText("Recording… press keys to capture")

    def _stop_record(self):
        self._recording = False
        if self._record_stop_cb:
            self._record_stop_cb()
        if self._recorder:
            self._recorder.stop()
            self._recorder = None
        self._rec_btn.setText("● Record")
        self._rec_btn.setObjectName("")
        self._rec_btn.setStyleSheet("")
        self._rec_hint.setText("")

    def _on_event(self, event: KeyEvent):
        self._events.append(event)
        self._append_table_row(event)

    def _clear_events(self):
        self._stop_record()
        self._events.clear()
        self._events_table.setRowCount(0)

    def _save(self):
        self._stop_record()
        events = []
        for row in range(self._events_table.rowCount()):
            t_item = self._events_table.item(row, 0)
            k_item = self._events_table.item(row, 1)
            d_item = self._events_table.item(row, 2)
            if not (t_item and k_item):
                continue
            t = "p" if t_item.text() == "↓" else "r"
            k = k_item.text()
            try:
                d = max(0.0, float(d_item.text()) / 1000.0) if d_item else 0.0
            except ValueError:
                d = 0.0
            events.append({"t": t, "k": k, "d": d})

        kind = self._current_kind()
        macro = Macro(
            id=self.macro.id,
            name=self._name_edit.text().strip() or "Macro",
            icon=self._selected_icon,
            kind=kind,
            events=events,
            text=self._text_edit.toPlainText() if kind == "text" else "",
            cmd=self._cmd_edit.text().strip() if kind == "cmd" else "",
            media=self._media_combo.currentData() if kind == "media" else "",
            keep_open=self._keep_open_chk.isChecked(),
        )
        self.store.set(self.slot, macro)
        self.accept()

    def eventFilter(self, obj, event):
        if self._recording and event.type() == QEvent.Type.KeyPress:
            return True
        return False

    def keyPressEvent(self, event):
        if self._recording:
            event.accept()
            return
        super().keyPressEvent(event)

    def closeEvent(self, event):
        self._stop_record()
        QApplication.instance().removeEventFilter(self)
        super().closeEvent(event)
