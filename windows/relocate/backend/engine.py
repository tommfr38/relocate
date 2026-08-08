"""The location-simulation session.

This is where the Windows port diverges from macOS by design. The macOS app drives
the `pymobiledevice3` **command line** and has to work around it:

* a one-shot `simulate-location set` is overridden by the device's next real GPS fix
  after ~5-10 seconds, so macOS holds a position by generating a 21,601-point GPX
  file that repeats the same coordinate every 2 seconds for 12 hours and replaying it;
* route progress can only be *estimated* from elapsed time, because nothing reports
  which point the device actually reached.

On Windows there is no Xcode tooling at all, so `pymobiledevice3` is used directly as
a **library**. That removes the CLI entirely: holding a position is a plain loop that
re-asserts the coordinate every couple of seconds, and route playback reports real
progress because this process is the thing sending each point.
"""

from __future__ import annotations

import asyncio
import logging
from contextlib import AsyncExitStack
from typing import Awaitable, Callable, Optional, Sequence

from pymobiledevice3.remote.userspace_tunnel import UserspaceRsdTunnel
from pymobiledevice3.services.dvt.instruments.dvt_provider import DvtProvider
from pymobiledevice3.services.dvt.instruments.location_simulation import LocationSimulation

from ..core import geometry
from ..core.models import InvalidCoordinateError, LocationPoint, RelocateError

log = logging.getLogger(__name__)

ProgressCallback = Callable[[float, LocationPoint], None]
FinishedCallback = Callable[[Optional[str]], None]


