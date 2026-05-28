#!/usr/bin/env python3
# SIGTRAP handler must be installed before any imports
import signal
try:
    signal.signal(signal.SIGTRAP, signal.SIG_IGN)
except (OSError, ValueError):
    pass

import sys, os, platform
from typing import Optional

# Fast TCC probe — spawned by the permissions dialog polling loop.
# A fresh process always reads the current TCC state; the running process has
# stale values on macOS 15 Sequoia after a permission is granted.
if '--check-tcc-ax' in sys.argv:
    from permissions import check_accessibility
    sys.exit(0 if check_accessibility() else 1)
if '--check-tcc-im' in sys.argv:
    from permissions import check_input_monitoring
    sys.exit(0 if check_input_monitoring() else 1)

from PyQt6.QtWidgets import (
    QApplication, QWidget, QGridLayout, QVBoxLayout, QHBoxLayout,
    QLabel, QPushButton, QFrame, QSizePolicy, QMenu, QDialog,
    QSystemTrayIcon, QLineEdit, QSpinBox,
)
from PyQt6.QtCore import Qt, pyqtSignal, QTimer, QObject, QEvent, QProcess
from PyQt6.QtGui import (
    QFont, QIcon, QPixmap, QPainter, QColor, QBrush, QCursor,
)

from store import MacroStore, Macro
from engine import Player, GlobalHotkeyListener
from editor import MacroEditorDialog
import permissions
import settings as _settings

MACOS = platform.system() == "Darwin"

BG    = "#1a1a2e"
EMPTY = "#1a1a3a"

MENU_STYLE = """
QMenu { background: #2a2a4a; color: #e0e0e0; border: 1px solid #444;
        border-radius: 6px; padding: 4px; }
QMenu::item { padding: 6px 20px; border-radius: 4px; }
QMenu::item:selected { background: #3a3a6a; }
QMenu::separator { height: 1px; background: #444; margin: 4px 8px; }
"""


# ── Helpers ───────────────────────────────────────────────────────────────────

def _hide_dock():
    if not MACOS:
        return
    try:
        from AppKit import NSApp, NSApplicationActivationPolicyAccessory
        NSApp.setActivationPolicy_(NSApplicationActivationPolicyAccessory)
    except Exception:
        pass


def _patch_panel(widget: QWidget):
    """Set NSWindowStyleMaskNonactivatingPanel so clicks don't steal focus."""
    if not MACOS:
        return
    try:
        import objc
        from ctypes import c_void_p
        view = objc.objc_object(c_void_p=c_void_p(int(widget.winId())))
        win = view.window()
        if win is None:
            return
        win.setHidesOnDeactivate_(False)
        mask = win.styleMask()
        if not (mask & 128):
            win.setStyleMask_(mask | 128)
    except Exception:
        pass


def _make_tray_icon() -> QIcon:
    pix = QPixmap(22, 22)
    pix.fill(Qt.GlobalColor.transparent)
    p = QPainter(pix)
    p.setRenderHint(QPainter.RenderHint.Antialiasing)
    p.setBrush(QBrush(QColor(255, 255, 255, 220)))
    p.setPen(Qt.PenStyle.NoPen)
    for row in range(2):
        for col in range(2):
            p.drawRoundedRect(2 + col * 11, 2 + row * 11, 8, 8, 2, 2)
    p.end()
    return QIcon(pix)


# ── MacroTile ─────────────────────────────────────────────────────────────────

