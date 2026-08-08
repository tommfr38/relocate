"""The iPhone setup walkthrough.

Mirrors the macOS build's tutorial, with one extra step at the front: Windows has no
built-in Apple device stack, so Apple Mobile Device Service has to be installed
before usbmux can see the iPhone at all.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Optional

import customtkinter as ctk

from . import theme


@dataclass(frozen=True)
class Step:
    title: str
    summary: str
    details: tuple[str, ...]
    caution: Optional[str] = None


STEPS: tuple[Step, ...] = (
    Step(
        title="Install Apple device support",
        summary="Windows needs Apple's USB driver before it can see an iPhone.",
        details=(
            "Install the Apple Devices app from the Microsoft Store, or iTunes from apple.com.",
            "Both install Apple Mobile Device Service, which Relocate talks to.",
            "Reboot if the iPhone still is not detected afterwards.",
        ),
        caution="Without this, no iPhone will ever appear — the most common cause of an empty device list on Windows.",
    ),
    Step(
        title="Connect with a cable",
        summary="Plug the iPhone directly into this PC.",
        details=(
            "Use a cable that carries data — charge-only cables will not work.",
            "Prefer a port on the PC itself over an unpowered hub.",
            "Relocate never changes location over Wi-Fi. The wired connection is required.",
        ),
    ),
    Step(
        title="Unlock and tap Trust",
        summary="The iPhone must trust this PC before it accepts developer commands.",
        details=(
            "Unlock the iPhone with Face ID, Touch ID, or your passcode.",
            'When "Trust This Computer?" appears, tap Trust.',
            "Enter the device passcode to confirm.",
        ),
        caution="Missed the prompt? Unplug the cable, plug it back in, and keep the phone unlocked.",
    ),
    Step(
        title="Turn on Developer Mode",
        summary="On the iPhone, open Settings › Privacy & Security › Developer Mode.",
        details=(
            "Toggle Developer Mode on.",
            "Tap Restart when iOS asks — the iPhone reboots.",
            "After it restarts, unlock it, tap Turn On, and enter your passcode.",
        ),
        caution="Developer Mode only appears once the iPhone has been connected to a computer with developer tools at least once.",
    ),
    Step(
        title="Simulate, then restore",
        summary="Choose the device, pick a spot, then press Set Location.",
        details=(
            "Click anywhere on the map, or type coordinates, to choose a point.",
            "Press Set Location to move the iPhone there.",
            "Press Stop to hand control back to the real GPS.",
        ),
        caution="Keep the iPhone unlocked and connected. iOS still reports the location as simulated — Relocate does not hide or bypass that.",
    ),
)


class TutorialDialog(ctk.CTkToplevel):
    def __init__(self, parent) -> None:
        super().__init__(parent)
        self.title("iPhone Setup Tutorial")
        self.geometry("620x580")
        self.minsize(560, 520)
        self.configure(fg_color=theme.BG)

        self._index = 0

        header = ctk.CTkFrame(self, fg_color="transparent")
        header.pack(fill="x", padx=26, pady=(22, 0))

        self._heading = ctk.CTkLabel(
            header, text="", font=(theme.FONT, 21, "bold"),
            text_color=theme.TEXT, anchor="w",
        )
        self._heading.pack(fill="x")

        self._progress = ctk.CTkLabel(
            header, text="", font=(theme.FONT, 12),
            text_color=theme.TEXT_DIM, anchor="w",
        )
        self._progress.pack(fill="x", pady=(2, 0))

        card = ctk.CTkFrame(self, fg_color=theme.CARD, corner_radius=theme.CORNER_LG)
        card.pack(fill="both", expand=True, padx=26, pady=18)

        self._summary = ctk.CTkLabel(
            card, text="", font=(theme.FONT, 14), text_color=theme.TEXT_DIM,
            anchor="w", justify="left", wraplength=520,
        )
        self._summary.pack(fill="x", padx=22, pady=(20, 14))

        self._steps_frame = ctk.CTkFrame(card, fg_color="transparent")
        self._steps_frame.pack(fill="x", padx=22)

        self._caution = ctk.CTkLabel(
            card, text="", font=(theme.FONT, 12), text_color=theme.TEXT_DIM,
            anchor="w", justify="left", wraplength=490,
            fg_color="#16203a", corner_radius=theme.CORNER,
        )

        footer = ctk.CTkFrame(self, fg_color="transparent")
        footer.pack(fill="x", padx=26, pady=(0, 20))

        self._dots = ctk.CTkLabel(
            footer, text="", font=(theme.FONT, 13), text_color=theme.TEXT_FAINT,
        )
        self._dots.pack(side="left")

        self._next = ctk.CTkButton(
            footer, text="Next", width=96, height=34, corner_radius=theme.CORNER,
            fg_color=theme.ACCENT, hover_color=theme.ACCENT_HOVER,
            font=(theme.FONT, 13, "bold"), command=self._go_next,
        )
        self._next.pack(side="right")

        self._back = ctk.CTkButton(
            footer, text="Back", width=86, height=34, corner_radius=theme.CORNER,
            fg_color=theme.CARD, hover_color=theme.CARD_HOVER,
            border_width=1, border_color=theme.BORDER,
            text_color=theme.TEXT, font=(theme.FONT, 13), command=self._go_back,
        )
        self._back.pack(side="right", padx=(0, 8))

        self._render()

        self.transient(parent)
        self.after(120, self._grab)

    def _grab(self) -> None:
        try:
            self.grab_set()
            self.focus_force()
        except Exception:
            pass

    # ------------------------------------------------------------- paging

    def _go_back(self) -> None:
        if self._index > 0:
            self._index -= 1
            self._render()

    def _go_next(self) -> None:
        if self._index < len(STEPS) - 1:
            self._index += 1
            self._render()
        else:
            self.destroy()

    def _render(self) -> None:
        step = STEPS[self._index]
        self._heading.configure(text=step.title)
        self._progress.configure(text=f"Step {self._index + 1} of {len(STEPS)}")
        self._summary.configure(text=step.summary)

        for child in self._steps_frame.winfo_children():
            child.destroy()

        for number, detail in enumerate(step.details, start=1):
            row = ctk.CTkFrame(self._steps_frame, fg_color="transparent")
            row.pack(fill="x", pady=4)
            ctk.CTkLabel(
                row, text=str(number), width=22, height=22,
                corner_radius=11, fg_color=theme.ACCENT, text_color="#ffffff",
                font=(theme.FONT, 11, "bold"),
            ).pack(side="left", padx=(0, 11), anchor="n")
            ctk.CTkLabel(
                row, text=detail, font=(theme.FONT, 13), text_color=theme.TEXT,
                anchor="w", justify="left", wraplength=460,
            ).pack(side="left", fill="x", expand=True)

        if step.caution:
            self._caution.configure(text=step.caution)
            self._caution.pack(fill="x", padx=22, pady=(16, 20), ipady=10, ipadx=10)
        else:
            self._caution.pack_forget()

        self._dots.configure(
            text="  ".join("●" if i == self._index else "○" for i in range(len(STEPS)))
        )

        self._back.configure(state="normal" if self._index > 0 else "disabled")
        self._next.configure(text="Done" if self._index == len(STEPS) - 1 else "Next")