class LocationEngine:
    """Owns the tunnel, the DVT location channel, and the running simulation task.

    Every method must be awaited on the engine's own event loop (see AsyncWorker).
    """

    def __init__(self) -> None:
        self._stack: Optional[AsyncExitStack] = None
        self._simulation: Optional[LocationSimulation] = None
        self._udid: Optional[str] = None
        self._task: Optional[asyncio.Task] = None

    # ---------------------------------------------------------------- session

    @property
    def is_running(self) -> bool:
        return self._task is not None and not self._task.done()

    async def _ensure_session(self, udid: str) -> LocationSimulation:
        """Open (or reuse) the tunnel + DVT channel for this device.

        Establishing the iOS 17+ tunnel takes a few seconds, so an existing session
        for the same device is reused rather than torn down and rebuilt between a
        'set location' and a subsequent 'play route'.
        """
        if self._simulation is not None and self._udid == udid:
            return self._simulation

        await self._close_session()

        stack = AsyncExitStack()
        try:
            # A no-root, in-process userspace tunnel — the library equivalent of the
            # CLI's --userspace flag, which the macOS app also relies on.
            rsd = await stack.enter_async_context(UserspaceRsdTunnel(serial=udid))
            dvt = await stack.enter_async_context(DvtProvider(rsd))
            simulation = await stack.enter_async_context(LocationSimulation(dvt))
        except Exception as exc:
            await stack.aclose()
            raise RelocateError(_friendly(exc)) from exc

        self._stack = stack
        self._simulation = simulation
        self._udid = udid
        return simulation

    async def _close_session(self) -> None:
        self._simulation = None
        self._udid = None
        if self._stack is not None:
            stack, self._stack = self._stack, None
            try:
                await stack.aclose()
            except Exception:
                log.debug("ignoring tunnel teardown error", exc_info=True)

    async def _cancel_task(self) -> None:
        if self._task is None:
            return
        task, self._task = self._task, None
        task.cancel()
        try:
            await task
        except (asyncio.CancelledError, Exception):
            pass

    # ------------------------------------------------------------- operations

    async def set_location(
        self,
        udid: str,
        point: LocationPoint,
        on_finished: Optional[FinishedCallback] = None,
    ) -> None:
        """Move the device to `point` and hold it there until stopped."""
        if not point.is_valid:
            raise InvalidCoordinateError()

        await self._cancel_task()
        simulation = await self._ensure_session(udid)

        # Assert once up front so a failure surfaces immediately instead of inside
        # the background task, where the UI could not report it.
        await simulation.set(point.latitude, point.longitude)

        self._task = asyncio.ensure_future(self._hold(simulation, point, on_finished))

    async def _hold(
        self,
        simulation: LocationSimulation,
        point: LocationPoint,
        on_finished: Optional[FinishedCallback],
    ) -> None:
        """Re-assert one coordinate forever.

        iOS overrides a single simulated fix with the next real GPS fix after a few
        seconds, so the coordinate has to be repeated well inside that window.
        """
        error: Optional[str] = None
        try:
            while True:
                await asyncio.sleep(geometry.HOLD_INTERVAL)
                await simulation.set(point.latitude, point.longitude)
        except asyncio.CancelledError:
            raise
        except Exception as exc:
            log.exception("hold loop failed")
            error = _friendly(exc)
            if on_finished is not None:
                on_finished(error)

    async def play_route(
        self,
        udid: str,
        points: Sequence[LocationPoint],
        speed_mps: float,
        on_progress: Optional[ProgressCallback] = None,
        on_finished: Optional[FinishedCallback] = None,
    ) -> None:
        """Drive the device along `points` at `speed_mps`, then hold the last point."""
        if len(points) < 2:
            raise RelocateError("A route needs at least two waypoints.")
        if not all(p.is_valid for p in points):
            raise InvalidCoordinateError()

        await self._cancel_task()
        simulation = await self._ensure_session(udid)

        # Interpolate: playback moves the device to each point in turn, so raw
        # waypoints alone would teleport it straight to the destination.
        track = geometry.densify(points, speed_mps, start_time=0.0)
        await simulation.set(track[0].latitude, track[0].longitude)

        self._task = asyncio.ensure_future(
            self._play(simulation, track, on_progress, on_finished)
        )

    async def _play(
        self,
        simulation: LocationSimulation,
        track: Sequence[LocationPoint],
        on_progress: Optional[ProgressCallback],
        on_finished: Optional[FinishedCallback],
    ) -> None:
        loop = asyncio.get_running_loop()
        started = loop.time()
        last = track[-1]
        error: Optional[str] = None

        try:
            for index, point in enumerate(track):
                # Track points carry offsets from 0.0, so pace against the start.
                delay = (point.timestamp or 0.0) - (loop.time() - started)
                if delay > 0:
                    await asyncio.sleep(delay)
                await simulation.set(point.latitude, point.longitude)
                if on_progress is not None:
                    fraction = (index + 1) / len(track)
                    on_progress(fraction, point)

            if on_finished is not None:
                on_finished(None)

            # Keep holding the destination, exactly as the macOS build does once a
            # route runs out, so the device does not snap back to its real location.
            while True:
                await asyncio.sleep(geometry.HOLD_INTERVAL)
                await simulation.set(last.latitude, last.longitude)
        except asyncio.CancelledError:
            raise
        except Exception as exc:
            log.exception("route playback failed")
            error = _friendly(exc)
            if on_finished is not None:
                on_finished(error)

    async def stop(self) -> None:
        """Stop simulating and hand control back to the device's real GPS."""
        await self._cancel_task()

        simulation = self._simulation
        if simulation is not None:
            try:
                await simulation.clear()
            except Exception:
                log.exception("clear failed")

        await self._close_session()


def _friendly(exc: BaseException) -> str:
    """Turn a backend exception into something worth showing a person."""
    name = type(exc).__name__
    text = str(exc).strip()

    if "NotPaired" in name or "Pairing" in name:
        return "The iPhone is not trusted. Unlock it, reconnect the cable, and tap Trust."
    if "PasswordRequired" in name:
        return "Unlock the iPhone with its passcode, then try again."
    if "DeveloperMode" in name or "developer mode" in text.lower():
        return "Enable Developer Mode on the iPhone (Settings > Privacy & Security)."
    if "NoDeviceConnected" in name or "DeviceNotFound" in name:
        return "No iPhone found. Check the cable and that it is a data cable."
    if "ConnectionFailed" in name or "ConnectionAborted" in name:
        return "Lost the connection to the iPhone. Check the cable and keep the device unlocked."
    if "Tunnel" in name:
        return (
            "Could not open the developer tunnel. Make sure the iPhone is unlocked, "
            "trusted, and has Developer Mode enabled."
        )
    return text or f"{name} while talking to the device."