class MacroTile(QFrame):
    clicked    = pyqtSignal(int)
    edit_req   = pyqtSignal(int)
    delete_req = pyqtSignal(int)

    def __init__(self, slot: int, macro: Optional[Macro], parent=None):
        super().__init__(parent)
        self.slot  = slot
        self.macro = macro
        self.setMinimumSize(110, 82)
        self.setSizePolicy(QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Expanding)
        self.setCursor(Qt.CursorShape.PointingHandCursor)
        self.setFocusPolicy(Qt.FocusPolicy.NoFocus)
        self.setContextMenuPolicy(Qt.ContextMenuPolicy.CustomContextMenu)
        self.customContextMenuRequested.connect(self._ctx)
        # Create layout once; _render() clears and refills it each time.
        self._lay = QVBoxLayout(self)
        self._lay.setContentsMargins(8, 6, 8, 6)
        self._lay.setSpacing(3)
        self._render()

    def update_macro(self, macro: Optional[Macro]):
        self.macro = macro
        self._render()

    def _render(self):
        # takeAt + setParent(None) removes widgets immediately.
        # deleteLater() is deferred and would race with the new widgets
        # we add below — that's why text disappeared after editing.
        while self._lay.count():
            item = self._lay.takeAt(0)
            w = item.widget()
            if w:
                w.setParent(None)

        hotkey = f"⌃{self.slot % 10}" if self.slot <= 10 else f"#{self.slot}"

        if self.macro:
            c = self.macro.color
            self.setStyleSheet(
                f"MacroTile{{background:{c}18;border:2px solid {c}55;border-radius:10px;}}"
                f"MacroTile:hover{{background:{c}38;border-color:{c}aa;}}"
            )
            self._lay.addStretch()
            if self.macro.icon:
                icon_lbl = QLabel(self.macro.icon)
                icon_lbl.setFont(QFont(".AppleSystemUIFont", 22))
                icon_lbl.setAlignment(Qt.AlignmentFlag.AlignCenter)
                icon_lbl.setStyleSheet("background:transparent;border:none;")
                icon_lbl.setFocusPolicy(Qt.FocusPolicy.NoFocus)
                self._lay.addWidget(icon_lbl)
            name = QLabel(self.macro.name)
            fs = 9 if self.macro.icon else 11
            name.setFont(QFont(".AppleSystemUIFont", fs, QFont.Weight.Medium))
            name.setStyleSheet(f"color:{c};background:transparent;border:none;")
            name.setAlignment(Qt.AlignmentFlag.AlignCenter)
            name.setWordWrap(True)
            name.setFocusPolicy(Qt.FocusPolicy.NoFocus)
            self._lay.addWidget(name)
            self._lay.addStretch()
        else:
            self.setStyleSheet(
                f"MacroTile{{background:{EMPTY};border:2px dashed #2e2e5a;border-radius:10px;}}"
                f"MacroTile:hover{{background:#22224a;border-color:#444;}}"
            )
            plus = QLabel("+")
            plus.setFont(QFont(".AppleSystemUIFont", 20, QFont.Weight.Light))
            plus.setStyleSheet("color:#3a3a6a;background:transparent;border:none;")
            plus.setAlignment(Qt.AlignmentFlag.AlignCenter)
            plus.setFocusPolicy(Qt.FocusPolicy.NoFocus)
            self._lay.addWidget(plus, alignment=Qt.AlignmentFlag.AlignCenter)

        hk = QLabel(hotkey)
        hk.setStyleSheet(
            f"color:{'#666' if self.macro else '#2e2e5a'};font-size:9px;"
            "background:transparent;border:none;"
        )
        hk.setAlignment(Qt.AlignmentFlag.AlignCenter)
        hk.setFocusPolicy(Qt.FocusPolicy.NoFocus)
        self._lay.addWidget(hk)

    def mousePressEvent(self, ev):
        if ev.button() == Qt.MouseButton.LeftButton:
            self.clicked.emit(self.slot)

    def _ctx(self, pos):
        menu = QMenu(self)
        menu.setStyleSheet(MENU_STYLE)
        if self.macro:
            menu.addAction("▶  Run",    lambda: self.clicked.emit(self.slot))
            menu.addSeparator()
            menu.addAction("✎  Edit",   lambda: self.edit_req.emit(self.slot))
            menu.addAction("✕  Delete", lambda: self.delete_req.emit(self.slot))
        else:
            menu.addAction("+ Add Macro", lambda: self.edit_req.emit(self.slot))
        menu.exec(self.mapToGlobal(pos))


# ── MacroPopup ────────────────────────────────────────────────────────────────

