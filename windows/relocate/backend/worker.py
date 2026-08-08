"""Bridges pymobiledevice3's asyncio world to Tk's single-threaded world.

All device work happens on a dedicated event-loop thread so the UI never blocks on a
tunnel handshake (which takes a few seconds). Tk widgets may only be touched from the
thread that owns the main loop, so results are funnelled through a queue that the GUI
drains on a timer.
"""

from __future__ import annotations

import asyncio
import logging
import queue
import threading
from typing import Any, Callable, Coroutine, Optional

log = logging.getLogger(__name__)

PUMP_INTERVAL_MS = 30


class AsyncWorker:
    """Runs an asyncio event loop on a background thread."""

    def __init__(self, tk_root: Any) -> None:
        self._root = tk_root
        self._queue: "queue.Queue[Callable[[], None]]" = queue.Queue()
        self._loop = asyncio.new_event_loop()
        # asyncio only holds a weak reference to running tasks, so a task with no other
        # referent can be garbage-collected mid-flight ("Task was destroyed but it is
        # pending!"). Keep them alive until they finish.
        self._tasks: set[asyncio.Task] = set()
        self._closing = False

        ready = threading.Event()

        def run() -> None:
            asyncio.set_event_loop(self._loop)
            self._loop.call_soon(ready.set)
            self._loop.run_forever()

        self._thread = threading.Thread(target=run, name="relocate-async", daemon=True)
        self._thread.start()
        ready.wait(timeout=5)
        self._pump()

    # ------------------------------------------------------------------ api

    def post_to_gui(self, fn: Callable[[], None]) -> None:
        """Run `fn` on the GUI thread. Safe to call from the asyncio thread."""
        self._queue.put(fn)

    def _pump(self) -> None:
        """Drain queued callbacks on the Tk thread."""
        while True:
            try:
                callback = self._queue.get_nowait()
            except queue.Empty:
                break
            try:
                callback()
            except Exception:
                log.exception("error in queued GUI callback")

        if not self._closing:
            try:
                self._root.after(PUMP_INTERVAL_MS, self._pump)
            except Exception:
                # The window is going away; stop rescheduling.
                self._closing = True

    def submit(
        self,
        coro: Coroutine[Any, Any, Any],
        on_success: Optional[Callable[[Any], None]] = None,
        on_error: Optional[Callable[[Exception], None]] = None,
    ) -> None:
        """Schedule `coro` on the worker loop; deliver the outcome to the GUI thread."""

        def _done(fut: "asyncio.Future[Any]") -> None:
            self._tasks.discard(fut)  # type: ignore[arg-type]
            try:
                result = fut.result()
            except asyncio.CancelledError:
                return
            except Exception as exc:  # noqa: BLE001 - surfaced to the UI
                log.debug("async task failed", exc_info=True)
                if on_error is not None:
                    self.post_to_gui(lambda exc=exc: on_error(exc))
                return
            if on_success is not None:
                self.post_to_gui(lambda result=result: on_success(result))

        def _schedule() -> None:
            task = self._loop.create_task(coro)
            self._tasks.add(task)
            task.add_done_callback(_done)

        self._loop.call_soon_threadsafe(_schedule)

    def run_blocking(self, coro: Coroutine[Any, Any, Any], timeout: float = 10.0) -> Any:
        """Run `coro` and wait for it. Only for shutdown, where blocking is acceptable."""
        future = asyncio.run_coroutine_threadsafe(coro, self._loop)
        try:
            return future.result(timeout=timeout)
        except Exception:
            log.debug("blocking call failed", exc_info=True)
            return None

    def shutdown(self, timeout: float = 5.0) -> None:
        """Cancel outstanding work and stop the loop."""
        self._closing = True

        async def _drain() -> None:
            current = asyncio.current_task()
            pending = [t for t in asyncio.all_tasks() if t is not current]
            for task in pending:
                task.cancel()
            for task in pending:
                try:
                    await task
                except BaseException:
                    pass

        done = threading.Event()

        def _stop() -> None:
            task = self._loop.create_task(_drain())
            task.add_done_callback(lambda _f: (self._loop.stop(), done.set()))

        try:
            self._loop.call_soon_threadsafe(_stop)
            done.wait(timeout=timeout)
        except RuntimeError:
            pass
        self._thread.join(timeout=timeout)
