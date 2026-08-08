"""Entry point: python -m relocate"""

from __future__ import annotations

import logging
import sys
from pathlib import Path

import customtkinter as ctk

from .core.places import config_dir
from .ui.main_window import MainWindow


def _configure_logging() -> None:
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
        handlers=[
            logging.StreamHandler(sys.stderr),
            logging.FileHandler(config_dir() / "relocate.log", encoding="utf-8"),
        ],
    )
    # The tunnel stack is chatty at INFO; keep our own logs readable.
    logging.getLogger("pymobiledevice3").setLevel(logging.WARNING)


def main() -> int:
    _configure_logging()

    ctk.set_appearance_mode("dark")
    ctk.set_default_color_theme("blue")

    window = MainWindow()

    icon = Path(__file__).parent / "resources" / "icon.ico"
    if icon.exists():
        try:
            window.iconbitmap(str(icon))
        except Exception:
            # iconbitmap only supports .ico on Windows; harmless elsewhere.
            pass

    window.mainloop()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