class MacroPopup(QWidget):
    run_req    = pyqtSignal(int)
    edit_req   = pyqtSignal(int)
    delete_req = pyqtSignal(int)
    close_req  = pyqtSignal()

    def __init__(self, store: MacroStore, cols: int = 4, rows: int = 3, parent=None):
        super().__init__(parent)
        self.store = store
        self._cols = cols
        self._rows = rows

        self.setWindowFlags(
            Qt.WindowType.FramelessWindowHint      |
            Qt.WindowType.Tool                     |
            Qt.WindowType.WindowStaysOnTopHint     |
            Qt.WindowType.WindowDoesNotAcceptFocus
        )
        self.setAttribute(Qt.WidgetAttribute.WA_ShowWithoutActivating)
        self.setAttribute(Qt.WidgetAttribute.WA_TranslucentBackground)
        self.setFocusPolicy(Qt.FocusPolicy.NoFocus)

        self._tiles: list = []
        self._grid_widget: Optional[QWidget] = None
        self._card_lay: Optional[QVBoxLayout] = None
        self._build()

    def _build(self):
        outer = QVBoxLayout(self)
        outer.setContentsMargins(6, 6, 6, 6)

        self._card = QFrame()
        self._card.setObjectName("card")
        self._card.setStyleSheet("""
            QFrame#card {
                background: #1a1a2e;
                border: 1px solid #2e2e5a;
                border-radius: 13px;
            }
        """)
        self._card_lay = QVBoxLayout(self._card)
        self._card_lay.setContentsMargins(10, 8, 10, 10)
        self._card_lay.setSpacing(7)

        hdr = QHBoxLayout()
        title = QLabel("MacroDeck")
        title.setFont(QFont(".AppleSystemUIFont", 12, QFont.Weight.Bold))
        title.setStyleSheet("color:#c0c0c0; background:transparent;")
        title.setFocusPolicy(Qt.FocusPolicy.NoFocus)
        hdr.addWidget(title)
        hdr.addStretch()

        close_btn = QPushButton("✕")
        close_btn.setFixedSize(18, 18)
        close_btn.setFocusPolicy(Qt.FocusPolicy.NoFocus)
        close_btn.setStyleSheet("""
            QPushButton{background:transparent;color:#555;border:none;font-size:11px;}
            QPushButton:hover{color:#e0e0e0;}
        """)
        close_btn.clicked.connect(self.close_req)
        hdr.addWidget(close_btn)
        self._card_lay.addLayout(hdr)

        outer.addWidget(self._card)
        self.rebuild_grid(self._cols, self._rows)

    def rebuild_grid(self, cols: int, rows: int):
        self._cols = cols
        self._rows = rows

        if self._grid_widget is not None:
            self._card_lay.removeWidget(self._grid_widget)
            self._grid_widget.setParent(None)

        self._grid_widget = QWidget()
        self._grid_widget.setFocusPolicy(Qt.FocusPolicy.NoFocus)
        self._grid_widget.setStyleSheet("background: transparent;")
        grid = QGridLayout(self._grid_widget)
        grid.setSpacing(7)
        grid.setContentsMargins(0, 0, 0, 0)

        self._tiles = []
        for i in range(cols * rows):
            r, c = divmod(i, cols)
            slot = i + 1
            tile = MacroTile(slot, self.store.get(slot))
            tile.clicked.connect(self.run_req)
            tile.edit_req.connect(self.edit_req)
            tile.delete_req.connect(self.delete_req)
            grid.addWidget(tile, r, c)
            self._tiles.append(tile)

        self._card_lay.addWidget(self._grid_widget)
        self.adjustSize()

    def update_slot(self, slot: int, macro: Optional[Macro]):
        if 1 <= slot <= len(self._tiles):
            self._tiles[slot - 1].update_macro(macro)


# ── Permissions dialog ────────────────────────────────────────────────────────

PERM_STYLE = f"""
QDialog  {{ background: {BG}; }}
QWidget  {{ background: {BG}; color: #e0e0e0; }}
QLabel   {{ background: transparent; }}
QPushButton {{
    background: #2a2a4a; color: #e0e0e0;
    border: none; border-radius: 6px;
    padding: 7px 16px; font-size: 12px;
}}
QPushButton:hover {{ background: #3a3a6a; }}
QPushButton#grant {{ background: #1E88E5; color: white; }}
QPushButton#grant:hover {{ background: #2196F3; }}
QPushButton#done  {{ background: #43A047; color: white; }}
QPushButton#done:hover  {{ background: #4CAF50; }}
QFrame#pcard {{
    background: #0d1117;
    border: 1px solid #2a2a4a;
    border-radius: 10px;
}}
"""


