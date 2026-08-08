"""Persistence for saved places and preferences.

Kept free of Qt so the core stays unit-testable on any platform.
"""

from __future__ import annotations

import json
import logging
import os
import sys
from pathlib import Path
from typing import Any

from .models import LocationPoint, SavedPlace

log = logging.getLogger(__name__)

DEFAULT_PLACES: tuple[tuple[str, float, float], ...] = (
    ("Apple Park", 37.3349, -122.0090),
    ("Budapest", 47.4979, 19.0402),
    ("London", 51.5074, -0.1278),
)


def config_dir() -> Path:
    """%APPDATA%\\Relocate on Windows; the usual XDG-ish spot elsewhere."""
    if sys.platform == "win32":
        base = os.environ.get("APPDATA") or str(Path.home() / "AppData" / "Roaming")
    elif sys.platform == "darwin":
        base = str(Path.home() / "Library" / "Application Support")
    else:
        base = os.environ.get("XDG_CONFIG_HOME") or str(Path.home() / ".config")
    path = Path(base) / "Relocate"
    path.mkdir(parents=True, exist_ok=True)
    return path


def _places_file() -> Path:
    return config_dir() / "places.json"


def _settings_file() -> Path:
    return config_dir() / "settings.json"


def default_places() -> list[SavedPlace]:
    return [
        SavedPlace(name=name, point=LocationPoint(name=name, latitude=lat, longitude=lon))
        for name, lat, lon in DEFAULT_PLACES
    ]


def load_places() -> list[SavedPlace]:
    path = _places_file()
    if not path.exists():
        return default_places()
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
        places = [SavedPlace.from_dict(entry) for entry in raw]
        return places
    except (OSError, ValueError, TypeError):
        log.warning("could not read %s; falling back to defaults", path, exc_info=True)
        return default_places()


def save_places(places: list[SavedPlace]) -> None:
    try:
        _places_file().write_text(
            json.dumps([p.to_dict() for p in places], indent=2), encoding="utf-8"
        )
    except OSError:
        log.warning("could not persist saved places", exc_info=True)


def load_settings() -> dict[str, Any]:
    path = _settings_file()
    if not path.exists():
        return {}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


def save_settings(settings: dict[str, Any]) -> None:
    try:
        _settings_file().write_text(json.dumps(settings, indent=2), encoding="utf-8")
    except OSError:
        log.warning("could not persist settings", exc_info=True)
