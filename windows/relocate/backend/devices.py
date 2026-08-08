"""Device discovery over usbmux.

Windows has no Xcode, so there is no `devicectl` and no iOS Simulator: every target
is a physical iPhone reached through Apple Mobile Device Service (installed with
iTunes / the Apple Devices app), which is what usbmux talks to.

The macOS app learned not to gate availability on a tunnel being up — a wired,
trusted device is usable even when no tunnel exists yet. The equivalent signal here
is whether a lockdown session can be established at all, which is exactly "is this
device paired and trusted".
"""

from __future__ import annotations

import asyncio
import logging
from typing import Optional

from pymobiledevice3 import usbmux
from pymobiledevice3.exceptions import (
    ConnectionFailedError,
    NotPairedError,
    PairingError,
)
from pymobiledevice3.lockdown import create_using_usbmux

from ..core.models import DeviceTarget

log = logging.getLogger(__name__)

# Marketing names for the identifiers most likely to show up in testing; anything
# unknown falls back to the raw ProductType, which is still meaningful.
_PRODUCT_NAMES = {
    "iPhone14,7": "iPhone 14",
    "iPhone15,2": "iPhone 14 Pro",
    "iPhone15,4": "iPhone 15",
    "iPhone16,1": "iPhone 15 Pro",
    "iPhone16,2": "iPhone 15 Pro Max",
    "iPhone17,1": "iPhone 16 Pro",
    "iPhone17,2": "iPhone 16 Pro Max",
    "iPhone17,3": "iPhone 16",
    "iPhone18,1": "iPhone 17 Pro",
    "iPhone18,2": "iPhone 17 Pro Max",
}


def _model_name(product_type: Optional[str]) -> str:
    if not product_type:
        return "iPhone"
    return _PRODUCT_NAMES.get(product_type, product_type)


async def list_devices() -> list[DeviceTarget]:
    """Enumerate connected devices, preferring the wired connection for each.

    usbmux reports a device once per transport, so the same iPhone can appear twice
    (USB and Network). Relocate only simulates over the cable, so USB wins.
    """
    try:
        mux_devices = await usbmux.list_devices()
    except ConnectionRefusedError:
        log.warning("usbmux is not reachable — is Apple Mobile Device Service running?")
        return []
    except Exception:
        log.exception("usbmux enumeration failed")
        return []

    by_serial: dict[str, bool] = {}
    for device in mux_devices:
        # Prefer the wired entry when the same device is reported on both transports.
        by_serial[device.serial] = by_serial.get(device.serial, False) or device.is_usb

    targets: list[DeviceTarget] = []
    for serial, is_usb in by_serial.items():
        targets.append(await _describe(serial, is_usb))

    targets.sort(key=lambda t: (not t.is_available, t.name.lower()))
    return targets


async def _describe(serial: str, is_usb: bool) -> DeviceTarget:
    """Fetch a device's details; an unpaired device is listed but not available."""
    # Relocate simulates over the cable, so make a Wi-Fi-only device obvious rather
    # than showing an opaque transport name.
    connection = "USB" if is_usb else "Wi-Fi (connect a cable)"
    try:
        lockdown = await create_using_usbmux(serial=serial, autopair=False)
    except (NotPairedError, PairingError):
        return DeviceTarget(
            udid=serial,
            name="iPhone (not trusted)",
            model="Tap Trust on the device",
            os_version="",
            connection=connection,
            is_available=False,
        )
    except Exception:
        log.exception("could not read device info for %s", serial)
        return DeviceTarget(
            udid=serial,
            name="iPhone (unavailable)",
            model="",
            os_version="",
            connection=connection,
            is_available=False,
        )

    try:
        # short_info is a property, not a method.
        info = lockdown.short_info
        return DeviceTarget(
            udid=serial,
            name=info.get("DeviceName") or "iPhone",
            model=_model_name(info.get("ProductType")),
            os_version=info.get("ProductVersion") or "",
            connection=connection,
            # Reaching lockdown at all means the device is paired and trusted.
            is_available=True,
        )
    finally:
        close = getattr(lockdown, "aclose", None) or getattr(lockdown, "close", None)
        if close is not None:
            try:
                result = close()
                if asyncio.iscoroutine(result):
                    await result
            except Exception:
                log.debug("ignoring lockdown close error", exc_info=True)
