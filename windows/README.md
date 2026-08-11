# Relocate for Windows

A Windows mirror of the macOS Relocate app: simulate the GPS location of a
cable-connected iPhone, for development and QA on devices you own or are authorized
to test.

Built with **Python 3 + CustomTkinter**, using **pymobiledevice3 as a library**.

## Why Python rather than C#/WinUI

The choice follows from what is actually reachable on Windows.

macOS reaches the device through Xcode (`simctl`, `devicectl`) *and* `pymobiledevice3`.
Windows has none of the Xcode tooling, so `pymobiledevice3` — a pure-Python
implementation of Apple's device protocols — is the only path to an iPhone. Writing
the app in Python lets it call that library **in-process** instead of shelling out to
its command line, which removes an entire class of problems the macOS build had to
work around:

| | macOS build (CLI subprocess) | This build (in-process library) |
|---|---|---|
| Holding a static location | iOS overrides a one-shot `set` after ~5-10 s, so it generates a **21,601-point, 12-hour GPX** that repeats one coordinate every 2 s and replays it | A plain `while` loop that re-asserts the coordinate every 2 s |
| Route progress | Estimated from elapsed wall-clock time; drifts if playback stalls | Reported from the point actually being sent |
| Argument handling | Broke on `--udid` placement (`No such option: --udid`) | No command line at all |
| Session lifetime | Depends on keeping a child process alive | An object this process owns |

There is no iOS Simulator on Windows, so — unlike macOS — every target is a physical
device.

## Requirements

- Windows 10/11 (x64)
- **Tk 8.6** — bundled with the python.org installer and with the packaged build.
  Some Linux/macOS Pythons (including Homebrew's) ship without it; `python -c "import
  tkinter"` must succeed.
- **Apple Mobile Device Support**, from the
  [Apple Devices app](https://apps.microsoft.com/detail/9np83lwlpz9k) or iTunes.
  Without it Windows cannot see an iPhone at all — this is the usual cause of an
  empty device list.
- An iPhone with **Developer Mode** enabled, connected by a **data-capable cable**,
  unlocked and trusted.
- Python 3.10+ (only to run from source; the packaged build bundles its own).

## Run from source

```powershell
python -m venv .venv
.venv\Scripts\pip install -r requirements.txt
.venv\Scripts\python -m relocate
```

## Tests

```powershell
.venv\Scripts\python -m pytest tests -q
```

The suite covers the geometry and GPX logic, including the specific bugs fixed in the
macOS build: routes must be written as `<trkpt>` track points (playback ignores
`<wpt>` entirely and silently plays nothing), routes must be interpolated or the
device teleports between waypoints, and the interpolation sample count must stay
bounded.

## Build the installer

```powershell
powershell -ExecutionPolicy Bypass -File packaging\build.ps1
```

This runs the tests, builds `dist\Relocate\Relocate.exe` with PyInstaller, and — if
[Inno Setup](https://jrsoftware.org/isdl.php) is installed — produces
`dist\Relocate-Setup-1.0.0.exe`. The installer warns if Apple Mobile Device Support
is missing.

PyInstaller cannot cross-compile: the Windows executable has to be built on Windows.

## Layout

```
relocate/
  core/       models, great-circle geometry, GPX codec, settings  (UI-free, unit-tested)
  backend/    usbmux discovery, the DVT location session, asyncio->Tk bridge
  ui/         main window, setup tutorial, theme
packaging/    PyInstaller spec, Inno Setup script, build script
tests/        core logic tests
```

The map is `tkintermapview` pointed at Esri's Dark Gray Canvas — a true mid-dark
basemap, where CARTO's `dark_all` is so near-black it disappears against this chrome.
No embedded browser is involved, which keeps the packaged build small. Tiles are
cached on disk by the widget.

`core/` and `backend/` deliberately import no UI toolkit, so the device logic is
testable headlessly and the front end stays replaceable.

## Verification status

Verified on this machine (macOS, against a real iPhone — the backend is
OS-independent Python):

- 17/17 core tests pass.
- Device discovery returns the real device, its model, and iOS version.
- Opening the tunnel and setting a location works; the hold loop was measured
  re-asserting at **2.03-2.09 s** intervals.
- Route playback produced 12 real progress callbacks, moved monotonically along the
  route, reached exactly 100%, and restored the real location on stop.
- The UI runs and renders: dark map tiles, markers, saved-place cards, readiness
  checks, and correct enabled/disabled button states.

Verified on Windows 11 (x64), against an iPhone 17 Pro Max on iOS 26.6 over USB:

- The PyInstaller build and the Inno Setup installer both produce working output, and
  the installed app launches and renders (map tiles, markers, saved places, native
  Segoe UI chrome).
- usbmux via Apple Mobile Device Service resolves the device, its model and iOS
  version, and the readiness panel reports the service reachable.

Not verified on Windows yet:

- Setting a location and route playback against a connected device (the macOS runs
  above cover the same backend code, but not on this transport).

Build notes learned the hard way:

- Build on Python 3.10-3.12. `pymobiledevice3` pulls in `lzfse` and `pylzss`, C
  extensions with no wheels past 3.12, so a newer interpreter tries to compile them and
  fails without MSVC. `build.ps1` selects a supported interpreter for this reason.
- Apple Mobile Device Support must really be installed (the Apple Devices app or
  iTunes). An `iCloud`-only machine leaves an empty `Common Files\Apple\Mobile Device
  Support\{Drivers,NetDrivers}` skeleton with no service behind it, which looks like a
  working install but cannot see a device.

## Scope

Relocate does not jailbreak devices, hide simulated-location metadata, or bypass iOS
security. iOS continues to report the location as simulated. Use only with devices you
own or are authorized to test.