class _PermRow(QFrame):
    """One permission row. Makes the dialog invisible when Grant is clicked, opens
    System Settings, then polls with a subprocess TCC check every 300 ms. A fresh
    subprocess always reads the current TCC state — the running process has stale
    values on macOS 15 Sequoia after a permission is granted."""

    status_changed = pyqtSignal()

    def __init__(self, title, detail, granted, on_open, check_flag, parent=None):
        super().__init__(parent)
        self.setObjectName("pcard")
        self._granted    = granted
        self._on_open    = on_open
        self._check_flag = check_flag
        self._poll_timer: Optional[QTimer] = None
        self._checking   = False

        lay = QHBoxLayout(self)
        lay.setContentsMargins(14, 12, 14, 12)
        lay.setSpacing(12)

        self._icon = QLabel()
        self._icon.setFixedWidth(20)
        self._icon.setFont(QFont(".AppleSystemUIFont", 15))
        lay.addWidget(self._icon)

        col = QVBoxLayout()
        col.setSpacing(2)
        t = QLabel(title)
        t.setFont(QFont(".AppleSystemUIFont", 12, QFont.Weight.Medium))
        t.setStyleSheet("color:#e0e0e0;")
        self._detail = QLabel(detail)
        self._detail.setStyleSheet("color:#888; font-size: 11px;")
        self._detail.setWordWrap(True)
        col.addWidget(t)
        col.addWidget(self._detail)
        lay.addLayout(col, stretch=1)

        self._btn = QPushButton()
        self._btn.setFixedWidth(120)
        self._btn.clicked.connect(self._open)
        lay.addWidget(self._btn)

        self._refresh()

    def _refresh(self):
        if self._granted:
            self._icon.setText("✓")
            self._icon.setStyleSheet("color:#43A047;")
            self._btn.setText("Granted")
            self._btn.setEnabled(False)
            self._btn.setStyleSheet(
                "background:#1a2a1a;color:#43A047;border:none;border-radius:6px;"
                "padding:7px 16px;font-size:12px;"
            )
        else:
            self._icon.setText("⚠")
            self._icon.setStyleSheet("color:#FF9800;")
            self._btn.setText("Grant Access")
            self._btn.setObjectName("grant")
            self._btn.setEnabled(True)
            self._btn.setStyleSheet("")

    def _open(self):
        # Call on_open FIRST — for Accessibility this shows a native macOS alert
        # that blocks until the user clicks "Open System Settings" or "Deny".
        # The alert appears on top of our dialog, which is fine.
        self._on_open()
        win = self.window()
        self._saved_pos = win.pos()
        win.setWindowModality(Qt.WindowModality.NonModal)
        win.setWindowOpacity(0.0)
        screen = QApplication.primaryScreen().geometry()
        win.move(screen.right() + 200, screen.top())
        self._start_poll()
        QTimer.singleShot(90_000, self._poll_timeout)

    def _start_poll(self):
        self._poll_timer = QTimer(self)
        self._poll_timer.timeout.connect(self._poll_tcc)
        self._poll_timer.start(300)

    def _poll_tcc(self):
        """Spawn a subprocess to check TCC. Skip if a prior check is still running."""
        if self._checking:
            return
        resource_path = os.environ.get('RESOURCEPATH', '')
        if resource_path:
            exe  = os.path.join(os.path.dirname(resource_path), 'MacOS', 'MacroDeck')
            args = [self._check_flag]
        else:
            exe  = sys.executable
            args = [os.path.abspath(sys.argv[0]), self._check_flag]
        if not os.path.isfile(exe):
            return
        self._checking = True
        proc = QProcess(self)
        proc.finished.connect(self._on_proc_done)
        proc.start(exe, args)

    def _on_proc_done(self, exit_code, _exit_status):
        self._checking = False
        if exit_code == 0:
            if self._poll_timer:
                self._poll_timer.stop()
            self._granted = True
            self._refresh()
            self._return_to_dialog()

    def _poll_timeout(self):
        if self._poll_timer and self._poll_timer.isActive():
            self._poll_timer.stop()
        self._return_to_dialog()

    def _return_to_dialog(self):
        win = self.window()
        win.move(self._saved_pos if hasattr(self, '_saved_pos') else win.pos())
        win.setWindowModality(Qt.WindowModality.ApplicationModal)
        win.setWindowOpacity(1.0)
        win.raise_()
        win.activateWindow()
        self.status_changed.emit()


