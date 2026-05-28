import json, os
from dataclasses import dataclass, asdict

_PATH = os.path.expanduser("~/.mac-macro/settings.json")


@dataclass
class Settings:
    toggle_hotkey: str = "ctrl+shift+m"
    grid_cols: int = 4
    grid_rows: int = 3
    card_opacity: float = 0.72   # 0.10 (very see-through) .. 1.00 (solid)
    tile_opacity: float = 1.00   # 0.10 .. 1.00


def load() -> Settings:
    try:
        if os.path.exists(_PATH):
            with open(_PATH) as f:
                d = json.load(f)
            valid = Settings.__dataclass_fields__
            return Settings(**{k: v for k, v in d.items() if k in valid})
    except Exception:
        pass
    return Settings()


def save(s: Settings):
    os.makedirs(os.path.dirname(_PATH), exist_ok=True)
    with open(_PATH, "w") as f:
        json.dump(asdict(s), f, indent=2)
