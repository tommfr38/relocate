# PyInstaller spec for Relocate (Windows).
#   pyinstaller packaging/Relocate.spec
#
# pymobiledevice3 resolves a lot of its surface dynamically (service classes, the
# pure-Python TCP stack used by the userspace tunnel, cryptography backends), so it is
# collected wholesale rather than relying on PyInstaller's static import analysis.

from PyInstaller.utils.hooks import collect_all, collect_submodules

datas, binaries, hiddenimports = [], [], []

# customtkinter and tkintermapview ship theme JSON / assets that must be bundled, and
# pymobiledevice3 resolves much of its surface dynamically (service classes, the pure
# Python TCP stack behind the userspace tunnel, cryptography backends).
required_packages = ("customtkinter", "tkintermapview", "pymobiledevice3", "construct", "cryptography")
# Optional extras that don't exist for every pymobiledevice3 version.
optional_packages = ("pytun_pmd3", "qh3")

for package in required_packages:
    # Not wrapped in try/except: if one of these fails to collect, the resulting exe
    # launches fine and then crashes on first use with a ModuleNotFoundError, which is
    # far harder to diagnose than a build-time failure. Fail the build instead.
    pkg_datas, pkg_binaries, pkg_hidden = collect_all(package)
    datas += pkg_datas
    binaries += pkg_binaries
    hiddenimports += pkg_hidden

for package in optional_packages:
    try:
        pkg_datas, pkg_binaries, pkg_hidden = collect_all(package)
    except Exception:
        continue
    datas += pkg_datas
    binaries += pkg_binaries
    hiddenimports += pkg_hidden

hiddenimports += collect_submodules("relocate")

# icon.png backs the toolbar button; icon.ico is what iconbitmap() wants for the title
# bar, and is loaded at runtime from this same directory, so it has to ship too.
datas += [
    ("../relocate/resources/icon.png", "relocate/resources"),
    ("../relocate/resources/icon.ico", "relocate/resources"),
]

a = Analysis(
    ["../main.py"],
    pathex=[".."],
    binaries=binaries,
    datas=datas,
    hiddenimports=hiddenimports,
    hookspath=[],
    runtime_hooks=[],
    # Heavy libraries this app never touches. tkinter itself must NOT be excluded —
    # CustomTkinter is built on it.
    excludes=[
        "PySide6",
        "PyQt5",
        "PyQt6",
        "matplotlib",
        "numpy.distutils",
        "pytest",
    ],
    noarchive=False,
)

pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name="Relocate",
    debug=False,
    strip=False,
    upx=False,
    console=False,  # GUI app: no console window
    icon="../relocate/resources/icon.ico",
)

coll = COLLECT(
    exe,
    a.binaries,
    a.datas,
    strip=False,
    upx=False,
    name="Relocate",
)
