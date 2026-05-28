import json, os
from dataclasses import dataclass, asdict

_PATH = os.path.expanduser("~/.mac-macro/settings.json")


@dataclass
class Settings:
    toggle_hotkey: str = "ctrl+shift+m"
    grid_cols: int = 4
    grid_rows: int = 3


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