class PermissionsDialog(QDialog):
    def __init__(self, parent=None):
        super().__init__(parent)
        self.setWindowTitle("MacroDeck — Permissions needed")
        self.setFixedWidth(500)
        self.setModal(True)
        self.setStyleSheet(PERM_STYLE)
        self._build()

    def _build(self):
        import subprocess as _sp
        lay = QVBoxLayout(self)
        lay.setContentsMargins(24, 22, 24, 20)
        lay.setSpacing(12)

        hdr = QLabel("MacroDeck needs two permissions")
        hdr.setFont(QFont(".AppleSystemUIFont", 15, QFont.Weight.Bold))
        hdr.setStyleSheet("color:#e0e0e0;")
        lay.addWidget(hdr)

        sub = QLabel(
            "Click Grant Access for each permission below, then follow the prompts "
            "to enable MacroDeck in System Settings."
        )
        sub.setStyleSheet("color:#888; font-size:12px;")
        sub.setWordWrap(True)
        lay.addWidget(sub)

        def _open_ax():
            permissions.request_accessibility()

        def _open_im():
            permissions.request_input_monitoring()
            _sp.run(["open",
                     "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"],
                    check=False)

        self._ax = _PermRow(
            "Accessibility",
            "Required for key/text playback into other apps (System Events).",
            permissions.check_accessibility(),
            _open_ax,
            '--check-tcc-ax',
            parent=self,
        )
        self._ax.status_changed.connect(self._update_continue_btn)
        lay.addWidget(self._ax)

        self._im = _PermRow(
            "Input Monitoring",
            "Required for recording keystrokes and for global hotkeys.",
            permissions.check_input_monitoring(),
            _open_im,
            '--check-tcc-im',
            parent=self,
        )
        self._im.status_changed.connect(self._update_continue_btn)
        lay.addWidget(self._im)

        btns = QHBoxLayout()
        btns.addStretch()
        self._continue_btn = QPushButton()
        self._continue_btn.clicked.connect(self.accept)
        btns.addWidget(self._continue_btn)
        lay.addLayout(btns)
        self._update_continue_btn()

    def _update_continue_btn(self):
        if self._ax._granted and self._im._granted:
            self._continue_btn.setText("Continue")
            self._continue_btn.setObjectName("done")
        else:
            self._continue_btn.setText("Continue Anyway")
            self._continue_btn.setObjectName("")
        self._continue_btn.setStyleSheet(self.styleSheet())


class _RestartDialog(QDialog):
    """Shown after the permissions flow. macOS only sees the new TCC grants in a
    fresh process, so the app has to restart — this just makes that explicit."""

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setWindowTitle("MacroDeck — Restart needed")
        self.setFixedWidth(400)
        self.setModal(True)
        self.setStyleSheet(PERM_STYLE)

        lay = QVBoxLayout(self)
        lay.setContentsMargins(24, 22, 24, 20)
        lay.setSpacing(14)

        hdr = QLabel("Almost done")
        hdr.setFont(QFont(".AppleSystemUIFont", 15, QFont.Weight.Bold))
        hdr.setStyleSheet("color:#e0e0e0;")
        lay.addWidget(hdr)

        sub = QLabel("MacroDeck needs to restart so macOS picks up the new permissions.")
        sub.setStyleSheet("color:#aaa; font-size:12px;")
        sub.setWordWrap(True)
        lay.addWidget(sub)

        btns = QHBoxLayout()
        btns.addStretch()
        btn = QPushButton("Restart Now")
        btn.setObjectName("done")
        btn.clicked.connect(self.accept)
        btns.addWidget(btn)
        lay.addLayout(btns)


# ── Settings dialog ───────────────────────────────────────────────────────────

