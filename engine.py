import platform, subprocess, time, threading, signal
from typing import Callable, List, Optional

# Suppress any SIGTRAP from pyobjc/pynput before the main.py handler runs
try:
    signal.signal(signal.SIGTRAP, signal.SIG_IGN)
except (OSError, ValueError):
    pass

MACOS = platform.system() == "Darwin"

try:
    from pynput import keyboard as _kb
    from pynput.keyboard import Key, KeyCode
    if not MACOS:
        from pynput.keyboard import Controller as _Ctrl
    HAVE_PYNPUT = True
except Exception:
    HAVE_PYNPUT = False

try:
    from store import KeyEvent
except ImportError:
    pass

# ── macOS key codes for osascript ─────────────────────────────────────────────
_KEYCODE: dict = {
    "Key.return_": 36, "Key.enter": 36, "Key.tab": 48, "Key.space": 49,
    "Key.backspace": 51, "Key.delete": 117, "Key.escape": 53,
    "Key.left": 123, "Key.right": 124, "Key.down": 125, "Key.up": 126,
    "Key.home": 115, "Key.end": 119, "Key.page_up": 116, "Key.page_down": 121,
    "Key.f1": 122, "Key.f2": 120, "Key.f3": 99,  "Key.f4": 118,
    "Key.f5": 96,  "Key.f6": 97,  "Key.f7": 98,  "Key.f8": 100,
    "Key.f9": 101, "Key.f10": 109, "Key.f11": 103, "Key.f12": 111,
}

_MOD: dict = {
    "Key.cmd": "command down",   "Key.cmd_l": "command down",   "Key.cmd_r": "command down",
    "Key.shift": "shift down",   "Key.shift_l": "shift down",   "Key.shift_r": "shift down",
    "Key.ctrl": "control down",  "Key.ctrl_l": "control down",  "Key.ctrl_r": "control down",
    "Key.alt": "option down",    "Key.alt_l": "option down",    "Key.alt_r": "option down",
}

_MOD_KEYS = set(_MOD)

# macOS virtual key codes for digit keys — pynput may return vk instead of char
# when modifier keys are held down.
_VK_DIGIT: dict = {
    18: '1', 19: '2', 20: '3', 21: '4', 23: '5',
    22: '6', 26: '7', 28: '8', 25: '9', 29: '0',
}


def check_input_monitoring() -> bool:
    if not MACOS or not HAVE_PYNPUT:
        return True
    try:
        from ApplicationServices import CGPreflightListenEventAccess
        return bool(CGPreflightListenEventAccess())
    except Exception:
        return True


def _run_osascript(script: str):
    try:
        subprocess.run(["osascript", "-e", script], check=False, timeout=10)
    except Exception:
        pass


def _events_to_osascript(events: list) -> Optional[str]:
    """Convert a list of recorded KeyEvents to an AppleScript block."""
    from store import KeyEvent as KE
    parsed = [KE(**e) if isinstance(e, dict) else e for e in events]

    lines: list[str] = []
    active_mods: set = set()

    for e in parsed:
        k = e.k
        if k in _MOD_KEYS:
            if e.t == "p":
                active_mods.add(k)
            else:
                active_mods.discard(k)
            continue
        if e.t != "p":
            continue

        if e.d > 0.02:
            lines.append(f"delay {round(e.d, 4)}")

        mods = [_MOD[m] for m in active_mods if m in _MOD]
        mod_str = f" using {{{', '.join(mods)}}}" if mods else ""

        if len(k) == 1:
            safe = k.replace("\\", "\\\\").replace('"', '\\"')
            lines.append(f'keystroke "{safe}"{mod_str}')
        elif k in _KEYCODE:
            lines.append(f'key code {_KEYCODE[k]}{mod_str}')

    if not lines:
        return None
    body = "\n    ".join(lines)
    return f'tell application "System Events"\n    {body}\nend tell'


def _key_str(key) -> str:
    char = getattr(key, "char", None)
    if char and char.isprintable():
        return char
    # On macOS, holding ctrl can suppress key.char; fall back to vk for digits.
    if MACOS:
        vk = getattr(key, "vk", None)
        if vk in _VK_DIGIT:
            return _VK_DIGIT[vk]
    return str(key)


def _parse_key(s: str):
    """Convert a stored key string back to a pynput key (non-macOS only)."""
    if not HAVE_PYNPUT:
        return None
    if s.startswith("Key."):
        try:
            return getattr(Key, s[4:])
        except AttributeError:
            pass
    if len(s) == 1:
        return KeyCode.from_char(s)
    if s.startswith("<") and s.endswith(">"):
        try:
            return KeyCode.from_vk(int(s[1:-1]))
        except ValueError:
            pass
    return None


# ── Recorder ──────────────────────────────────────────────────────────────────

class Recorder:
    def __init__(self, on_event: Callable):
        self._cb = on_event
        self._listener = None
        self._last = 0.0

    def start(self) -> str:
        """Start recording. Returns '' on success, error message on failure."""
        if not HAVE_PYNPUT:
            return "pynput is not installed"
        try:
            self._last = time.time()
            self._listener = _kb.Listener(
                on_press=lambda k: self._emit("p", k),
                on_release=lambda k: self._emit("r", k),
            )
            self._listener.start()
            return ""
        except Exception as e:
            self._listener = None
            return str(e)

    def stop(self):
        if self._listener:
            self._listener.stop()
            self._listener = None

    def _emit(self, t: str, key):
        now = time.time()
        d = round(now - self._last, 4)
        self._last = now
        self._cb(KeyEvent(t=t, k=_key_str(key), d=d))


