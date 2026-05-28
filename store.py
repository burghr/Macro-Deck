import json, os, uuid
from dataclasses import dataclass, field, asdict
from typing import Optional


@dataclass
class KeyEvent:
    t: str    # 'p' press / 'r' release
    k: str    # key string
    d: float  # delay before event (seconds)


@dataclass
class Macro:
    id: str
    name: str
    kind: str = "keys"  # keys | text | cmd | media
    events: list = field(default_factory=list)
    text: str = ""
    cmd: str = ""
    media: str = ""  # action name when kind == "media" (vol_up, mute, etc.)
    icon: str = ""  # emoji shown on the tile, empty = none
    keep_open: bool = False  # if True, popup stays open after running this macro


class MacroStore:
    def __init__(self, path: str):
        self.path = path
        self._d: dict[int, Macro] = {}
        os.makedirs(os.path.dirname(path), exist_ok=True)
        self._load()

    def _load(self):
        if not os.path.exists(self.path):
            return
        try:
            valid = Macro.__dataclass_fields__
            with open(self.path) as f:
                for k, v in json.load(f).items():
                    self._d[int(k)] = Macro(**{f: v[f] for f in valid if f in v})
        except Exception:
            pass

    def save(self):
        with open(self.path, "w") as f:
            json.dump({str(k): asdict(m) for k, m in self._d.items()}, f, indent=2)

    def get(self, slot: int) -> Optional[Macro]:
        return self._d.get(slot)

    def set(self, slot: int, macro: Macro):
        self._d[slot] = macro
        self.save()

    def delete(self, slot: int):
        self._d.pop(slot, None)
        self.save()

    def new_macro(self, name: str = "New Macro") -> Macro:
        return Macro(id=str(uuid.uuid4()), name=name)