SETTINGS_STYLE = """
QDialog  { background: #1a1a2e; }
QWidget  { background: #1a1a2e; color: #e0e0e0; }
QLabel   { background: transparent; }
QLineEdit {
    background: #0d1117; color: #e0e0e0;
    border: 1px solid #2e2e5a; border-radius: 6px;
    padding: 6px 10px; font-size: 12px;
}
QLineEdit:focus { border-color: #5a5a9a; }
QSpinBox {
    background: #0d1117; color: #e0e0e0;
    border: 1px solid #2e2e5a; border-radius: 6px;
    padding: 5px 8px; font-size: 12px;
    min-width: 52px;
}
QPushButton {
    background: #2a2a4a; color: #e0e0e0;
    border: none; border-radius: 6px;
    padding: 7px 20px; font-size: 12px;
}
QPushButton:hover { background: #3a3a6a; }
QPushButton#save { background: #1E88E5; color: white; }
QPushButton#save:hover { background: #2196F3; }
"""


class SettingsDialog(QDialog):
    def __init__(self, s: _settings.Settings, parent=None):
        super().__init__(parent)
        self.setWindowTitle("MacroDeck — Settings")
        self.setFixedWidth(380)
        self.setModal(True)
        self.setStyleSheet(SETTINGS_STYLE)
        self._s = s
        self._build()

    def _build(self):
        lay = QVBoxLayout(self)
        lay.setContentsMargins(24, 22, 24, 20)
        lay.setSpacing(10)

        hdr = QLabel("Settings")
        hdr.setFont(QFont(".AppleSystemUIFont", 15, QFont.Weight.Bold))
        hdr.setStyleSheet("color:#e0e0e0;")
        lay.addWidget(hdr)

        hk_row = QHBoxLayout()
        hk_lbl = QLabel("Toggle hotkey")
        hk_lbl.setStyleSheet("color:#aaa; font-size:12px;")
        hk_lbl.setFixedWidth(130)
        self._hk_edit = QLineEdit(self._s.toggle_hotkey)
        hk_row.addWidget(hk_lbl)
        hk_row.addWidget(self._hk_edit)
        lay.addLayout(hk_row)

        hint = QLabel('Keys joined with "+",  e.g. ctrl+shift+m')
        hint.setStyleSheet("color:#555; font-size:10px;")
        lay.addWidget(hint)

        lay.addSpacing(8)

        grid_row = QHBoxLayout()
        grid_lbl = QLabel("Grid size")
        grid_lbl.setStyleSheet("color:#aaa; font-size:12px;")
        grid_lbl.setFixedWidth(130)
        self._cols_spin = QSpinBox()
        self._cols_spin.setRange(1, 10)
        self._cols_spin.setValue(self._s.grid_cols)
        x_lbl = QLabel("×")
        x_lbl.setStyleSheet("color:#aaa; font-size:13px;")
        x_lbl.setAlignment(Qt.AlignmentFlag.AlignCenter)
        x_lbl.setFixedWidth(20)
        self._rows_spin = QSpinBox()
        self._rows_spin.setRange(1, 10)
        self._rows_spin.setValue(self._s.grid_rows)
        grid_row.addWidget(grid_lbl)
        grid_row.addWidget(self._cols_spin)
        grid_row.addWidget(x_lbl)
        grid_row.addWidget(self._rows_spin)
        grid_row.addStretch()
        lay.addLayout(grid_row)

        lay.addStretch()

        btns = QHBoxLayout()
        btns.addStretch()
        cancel_btn = QPushButton("Cancel")
        cancel_btn.clicked.connect(self.reject)
        save_btn = QPushButton("Save")
        save_btn.setObjectName("save")
        save_btn.clicked.connect(self._save)
        btns.addWidget(cancel_btn)
        btns.addWidget(save_btn)
        lay.addLayout(btns)

    def _save(self):
        hk = self._hk_edit.text().strip()
        self._s.toggle_hotkey = hk if hk else self._s.toggle_hotkey
        self._s.grid_cols = self._cols_spin.value()
        self._s.grid_rows = self._rows_spin.value()
        self.accept()

    @property
    def value(self) -> _settings.Settings:
        return self._s


# ── Thread bridge ────────────────────────────────────────────────────────────