# ── Player ────────────────────────────────────────────────────────────────────

class Player:
    """Plays back macros. Uses osascript on macOS to avoid permission traps."""

    def __init__(self):
        self._ctrl = None  # lazy — never instantiated on macOS

    def _get_ctrl(self):
        if self._ctrl is None and HAVE_PYNPUT and not MACOS:
            try:
                self._ctrl = _Ctrl()
            except Exception:
                pass
        return self._ctrl

    def play(self, events: list, speed: float = 1.0, delay: float = 0.5, done: Callable = None):
        def _run():
            if delay > 0:
                time.sleep(delay)
            if MACOS:
                script = _events_to_osascript(events)
                if script:
                    _run_osascript(script)
            else:
                from store import KeyEvent as KE
                ctrl = self._get_ctrl()
                if ctrl:
                    for e in [KE(**e) if isinstance(e, dict) else e for e in events]:
                        if e.d > 0.005:
                            time.sleep(e.d / speed)
                        key = _parse_key(e.k)
                        if key:
                            try:
                                (ctrl.press if e.t == "p" else ctrl.release)(key)
                            except Exception:
                                pass
            if done:
                done()
        threading.Thread(target=_run, daemon=True).start()

    def type_text(self, text: str, delay: float = 0.5, done: Callable = None):
        def _run():
            if delay > 0:
                time.sleep(delay)
            if MACOS:
                # osascript keystroke doesn't send newlines; split on \n and send Return (key code 36)
                lines = text.split('\n')
                parts = []
                for i, line in enumerate(lines):
                    if line:
                        safe = line.replace("\\", "\\\\").replace('"', '\\"')
                        parts.append(f'keystroke "{safe}"')
                    if i < len(lines) - 1:
                        parts.append('key code 36')
                if parts:
                    body = "\n    ".join(parts)
                    _run_osascript(f'tell application "System Events"\n    {body}\nend tell')
            else:
                ctrl = self._get_ctrl()
                if ctrl:
                    try:
                        ctrl.type(text)
                    except Exception:
                        pass
            if done:
                done()
        threading.Thread(target=_run, daemon=True).start()

    def run_cmd(self, cmd: str):
        subprocess.Popen(cmd, shell=True)


# ── Global hotkey listener ────────────────────────────────────────────────────

class GlobalHotkeyListener:
    """Listens globally for Ctrl+1–0 (slots) and a toggle hotkey for the popup.

    All callbacks are invoked on the pynput listener thread — callers must
    dispatch to the Qt main thread themselves (e.g. via QTimer.singleShot).
    """

    def __init__(
        self,
        on_slot: Callable[[int], None],
        on_toggle: Optional[Callable] = None,
        toggle_combo: str = "ctrl+shift+m",
    ):
        self._on_slot   = on_slot
        self._on_toggle = on_toggle
        parts = [p.strip().lower() for p in toggle_combo.split("+")]
        self._toggle_key  = parts[-1]
        self._toggle_mods = set(parts[:-1])
        self._listener    = None
        self._down: set   = set()
        self._paused      = False
        self._record_cb: Optional[Callable] = None
        self._record_last = 0.0

    def start(self) -> str:
        if not HAVE_PYNPUT:
            return "pynput not available"
        try:
            self._listener = _kb.Listener(
                on_press=self._press,
                on_release=self._release,
            )
            self._listener.start()
            return ""
        except Exception as e:
            self._listener = None
            return str(e)

    def stop(self):
        if self._listener:
            self._listener.stop()
            self._listener = None
        self._down.clear()

    def pause(self):
        """Suppress hotkey firing without stopping the listener thread."""
        self._paused = True

    def resume(self):
        """Re-enable hotkey firing; also clears any active recording."""
        self._paused = False
        self._record_cb = None

    def start_recording(self, cb: Callable):
        """Route all key events to cb instead of firing hotkeys."""
        self._record_cb = cb
        self._record_last = time.time()

    def stop_recording(self):
        """Stop recording mode; listener stays paused until resume() is called."""
        self._record_cb = None

    def _pressed(self, *names: str) -> bool:
        for name in names:
            if any(k in self._down for k in (f"Key.{name}", f"Key.{name}_l", f"Key.{name}_r")):
                return True
        return False

    def _press(self, key):
        k = _key_str(key)
        self._down.add(k)

        if self._record_cb is not None:
            now = time.time()
            d = round(now - self._record_last, 4)
            self._record_last = now
            try:
                from store import KeyEvent as KE
                self._record_cb(KE(t="p", k=k, d=d))
            except Exception:
                pass
            return

        if self._paused:
            return

        ctrl  = self._pressed("ctrl")
        shift = self._pressed("shift")

        if ctrl and not shift and len(k) == 1 and k.isdigit():
            slot = int(k) if k != "0" else 10
            self._on_slot(slot)
            return

        if self._on_toggle:
            mod_ok = all(self._pressed(m) for m in self._toggle_mods)
            if mod_ok and k == self._toggle_key:
                self._on_toggle()

    def _release(self, key):
        k = _key_str(key)
        self._down.discard(k)

        if self._record_cb is not None:
            now = time.time()
            d = round(now - self._record_last, 4)
            self._record_last = now
            try:
                from store import KeyEvent as KE
                self._record_cb(KE(t="r", k=k, d=d))
            except Exception:
                pass
