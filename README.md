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

## Platform behavior

Simulator sessions use Apple’s documented CoreSimulator location API. Physical sessions use Apple developer services over the trusted device connection. On iOS 17 and later this may require the system’s developer tunnel; current `pymobiledevice3` handles service-provider selection on supported macOS/iOS versions.

Static physical-device sessions intentionally remain attached to their helper process. Stopping from Relocate interrupts that session and sends a separate clear command so the iPhone returns to its real Core Location source.