class _HotkeyBridge(QObject):
    """Signals emitted from pynput's thread; Qt queues them to the main thread."""
    slot_triggered   = pyqtSignal(int)
    toggle_triggered = pyqtSignal()


# ── App controller ────────────────────────────────────────────────────────────

class MacroDeckApp(QObject):
    def __init__(self, tray: QSystemTrayIcon):
        super().__init__()
        self._cfg = _settings.load()

        store_path = os.path.expanduser("~/.mac-macro/macros.json")
        self.store  = MacroStore(store_path)
        self.player = Player()

        self._toggle_hotkey = self._cfg.toggle_hotkey

        self._tray = tray
        self._tray.setToolTip(f"MacroDeck — {self._toggle_hotkey} to open")
        self._ctx_menu = QMenu()
        self._ctx_menu.setStyleSheet(MENU_STYLE)
        self._build_ctx_menu()
        self._tray.activated.connect(self._on_tray)

        self._popup = MacroPopup(self.store, self._cfg.grid_cols, self._cfg.grid_rows)
        self._popup.run_req.connect(self._run_slot)
        self._popup.edit_req.connect(self._edit_slot)
        self._popup.delete_req.connect(self._delete_slot)
        self._popup.close_req.connect(self._close_popup)
        self._popup_open = False

        QApplication.instance().installEventFilter(self)

        self._hotkeys: Optional[GlobalHotkeyListener] = None
        self._start_hotkeys()

    def _build_ctx_menu(self):
        self._ctx_menu.clear()
        self._ctx_menu.addAction(f"Show / Hide  ({self._toggle_hotkey})", self._toggle)
        self._ctx_menu.addSeparator()
        self._ctx_menu.addAction("Configure…", self._open_settings)
        self._ctx_menu.addAction("Permissions…", self._check_permissions)
        self._ctx_menu.addSeparator()
        self._ctx_menu.addAction("Quit MacroDeck", self._quit)

    def _quit(self):
        self._tray.hide()
        QApplication.instance().quit()

    # ── Hotkeys ───────────────────────────────────────────────────────────────

    def _start_hotkeys(self):
        # Signals are thread-safe; emitting from pynput's background thread
        # automatically queues delivery to the main Qt thread.
        self._hotkeys_bridge = _HotkeyBridge()
        self._hotkeys_bridge.slot_triggered.connect(self._run_slot)
        self._hotkeys_bridge.toggle_triggered.connect(self._toggle)
        bridge = self._hotkeys_bridge

        self._hotkeys = GlobalHotkeyListener(
            on_slot=bridge.slot_triggered.emit,
            on_toggle=bridge.toggle_triggered.emit,
            toggle_combo=self._toggle_hotkey,
        )
        err = self._hotkeys.start()
        if err:
            print(f"[MacroDeck] global hotkeys unavailable: {err}")

    def _pause_hotkeys(self):
        if self._hotkeys:
            self._hotkeys.pause()

    def _resume_hotkeys(self):
        if self._hotkeys:
            self._hotkeys.resume()

    # ── Settings ──────────────────────────────────────────────────────────────

    def _open_settings(self):
        dlg = SettingsDialog(self._cfg)
        if dlg.exec():
            new_cfg = dlg.value
            hotkey_changed = new_cfg.toggle_hotkey != self._toggle_hotkey
            grid_changed = (new_cfg.grid_cols != self._cfg.grid_cols or
                            new_cfg.grid_rows != self._cfg.grid_rows)
            self._cfg = new_cfg
            _settings.save(new_cfg)

            if hotkey_changed:
                self._toggle_hotkey = new_cfg.toggle_hotkey
                self._tray.setToolTip(f"MacroDeck — {self._toggle_hotkey} to open")
                self._build_ctx_menu()
                if self._hotkeys:
                    self._hotkeys.stop()
                    self._hotkeys = None
                self._start_hotkeys()

            if grid_changed:
                self._popup.rebuild_grid(new_cfg.grid_cols, new_cfg.grid_rows)

    def _check_permissions(self):
        dlg = PermissionsDialog()
        dlg.exec()
        self._start_hotkeys()

    # ── Tray ──────────────────────────────────────────────────────────────────

    def _on_tray(self, reason):
        if reason in (
            QSystemTrayIcon.ActivationReason.Trigger,
            QSystemTrayIcon.ActivationReason.MiddleClick,
        ):
            self._toggle()
        elif reason == QSystemTrayIcon.ActivationReason.Context:
            self._ctx_menu.exec(QCursor.pos())

    def eventFilter(self, obj, event):
        if self._popup_open and event.type() == QEvent.Type.MouseButtonPress:
            if hasattr(event, 'globalPosition'):
                gpos = event.globalPosition().toPoint()
            else:
                gpos = event.globalPos()
            if not self._popup.geometry().contains(gpos):
                self._close_popup()
        return False

    def _toggle(self):
        if self._popup_open:
            self._close_popup()
        else:
            self._open_popup()

    def _open_popup(self):
        self._place_popup()
        _patch_panel(self._popup)  # must be before show() so NSWindow is non-activating on first paint
        self._popup.show()
        self._popup_open = True

    def _close_popup(self):
        self._popup.hide()
        self._popup_open = False

    def _place_popup(self):
        geo = self._tray.geometry()
        screen = QApplication.primaryScreen().availableGeometry()
        self._popup.adjustSize()
        pw, ph = self._popup.width(), self._popup.height()

        if geo.isValid():
            x = geo.center().x() - pw // 2
            y = geo.bottom() + 4
        else:
            x = screen.right() - pw - 12
            y = screen.top() + 28

        x = max(screen.left(), min(x, screen.right() - pw))
        y = max(screen.top(), min(y, screen.bottom() - ph))
        self._popup.move(x, y)

    # ── Macro actions ─────────────────────────────────────────────────────────

    def _run_slot(self, slot: int):
        macro = self.store.get(slot)
        if macro:
            if not macro.keep_open:
                self._close_popup()
            self._run(macro)

    def _run(self, macro: Macro):
        DELAY = 0.1
        if macro.kind == "text":
            self.player.type_text(macro.text, delay=DELAY)
        elif macro.kind == "cmd":
            self.player.run_cmd(macro.cmd)
        else:
            self.player.play(macro.events, delay=DELAY)

    def _edit_slot(self, slot: int):
        self._pause_hotkeys()
        dlg = MacroEditorDialog(
            slot, self.store,
            record_start=self._hotkeys.start_recording if self._hotkeys else None,
            record_stop=self._hotkeys.stop_recording if self._hotkeys else None,
        )
        if dlg.exec():
            self._popup.update_slot(slot, self.store.get(slot))
        self._resume_hotkeys()

    def _delete_slot(self, slot: int):
        self.store.delete(slot)
        self._popup.update_slot(slot, None)


