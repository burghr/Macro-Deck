# MacroDeck

A Stream Deck–style macro launcher for macOS. Lives in the menu bar, fires user-defined macros with a global hotkey.

<p align="center">
  <img src="docs/popup.png"  width="430" alt="Popup grid of macro tiles">
  &nbsp;
  <img src="docs/editor.png" width="430" alt="Macro editor dialog">
</p>

## Features

- **Grid of macro tiles** — configurable columns × rows, opens as a translucent popup near the menu bar icon
- **Global hotkeys** — `⌃1`–`⌃0` runs the macro in that slot; `⌃⇧M` (configurable) toggles the popup
- **Three macro kinds**:
  - **Keys** — record any sequence of key presses and replay them
  - **Text** — type a snippet of text (multi-line supported)
  - **Command** — run a shell command
- **Lives in the menu bar** — no dock icon, no window stealing focus
- **Auto-starts at login** via a LaunchAgent

## Install

```
bash install.sh
```

That builds the app with `py2app`, copies it to `~/Applications/MacroDeck.app`, and registers a LaunchAgent so it starts at login.

First launch opens a permissions dialog asking for **Accessibility** (needed to play back keys into other apps) and **Input Monitoring** (needed for global hotkeys). After granting both, click **Restart Now** — the LaunchAgent restarts the app and hotkeys take effect.

Logs: `~/.mac-macro/macrodeck.log`
Data: `~/.mac-macro/macros.json` and `~/.mac-macro/settings.json`

## Uninstall

```
bash uninstall.sh
```

## Requirements

- macOS (built and tested on Apple Silicon, macOS 15)
- Python 3.9 (the system `/usr/bin/python3`)
- See `requirements.txt` for Python dependencies

## Project layout

| File | Purpose |
|---|---|
| `main.py` | PyQt6 UI — tray, popup grid, permissions and settings dialogs |
| `engine.py` | Recorder, Player, global hotkey listener (pynput) |
| `store.py` | Macro persistence (JSON) |
| `editor.py` | Per-macro editor dialog |
| `permissions.py` | macOS TCC checks for Accessibility / Input Monitoring |
| `settings.py` | App settings persistence |
| `setup.py` | py2app build config |
| `install.sh` / `uninstall.sh` | Build + LaunchAgent registration |
