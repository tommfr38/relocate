"""PyInstaller entry point (equivalent to `python -m relocate`)."""

from relocate.__main__ import main

if __name__ == "__main__":
    raise SystemExit(main())