# ── Entry point ───────────────────────────────────────────────────────────────

def main():
    app = QApplication(sys.argv)
    app.setApplicationName("MacroDeck")
    app.setStyle("Fusion")
    app.setQuitOnLastWindowClosed(False)

    # Show tray icon before _hide_dock() so it appears as fast as possible.
    _setup_tray = QSystemTrayIcon()
    _setup_tray.setIcon(_make_tray_icon())
    _setup_tray.show()

    _hide_dock()

    if not QSystemTrayIcon.isSystemTrayAvailable():
        sys.exit(1)

    # After granting permissions, CGPreflightListenEventAccess() stays False in the running
    # process — only a fresh process sees the grant. So: show dialog once, write a flag,
    # restart. On the second launch the flag is present, we skip the dialog and proceed.
    _PERMS_FLAG = '/tmp/macrodeck_perms_restart'
    if os.path.exists(_PERMS_FLAG):
        os.unlink(_PERMS_FLAG)
    elif permissions.needs_any():
        dlg = PermissionsDialog()
        dlg.exec()
        open(_PERMS_FLAG, 'w').close()
        # Show a restart prompt instead of auto-restarting — clearer UX, and
        # avoids the tray-icon-disappears-during-execv problem.
        restart_dlg = _RestartDialog()
        restart_dlg.exec()
        sys.exit(1)   # LaunchAgent's KeepAlive restarts on non-zero exit

    deck = MacroDeckApp(_setup_tray)    # noqa: F841
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
