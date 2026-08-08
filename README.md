# Relocate

Relocate is a native macOS location-simulation workspace for iOS development and QA. It supports:

- Native iOS Simulator control through `xcrun simctl`
- Trusted, cable-connected physical iPhones through `pymobiledevice3`
- Map search, precise coordinates, saved places, route design, GPX import/export, and speed control
- Explicit simulation state, one-click restoration, and automatic cleanup on normal app quit

Relocate does not jailbreak devices, hide simulated-location metadata, or bypass iOS security. Use it only with devices you own or are authorized to test.

## Requirements

- macOS 14 or later
- Xcode with the iOS platform installed
- For physical devices: Developer Mode enabled, USB trust established, and `pymobiledevice3`

```sh
brew install pipx
pipx install pymobiledevice3
pymobiledevice3 mounter auto-mount
```

## Build and run

```sh
swift build
swift run Relocate
```

Run tests:

```sh
swift test
```

Create a distributable `.app` bundle:

```sh
./scripts/package-app.sh
open dist/Relocate.app
```

## Installer

Build a standard macOS `.pkg` installer that installs Relocate to `/Applications` and, on
a best-effort basis, sets up the `pymobiledevice3` backend for physical-device sessions:

```sh
./scripts/build-installer.sh
open dist/Relocate-Installer.pkg
```

The installer:

- Installs `Relocate.app` into `/Applications`
- Runs a postinstall step that installs `pipx` and `pymobiledevice3` for the person running
  the installer (via Homebrew if present, otherwise via `pip install --user`), skipping
  cleanly if neither Homebrew nor Python is available — Relocate's own **Help → iPhone
  Setup Tutorial** covers manual setup in that case
- Logs the dependency-install step to `/var/log/relocate-install.log`
- Quits a running Relocate before an upgrade install replaces its files

The `.pkg` is unsigned unless a `Developer ID Installer` certificate is present in your
keychain (the build script detects one automatically and prints the `productsign` command
to finish signing). An unsigned installer is flagged by Gatekeeper as being from an
unidentified developer; recipients can proceed via right-click → Open in Finder, the
standard macOS path for unsigned installers.

## Windows

A Windows mirror lives in [`windows/`](windows/) — Python 3 + CustomTkinter, using
`pymobiledevice3` as an in-process library rather than a CLI. See
[windows/README.md](windows/README.md) for the rationale, requirements, and build
instructions. It is physical-device only: Windows has no iOS Simulator.

## Platform behavior

Simulator sessions use Apple’s documented CoreSimulator location API. Physical sessions use Apple developer services over the trusted device connection. On iOS 17 and later this may require the system’s developer tunnel; current `pymobiledevice3` handles service-provider selection on supported macOS/iOS versions.

Static physical-device sessions intentionally remain attached to their helper process. Stopping from Relocate interrupts that session and sends a separate clear command so the iPhone returns to its real Core Location source.
