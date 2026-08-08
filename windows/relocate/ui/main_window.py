"""The Relocate main window (CustomTkinter)."""

from __future__ import annotations

import logging
import tkinter as tk
from tkinter import filedialog, messagebox
from typing import Optional

import customtkinter as ctk
from tkintermapview import TkinterMapView
from tkintermapview.canvas_button import CanvasButton

from ..backend import devices as device_service
from ..backend.engine import LocationEngine
from ..backend.worker import AsyncWorker
from ..core import gpx, places as places_store
from ..core.models import (
    DeviceTarget,
    LocationPoint,
    RelocateError,
    SavedPlace,
    SimulationState,
)
from . import theme
from .tutorial import TutorialDialog

log = logging.getLogger(__name__)

MIN_SPEED_KMH = 3
MAX_SPEED_KMH = 162
DEFAULT_SPEED_KMH = 50

SIDEBAR_WIDTH = 260
INSPECTOR_WIDTH = 290


def _theme_map_buttons() -> None:
    """Recolour tkintermapview's built-in zoom buttons.

    They are canvas polygons hard-coded to "gray20", which clashes with this palette.
    The colours are reapplied on every draw/hover, so the drawing methods are wrapped
    rather than the items being recoloured once.
    """
    if getattr(CanvasButton, "_relocate_themed", False):
        return

    original_draw = CanvasButton.draw

    def draw(self) -> None:
        original_draw(self)
        self.map_widget.canvas.itemconfig(
            self.canvas_rect, fill=theme.CARD, outline=theme.CARD
        )
        self.map_widget.canvas.itemconfig(self.canvas_text, fill=theme.TEXT)

    # Bound as Tk event handlers, so they receive the event object.
    def hover_on(self, event=None) -> None:
        self.map_widget.canvas.itemconfig(
            self.canvas_rect, fill=theme.ACCENT, outline=theme.ACCENT
        )

    def hover_off(self, event=None) -> None:
        self.map_widget.canvas.itemconfig(
            self.canvas_rect, fill=theme.CARD, outline=theme.CARD
        )

    CanvasButton.draw = draw
    CanvasButton.hover_on = hover_on
    CanvasButton.hover_off = hover_off
    CanvasButton._relocate_themed = True


def section_label(parent, text: str) -> ctk.CTkLabel:
    return ctk.CTkLabel(
        parent,
        text=text.upper(),
        font=(theme.FONT, 10, "bold"),
        text_color=theme.TEXT_FAINT,
        anchor="w",
    )


class MainWindow(ctk.CTk):
    def __init__(self) -> None:
        super().__init__()
        _theme_map_buttons()
        self.title("Relocate")
        self.geometry("1320x840")
        self.minsize(1080, 680)
        self.configure(fg_color=theme.BG)

        self._worker = AsyncWorker(self)
        self._engine = LocationEngine()

        self._devices: list[DeviceTarget] = []
        self._places: list[SavedPlace] = places_store.load_places()
        self._route: list[LocationPoint] = []
        self._selected = LocationPoint(name="Budapest", latitude=47.4979, longitude=19.0402)
        self._state = SimulationState.IDLE

        self._pin_marker = None
        self._live_marker = None
        self._route_path = None
        self._route_markers: list = []
        self._suppress_field_sync = False

        self._build_ui()
        self._refresh_places()
        self._refresh_route()
        self._sync_selection(center=True)
        self._update_controls()

        self.protocol("WM_DELETE_WINDOW", self._on_close)
        self.after(300, self.refresh_devices)

    # ------------------------------------------------------------------ ui

    def _build_ui(self) -> None:
        self.grid_rowconfigure(1, weight=1)
        self.grid_columnconfigure(1, weight=1)

        self._build_toolbar()
        self._build_sidebar()
        self._build_map()
        self._build_inspector()
        self._build_statusbar()

    def _build_toolbar(self) -> None:
        bar = ctk.CTkFrame(self, height=58, corner_radius=0, fg_color=theme.PANEL)
        bar.grid(row=0, column=0, columnspan=3, sticky="ew")
        bar.grid_propagate(False)
        bar.grid_columnconfigure(1, weight=1)

        left = ctk.CTkFrame(bar, fg_color="transparent")
        left.grid(row=0, column=0, padx=(14, 0), pady=11, sticky="w")

        ctk.CTkButton(
            left, text="?", width=34, height=34, corner_radius=theme.CORNER,
            fg_color=theme.CARD, hover_color=theme.CARD_HOVER,
            border_width=1, border_color=theme.BORDER,
            text_color=theme.TEXT, font=(theme.FONT, 14, "bold"),
            command=self.show_tutorial,
        ).pack(side="left")

        right = ctk.CTkFrame(bar, fg_color="transparent")
        right.grid(row=0, column=2, padx=(0, 14), pady=11, sticky="e")

        self._device_menu = ctk.CTkOptionMenu(
            right, values=["No devices"], width=210, height=34,
            corner_radius=theme.CORNER, fg_color=theme.CARD,
            button_color=theme.CARD, button_hover_color=theme.CARD_HOVER,
            dropdown_fg_color=theme.CARD, dropdown_hover_color=theme.ACCENT,
            text_color=theme.TEXT, font=(theme.FONT, 13),
            command=self._on_device_selected,
        )
        self._device_menu.pack(side="left", padx=(0, 8))

        self._refresh_button = ctk.CTkButton(
            right, text="Refresh", width=86, height=34, corner_radius=theme.CORNER,
            fg_color=theme.CARD, hover_color=theme.CARD_HOVER,
            border_width=1, border_color=theme.BORDER,
            text_color=theme.TEXT, font=(theme.FONT, 13),
            command=self.refresh_devices,
        )
        self._refresh_button.pack(side="left", padx=(0, 8))

        self._primary_button = ctk.CTkButton(
            right, text="Set Location", width=140, height=34,
            corner_radius=theme.CORNER, fg_color=theme.ACCENT,
            hover_color=theme.ACCENT_HOVER, text_color="#ffffff",
            font=(theme.FONT, 13, "bold"), command=self._on_primary_clicked,
        )
        self._primary_button.pack(side="left")

    def _build_sidebar(self) -> None:
        panel = ctk.CTkFrame(self, width=SIDEBAR_WIDTH, corner_radius=0, fg_color=theme.PANEL)
        panel.grid(row=1, column=0, sticky="nsw")
        panel.grid_propagate(False)
        panel.grid_rowconfigure(3, weight=1)
        panel.grid_rowconfigure(6, weight=1)
        panel.grid_columnconfigure(0, weight=1)

        # Devices
        header = ctk.CTkFrame(panel, fg_color="transparent")
        header.grid(row=0, column=0, sticky="ew", padx=14, pady=(16, 6))
        section_label(header, "Devices").pack(fill="x")

        self._device_label = ctk.CTkLabel(
            panel, text="Looking for devices…", font=(theme.FONT, 12),
            text_color=theme.TEXT_DIM, anchor="w", justify="left", wraplength=224,
        )
        self._device_label.grid(row=1, column=0, sticky="ew", padx=14)

        ctk.CTkButton(
            panel, text="Connection setup", height=32, corner_radius=theme.CORNER,
            fg_color=theme.CARD, hover_color=theme.CARD_HOVER,
            border_width=1, border_color=theme.BORDER,
            text_color=theme.TEXT, font=(theme.FONT, 12),
            command=self.show_tutorial,
        ).grid(row=2, column=0, sticky="ew", padx=14, pady=(10, 14))

        # Saved places
        places_header = ctk.CTkFrame(panel, fg_color="transparent")
        places_header.grid(row=3, column=0, sticky="new", padx=14)
        places_header.grid_columnconfigure(0, weight=1)
        section_label(places_header, "Saved Places").grid(row=0, column=0, sticky="w")
        self._add_place_button = ctk.CTkButton(
            places_header, text="+", width=26, height=22, corner_radius=6,
            fg_color="transparent", hover_color=theme.CARD_HOVER,
            text_color=theme.TEXT_DIM, font=(theme.FONT, 15, "bold"),
            command=self._save_selected_place,
        )
        self._add_place_button.grid(row=0, column=1, sticky="e")

        self._places_frame = ctk.CTkScrollableFrame(
            panel, fg_color="transparent", scrollbar_button_color=theme.BORDER,
            scrollbar_button_hover_color=theme.TEXT_FAINT,
        )
        self._places_frame.grid(row=4, column=0, sticky="nsew", padx=8, pady=(6, 0))
        panel.grid_rowconfigure(4, weight=1)

        # Route
        route_header = ctk.CTkFrame(panel, fg_color="transparent")
        route_header.grid(row=5, column=0, sticky="ew", padx=14, pady=(12, 0))
        route_header.grid_columnconfigure(0, weight=1)
        section_label(route_header, "Route").grid(row=0, column=0, sticky="w")
        ctk.CTkButton(
            route_header, text="Clear", width=52, height=22, corner_radius=6,
            fg_color="transparent", hover_color=theme.CARD_HOVER,
            text_color=theme.TEXT_DIM, font=(theme.FONT, 12),
            command=self._clear_route,
        ).grid(row=0, column=1, sticky="e")

        self._route_frame = ctk.CTkScrollableFrame(
            panel, fg_color="transparent", scrollbar_button_color=theme.BORDER,
            scrollbar_button_hover_color=theme.TEXT_FAINT,
        )
        self._route_frame.grid(row=6, column=0, sticky="nsew", padx=8, pady=(6, 0))

        gpx_row = ctk.CTkFrame(panel, fg_color="transparent")
        gpx_row.grid(row=7, column=0, sticky="ew", padx=14, pady=14)
        gpx_row.grid_columnconfigure((0, 1), weight=1)
        for column, (text, command) in enumerate(
            (("Import GPX", self._import_gpx), ("Export", self._export_gpx))
        ):
            ctk.CTkButton(
                gpx_row, text=text, height=30, corner_radius=theme.CORNER,
                fg_color=theme.CARD, hover_color=theme.CARD_HOVER,
                border_width=1, border_color=theme.BORDER,
                text_color=theme.TEXT_DIM, font=(theme.FONT, 12), command=command,
            ).grid(row=0, column=column, sticky="ew", padx=(0, 6) if column == 0 else (6, 0))

    def _build_map(self) -> None:
        container = ctk.CTkFrame(self, corner_radius=0, fg_color=theme.BG)
        container.grid(row=1, column=1, sticky="nsew")
        container.grid_rowconfigure(1, weight=1)
        container.grid_columnconfigure(0, weight=1)

        search = ctk.CTkFrame(container, height=52, corner_radius=0, fg_color=theme.PANEL)
        search.grid(row=0, column=0, sticky="ew")
        search.grid_propagate(False)
        search.grid_columnconfigure(0, weight=1)

        self._search_entry = ctk.CTkEntry(
            search, placeholder_text="Enter coordinates, e.g. 47.4979, 19.0402",
            height=32, corner_radius=theme.CORNER, fg_color=theme.CARD,
            border_color=theme.BORDER, text_color=theme.TEXT, font=(theme.FONT, 13),
        )
        self._search_entry.grid(row=0, column=0, sticky="ew", padx=(14, 8), pady=10)
        self._search_entry.bind("<Return>", lambda _e: self._apply_search())

        ctk.CTkButton(
            search, text="Go", width=60, height=32, corner_radius=theme.CORNER,
            fg_color=theme.CARD, hover_color=theme.CARD_HOVER,
            border_width=1, border_color=theme.BORDER,
            text_color=theme.TEXT, font=(theme.FONT, 13), command=self._apply_search,
        ).grid(row=0, column=1, padx=(0, 14), pady=10)

        self._map = TkinterMapView(container, corner_radius=0)
        self._map.grid(row=1, column=0, sticky="nsew")
        self._map.set_tile_server(theme.TILE_SERVER, max_zoom=theme.TILE_MAX_ZOOM)
        self._map.set_position(self._selected.latitude, self._selected.longitude)
        self._map.set_zoom(12)
        self._map.add_left_click_map_command(self._on_map_clicked)
        self._map.add_right_click_menu_command(
            label="Set location here", command=self._on_map_right_click, pass_coords=True
        )
        self._map.add_right_click_menu_command(
            label="Add waypoint here", command=self._on_map_add_waypoint, pass_coords=True
        )

        ctk.CTkLabel(
            container, text=theme.ATTRIBUTION, font=(theme.FONT, 9),
            text_color=theme.TEXT_FAINT, fg_color=theme.PANEL, corner_radius=4,
        ).place(relx=1.0, rely=1.0, anchor="se", x=-8, y=-8)

    def _build_inspector(self) -> None:
        panel = ctk.CTkFrame(self, width=INSPECTOR_WIDTH, corner_radius=0, fg_color=theme.PANEL)
        panel.grid(row=1, column=2, sticky="nse")
        panel.grid_propagate(False)
        panel.grid_columnconfigure(0, weight=1)

        ctk.CTkLabel(
            panel, text="Location", font=(theme.FONT, 19, "bold"),
            text_color=theme.TEXT, anchor="w",
        ).grid(row=0, column=0, sticky="ew", padx=16, pady=(16, 0))
        ctk.CTkLabel(
            panel, text="Set a static point or build a timed route.",
            font=(theme.FONT, 12), text_color=theme.TEXT_DIM, anchor="w",
            wraplength=250, justify="left",
        ).grid(row=1, column=0, sticky="ew", padx=16, pady=(2, 14))

        section_label(panel, "Coordinates").grid(row=2, column=0, sticky="ew", padx=16)

        fields = ctk.CTkFrame(panel, fg_color="transparent")
        fields.grid(row=3, column=0, sticky="ew", padx=16, pady=(6, 14))
        fields.grid_columnconfigure(1, weight=1)

        def field_label(text: str, row: int) -> None:
            ctk.CTkLabel(
                fields, text=text, width=34, anchor="w",
                font=(theme.FONT, 11), text_color=theme.TEXT_FAINT,
            ).grid(row=row, column=0, sticky="w", pady=(0, 6))

        field_label("Lat", 0)
        self._lat_entry = self._coordinate_entry(fields, "Latitude")
        self._lat_entry.grid(row=0, column=1, sticky="ew", pady=(0, 6))

        field_label("Lon", 1)
        self._lon_entry = self._coordinate_entry(fields, "Longitude")
        self._lon_entry.grid(row=1, column=1, sticky="ew", pady=(0, 6))

        field_label("Name", 2)
        self._label_entry = self._coordinate_entry(fields, "Label")
        self._label_entry.grid(row=2, column=1, sticky="ew")

        for entry in (self._lat_entry, self._lon_entry):
            entry.bind("<Return>", lambda _e: self._apply_coordinate_fields())
            entry.bind("<FocusOut>", lambda _e: self._apply_coordinate_fields())
        self._label_entry.bind("<KeyRelease>", lambda _e: self._apply_label_field())

        section_label(panel, "Route Playback").grid(row=4, column=0, sticky="ew", padx=16)

        speed_row = ctk.CTkFrame(panel, fg_color="transparent")
        speed_row.grid(row=5, column=0, sticky="ew", padx=16, pady=(6, 0))
        speed_row.grid_columnconfigure(0, weight=1)
        self._speed_label = ctk.CTkLabel(
            speed_row, text="Driving", font=(theme.FONT, 13), text_color=theme.TEXT, anchor="w"
        )
        self._speed_label.grid(row=0, column=0, sticky="w")
        self._speed_value = ctk.CTkLabel(
            speed_row, text=f"{DEFAULT_SPEED_KMH} km/h", font=(theme.FONT_MONO, 12),
            text_color=theme.TEXT_DIM, anchor="e",
        )
        self._speed_value.grid(row=0, column=1, sticky="e")

        self._speed_slider = ctk.CTkSlider(
            panel, from_=MIN_SPEED_KMH, to=MAX_SPEED_KMH,
            number_of_steps=MAX_SPEED_KMH - MIN_SPEED_KMH,
            button_color=theme.ACCENT, button_hover_color=theme.ACCENT_HOVER,
            progress_color=theme.ACCENT, fg_color=theme.CARD,
            command=self._on_speed_changed,
        )
        self._speed_slider.set(DEFAULT_SPEED_KMH)
        self._speed_slider.grid(row=6, column=0, sticky="ew", padx=16, pady=(8, 12))

        buttons = ctk.CTkFrame(panel, fg_color="transparent")
        buttons.grid(row=7, column=0, sticky="ew", padx=16)
        buttons.grid_columnconfigure((0, 1), weight=1)
        ctk.CTkButton(
            buttons, text="Add Point", height=32, corner_radius=theme.CORNER,
            fg_color=theme.CARD, hover_color=theme.CARD_HOVER,
            border_width=1, border_color=theme.BORDER,
            text_color=theme.TEXT, font=(theme.FONT, 12),
            command=self._add_selected_to_route,
        ).grid(row=0, column=0, sticky="ew", padx=(0, 5))
        self._play_button = ctk.CTkButton(
            buttons, text="Play Route", height=32, corner_radius=theme.CORNER,
            fg_color=theme.ACCENT, hover_color=theme.ACCENT_HOVER,
            text_color="#ffffff", font=(theme.FONT, 12, "bold"),
            command=self._play_route,
        )
        self._play_button.grid(row=0, column=1, sticky="ew", padx=(5, 0))

        section_label(panel, "Target Readiness").grid(
            row=8, column=0, sticky="ew", padx=16, pady=(18, 0)
        )
        self._readiness_frame = ctk.CTkFrame(
            panel, fg_color=theme.CARD, corner_radius=theme.CORNER
        )
        self._readiness_frame.grid(row=9, column=0, sticky="ew", padx=16, pady=(6, 0))

    def _coordinate_entry(self, parent, placeholder: str) -> ctk.CTkEntry:
        return ctk.CTkEntry(
            parent, placeholder_text=placeholder, height=32,
            corner_radius=theme.CORNER, fg_color=theme.CARD,
            border_color=theme.BORDER, text_color=theme.TEXT,
            font=(theme.FONT_MONO, 12),
        )

    def _build_statusbar(self) -> None:
        bar = ctk.CTkFrame(self, height=30, corner_radius=0, fg_color=theme.PANEL)
        bar.grid(row=2, column=0, columnspan=3, sticky="ew")
        bar.grid_propagate(False)
        bar.grid_columnconfigure(1, weight=1)

        self._status_dot = ctk.CTkLabel(
            bar, text="●", font=(theme.FONT, 12), text_color=theme.TEXT_FAINT, width=14
        )
        self._status_dot.grid(row=0, column=0, padx=(14, 4))

        self._status_label = ctk.CTkLabel(
            bar, text="Ready", font=(theme.FONT, 11), text_color=theme.TEXT_DIM, anchor="w"
        )
        self._status_label.grid(row=0, column=1, sticky="w")

        self._coordinate_label = ctk.CTkLabel(
            bar, text="", font=(theme.FONT_MONO, 11), text_color=theme.TEXT_FAINT, anchor="e"
        )
        self._coordinate_label.grid(row=0, column=2, padx=(0, 14), sticky="e")

    # ------------------------------------------------------------- devices

    def refresh_devices(self) -> None:
        self._refresh_button.configure(state="disabled")
        self._set_status("Looking for devices…")
        self._worker.submit(
            device_service.list_devices(),
            on_success=self._on_devices,
            on_error=self._on_device_error,
        )

    def _on_devices(self, found: list[DeviceTarget]) -> None:
        self._refresh_button.configure(state="normal")
        previous = self.current_device()
        self._devices = found

        if found:
            labels = [d.name for d in found]
            self._device_menu.configure(values=labels, state="normal")
            keep = previous.name if previous and any(d.name == previous.name for d in found) else labels[0]
            self._device_menu.set(keep)
            device = self.current_device()
            self._device_label.configure(text=device.detail if device else "")
            self._set_status(f"{len(found)} device{'s' if len(found) != 1 else ''} available")
        else:
            self._device_menu.configure(values=["No devices"], state="disabled")
            self._device_menu.set("No devices")
            self._device_label.configure(
                text="No iPhone detected. Connect one by cable, then press Refresh."
            )
            self._set_status("No devices detected")

        self._update_controls()

    def _on_device_error(self, exc: Exception) -> None:
        self._refresh_button.configure(state="normal")
        log.warning("device discovery failed: %s", exc)
        self._device_label.configure(
            text="Could not reach Apple Mobile Device Service. Install the Apple Devices "
            "app or iTunes, then press Refresh."
        )
        self._set_status("usbmux unavailable", error=True)
        self._update_controls()

    def _on_device_selected(self, _name: str) -> None:
        device = self.current_device()
        if device is not None:
            self._device_label.configure(text=device.detail)
        self._update_controls()

    def current_device(self) -> Optional[DeviceTarget]:
        name = self._device_menu.get()
        return next((d for d in self._devices if d.name == name), None)

    # ------------------------------------------------------------ selection

    def _sync_selection(self, center: bool = False) -> None:
        self._suppress_field_sync = True
        for entry, value in (
            (self._lat_entry, f"{self._selected.latitude:.6f}"),
            (self._lon_entry, f"{self._selected.longitude:.6f}"),
            (self._label_entry, self._selected.name),
        ):
            entry.delete(0, "end")
            entry.insert(0, value)
        self._suppress_field_sync = False

        if self._pin_marker is not None:
            self._pin_marker.delete()
        self._pin_marker = self._map.set_marker(
            self._selected.latitude,
            self._selected.longitude,
            text=self._selected.name or "Selected",
            marker_color_circle=theme.VIOLET,
            marker_color_outside=theme.ACCENT,
            text_color=theme.TEXT,
            font=(theme.FONT, 11, "bold"),
        )

        if center:
            self._map.set_position(self._selected.latitude, self._selected.longitude)

        self._coordinate_label.configure(text=self._selected.coordinate_label)
        self._update_controls()

    def _on_map_clicked(self, coords) -> None:
        latitude, longitude = coords
        self._selected = LocationPoint(name="Dropped Pin", latitude=latitude, longitude=longitude)
        self._sync_selection()
        self._set_status("Location selected")

    def _on_map_right_click(self, coords) -> None:
        self._on_map_clicked(coords)

    def _on_map_add_waypoint(self, coords) -> None:
        latitude, longitude = coords
        self._append_route_point(
            LocationPoint(name=f"Waypoint {len(self._route) + 1}",
                          latitude=latitude, longitude=longitude)
        )

    def _apply_coordinate_fields(self) -> None:
        if self._suppress_field_sync:
            return
        try:
            latitude = float(self._lat_entry.get().strip())
            longitude = float(self._lon_entry.get().strip())
        except ValueError:
            self._set_status("Coordinates must be numbers", error=True)
            return

        candidate = LocationPoint(
            name=self._label_entry.get().strip(), latitude=latitude, longitude=longitude
        )
        if not candidate.is_valid:
            self._set_status("Latitude must be −90..90 and longitude −180..180", error=True)
            return

        self._selected = candidate
        self._sync_selection()

    def _apply_label_field(self) -> None:
        if not self._suppress_field_sync:
            self._selected.name = self._label_entry.get()

    def _apply_search(self) -> None:
        text = self._search_entry.get().strip().replace(";", ",")
        if not text:
            return
        parts = [p for p in text.replace(",", " ").split() if p]
        if len(parts) != 2:
            self._set_status("Enter coordinates as 'latitude, longitude'", error=True)
            return
        try:
            latitude, longitude = float(parts[0]), float(parts[1])
        except ValueError:
            self._set_status("Could not read those coordinates", error=True)
            return

        candidate = LocationPoint(name="Searched", latitude=latitude, longitude=longitude)
        if not candidate.is_valid:
            self._set_status("Latitude must be −90..90 and longitude −180..180", error=True)
            return

        self._selected = candidate
        self._sync_selection(center=True)
        self._search_entry.delete(0, "end")
        self._set_status("Location selected")

    # --------------------------------------------------------------- places

    def _refresh_places(self) -> None:
        for child in self._places_frame.winfo_children():
            child.destroy()

        if not self._places:
            ctk.CTkLabel(
                self._places_frame, text="Save a location from the map to keep it here.",
                font=(theme.FONT, 11), text_color=theme.TEXT_FAINT,
                wraplength=210, justify="left", anchor="w",
            ).pack(fill="x", padx=6, pady=6)
            return

        for place in self._places:
            self._place_row(place)

    def _place_row(self, place: SavedPlace) -> None:
        row = ctk.CTkFrame(self._places_frame, fg_color=theme.CARD, corner_radius=theme.CORNER)
        row.pack(fill="x", pady=2, padx=2)

        name = ctk.CTkLabel(
            row, text=place.name, font=(theme.FONT, 12, "bold"),
            text_color=theme.TEXT, anchor="w",
        )
        name.pack(fill="x", padx=10, pady=(7, 0))
        coords = ctk.CTkLabel(
            row, text=place.point.coordinate_label, font=(theme.FONT_MONO, 10),
            text_color=theme.TEXT_FAINT, anchor="w",
        )
        coords.pack(fill="x", padx=10, pady=(0, 7))

        def on_click(_event=None, place=place) -> None:
            self._selected = LocationPoint(
                name=place.name,
                latitude=place.point.latitude,
                longitude=place.point.longitude,
            )
            self._sync_selection(center=True)

        def on_menu(event, place=place) -> None:
            self._show_place_menu(event, place)

        def on_enter(_event=None, row=row) -> None:
            row.configure(fg_color=theme.CARD_HOVER)

        def on_leave(_event=None, row=row) -> None:
            row.configure(fg_color=theme.CARD)

        for widget in (row, name, coords):
            widget.bind("<Button-1>", on_click)
            widget.bind("<Button-2>", on_menu)
            widget.bind("<Button-3>", on_menu)
            widget.bind("<Enter>", on_enter)
            widget.bind("<Leave>", on_leave)

    def _show_place_menu(self, event, place: SavedPlace) -> None:
        menu = tk.Menu(self, tearoff=0, bg=theme.CARD, fg=theme.TEXT,
                       activebackground=theme.ACCENT, activeforeground="#ffffff",
                       bd=0, relief="flat")
        menu.add_command(
            label="Use This Location",
            command=lambda: (
                setattr(self, "_selected", LocationPoint(
                    name=place.name,
                    latitude=place.point.latitude,
                    longitude=place.point.longitude)),
                self._sync_selection(center=True),
            ),
        )
        menu.add_command(
            label="Add to Route",
            command=lambda: self._append_route_point(place.point, place.name),
        )
        menu.add_separator()
        menu.add_command(label="Rename…", command=lambda: self._rename_place(place))
        menu.add_separator()
        menu.add_command(label="Delete", command=lambda: self._delete_place(place))
        try:
            menu.tk_popup(event.x_root, event.y_root)
        finally:
            menu.grab_release()

    def _save_selected_place(self) -> None:
        if self._selected_is_saved():
            self._set_status("That place is already saved")
            return

        name = self._selected.name.strip() or self._selected.coordinate_label
        self._places.append(
            SavedPlace(
                name=name,
                point=LocationPoint(
                    name=name,
                    latitude=self._selected.latitude,
                    longitude=self._selected.longitude,
                ),
            )
        )
        places_store.save_places(self._places)
        self._refresh_places()
        self._set_status(f"Saved “{name}”")
        self._update_controls()

    def _selected_is_saved(self) -> bool:
        return any(
            abs(p.point.latitude - self._selected.latitude) < 1e-6
            and abs(p.point.longitude - self._selected.longitude) < 1e-6
            for p in self._places
        )

    def _rename_place(self, place: SavedPlace) -> None:
        dialog = ctk.CTkInputDialog(text=f"Rename “{place.name}” to:", title="Rename Place")
        new_name = dialog.get_input()
        if not new_name:
            return
        new_name = new_name.strip()
        if not new_name:
            return
        place.name = new_name
        place.point.name = new_name
        places_store.save_places(self._places)
        self._refresh_places()
        self._set_status(f"Renamed to “{new_name}”")

    def _delete_place(self, place: SavedPlace) -> None:
        self._places = [p for p in self._places if p.id != place.id]
        places_store.save_places(self._places)
        self._refresh_places()
        self._set_status(f"Removed “{place.name}”")
        self._update_controls()

    # ---------------------------------------------------------------- route

    def _refresh_route(self) -> None:
        for child in self._route_frame.winfo_children():
            child.destroy()

        if not self._route:
            ctk.CTkLabel(
                self._route_frame,
                text="Add waypoints from the map to build a timed route.",
                font=(theme.FONT, 11), text_color=theme.TEXT_FAINT,
                wraplength=210, justify="left", anchor="w",
            ).pack(fill="x", padx=6, pady=6)
        else:
            for index, point in enumerate(self._route, start=1):
                self._route_row(index, point)

        self._redraw_route_on_map()
        self._update_controls()

    def _route_row(self, index: int, point: LocationPoint) -> None:
        row = ctk.CTkFrame(self._route_frame, fg_color=theme.CARD, corner_radius=theme.CORNER)
        row.pack(fill="x", pady=2, padx=2)
        row.grid_columnconfigure(1, weight=1)

        ctk.CTkLabel(
            row, text=str(index), width=22, height=22, corner_radius=11,
            fg_color=theme.VIOLET, text_color="#ffffff", font=(theme.FONT, 10, "bold"),
        ).grid(row=0, column=0, rowspan=2, padx=(8, 8), pady=8)

        ctk.CTkLabel(
            row, text=point.name or "Waypoint", font=(theme.FONT, 12),
            text_color=theme.TEXT, anchor="w",
        ).grid(row=0, column=1, sticky="ew", pady=(7, 0))
        ctk.CTkLabel(
            row, text=point.coordinate_label, font=(theme.FONT_MONO, 10),
            text_color=theme.TEXT_FAINT, anchor="w",
        ).grid(row=1, column=1, sticky="ew", pady=(0, 7))

        ctk.CTkButton(
            row, text="✕", width=24, height=24, corner_radius=6,
            fg_color="transparent", hover_color=theme.RED,
            text_color=theme.TEXT_FAINT, font=(theme.FONT, 11),
            command=lambda i=index - 1: self._remove_route_point(i),
        ).grid(row=0, column=2, rowspan=2, padx=(0, 6))

    def _redraw_route_on_map(self) -> None:
        if self._route_path is not None:
            self._route_path.delete()
            self._route_path = None
        for marker in self._route_markers:
            marker.delete()
        self._route_markers = []

        for index, point in enumerate(self._route, start=1):
            self._route_markers.append(
                self._map.set_marker(
                    point.latitude, point.longitude, text=str(index),
                    marker_color_circle=theme.VIOLET,
                    marker_color_outside="#b06cff",
                    text_color=theme.TEXT, font=(theme.FONT, 10, "bold"),
                )
            )

        if len(self._route) >= 2:
            self._route_path = self._map.set_path(
                [(p.latitude, p.longitude) for p in self._route],
                color="#b06cff", width=4,
            )

    def _append_route_point(self, point: LocationPoint, name: str = "") -> None:
        self._route.append(
            LocationPoint(
                name=name or point.name or f"Waypoint {len(self._route) + 1}",
                latitude=point.latitude,
                longitude=point.longitude,
            )
        )
        self._refresh_route()
        self._set_status(f"Waypoint {len(self._route)} added")

    def _add_selected_to_route(self) -> None:
        self._append_route_point(self._selected)

    def _remove_route_point(self, index: int) -> None:
        if 0 <= index < len(self._route):
            self._route.pop(index)
            self._refresh_route()

    def _clear_route(self) -> None:
        if not self._route:
            return
        self._route.clear()
        self._clear_live_marker()
        self._refresh_route()
        self._set_status("Route cleared")

    def _import_gpx(self) -> None:
        path = filedialog.askopenfilename(
            title="Import GPX", filetypes=[("GPX files", "*.gpx"), ("All files", "*.*")]
        )
        if not path:
            return
        try:
            with open(path, "rb") as handle:
                self._route = gpx.decode(handle.read())
        except (OSError, RelocateError) as exc:
            messagebox.showwarning("Import failed", str(exc), parent=self)
            return

        if self._route:
            first = self._route[0]
            self._selected = LocationPoint(
                name=first.name, latitude=first.latitude, longitude=first.longitude
            )
            self._sync_selection(center=True)
        self._refresh_route()
        self._set_status(f"Imported {len(self._route)} waypoints")

    def _export_gpx(self) -> None:
        if not self._route:
            self._set_status("Add waypoints before exporting", error=True)
            return
        path = filedialog.asksaveasfilename(
            title="Export GPX", defaultextension=".gpx",
            initialfile="Relocate Route.gpx", filetypes=[("GPX files", "*.gpx")],
        )
        if not path:
            return
        try:
            with open(path, "wb") as handle:
                handle.write(gpx.encode(self._route, self._speed_mps()))
        except OSError as exc:
            messagebox.showwarning("Export failed", str(exc), parent=self)
            return
        self._set_status("Route exported")

    # ------------------------------------------------------------ simulation

    def _speed_kmh(self) -> int:
        return int(round(self._speed_slider.get()))

    def _speed_mps(self) -> float:
        return self._speed_kmh() / 3.6

    def _on_speed_changed(self, _value: float) -> None:
        kmh = self._speed_kmh()
        self._speed_value.configure(text=f"{kmh} km/h")
        if kmh < 8:
            label = "Walking"
        elif kmh < 25:
            label = "Cycling"
        elif kmh < 80:
            label = "Driving"
        else:
            label = "High speed"
        self._speed_label.configure(text=label)

    def _on_primary_clicked(self) -> None:
        if self._state.is_running:
            self.stop_simulation()
        else:
            self.set_location()

    def set_location(self) -> None:
        device = self.current_device()
        if device is None:
            self._set_status("Select an available device first", error=True)
            return

        point = LocationPoint(
            name=self._selected.name,
            latitude=self._selected.latitude,
            longitude=self._selected.longitude,
        )
        self._set_state(SimulationState.PREPARING)
        self._set_status("Opening developer tunnel…")
        self._clear_live_marker()

        self._worker.submit(
            self._engine.set_location(device.udid, point, on_finished=self._on_session_ended),
            on_success=lambda _r: self._on_holding(point, device),
            on_error=self._on_simulation_error,
        )

    def _on_holding(self, point: LocationPoint, device: DeviceTarget) -> None:
        self._set_state(SimulationState.ACTIVE)
        self._set_status(
            f"Simulating {point.name or point.coordinate_label} on {device.name}"
        )

    def _play_route(self) -> None:
        device = self.current_device()
        if device is None:
            self._set_status("Select an available device first", error=True)
            return
        if len(self._route) < 2:
            self._set_status("A route needs at least two waypoints", error=True)
            return

        self._set_state(SimulationState.PREPARING)
        self._set_status(f"Preparing {len(self._route)}-point route…")

        self._worker.submit(
            self._engine.play_route(
                device.udid,
                list(self._route),
                self._speed_mps(),
                on_progress=self._on_route_progress,
                on_finished=self._on_route_finished,
            ),
            on_success=lambda _r: self._on_route_started(device),
            on_error=self._on_simulation_error,
        )

    def _on_route_started(self, device: DeviceTarget) -> None:
        self._set_state(SimulationState.PLAYING)
        self._set_status(f"Route playing on {device.name}")

    def _on_route_progress(self, fraction: float, point: LocationPoint) -> None:
        # Called from the asyncio thread; hop to the GUI thread before touching widgets.
        def apply() -> None:
            self._show_live_marker(point.latitude, point.longitude)
            if self._state is SimulationState.PLAYING:
                self._status_label.configure(
                    text=f"Route playing — {int(fraction * 100)}%"
                )

        self._worker.post_to_gui(apply)

    def _on_route_finished(self, error: Optional[str]) -> None:
        def apply() -> None:
            if error is None:
                self._set_state(SimulationState.ACTIVE)
                destination = self._route[-1].name if self._route else "final position"
                self._set_status(f"Route finished — holding {destination}")
            else:
                self._set_state(SimulationState.FAILED)
                self._set_status(error, error=True)

        self._worker.post_to_gui(apply)

    def _on_session_ended(self, error: Optional[str]) -> None:
        if error is None:
            return

        def apply() -> None:
            self._set_state(SimulationState.FAILED)
            self._clear_live_marker()
            self._set_status(error, error=True)

        self._worker.post_to_gui(apply)

    def stop_simulation(self) -> None:
        self._set_state(SimulationState.STOPPING)
        self._set_status("Restoring real location…")
        self._worker.submit(
            self._engine.stop(),
            on_success=lambda _r: self._on_stopped(),
            on_error=self._on_simulation_error,
        )

    def _on_stopped(self) -> None:
        self._set_state(SimulationState.IDLE)
        self._clear_live_marker()
        self._set_status("Real location restored")

    def _on_simulation_error(self, exc: Exception) -> None:
        self._set_state(SimulationState.FAILED)
        self._clear_live_marker()
        self._set_status(str(exc), error=True)

    def _show_live_marker(self, latitude: float, longitude: float) -> None:
        self._clear_live_marker()
        self._live_marker = self._map.set_marker(
            latitude, longitude, text="",
            marker_color_circle="#ffffff", marker_color_outside=theme.BLUE,
        )

    def _clear_live_marker(self) -> None:
        if self._live_marker is not None:
            self._live_marker.delete()
            self._live_marker = None

    # ------------------------------------------------------------------ misc

    def show_tutorial(self) -> None:
        TutorialDialog(self)

    def _set_state(self, state: SimulationState) -> None:
        self._state = state
        self._update_controls()

    def _set_status(self, message: str, error: bool = False) -> None:
        self._status_label.configure(
            text=message, text_color=theme.RED if error else theme.TEXT_DIM
        )
        if error:
            colour = theme.RED
        elif self._state in (SimulationState.ACTIVE, SimulationState.PLAYING):
            colour = theme.GREEN
        elif self._state.is_running:
            colour = "#f0a020"
        else:
            colour = theme.TEXT_FAINT
        self._status_dot.configure(text_color=colour)

    def _update_controls(self) -> None:
        device = self.current_device()
        ready = device is not None and device.is_available
        running = self._state.is_running

        # A disabled CustomTkinter button keeps its fill, so an accent-coloured button
        # just looks washed out. Drop it to the card colour instead.
        def set_action(button, *, text: str, enabled: bool, accent: str, hover: str) -> None:
            button.configure(
                text=text,
                state="normal" if enabled else "disabled",
                fg_color=accent if enabled else theme.CARD,
                hover_color=hover,
                text_color="#ffffff",
                text_color_disabled=theme.TEXT_FAINT,
            )

        if running:
            set_action(
                self._primary_button, text="Stop",
                enabled=self._state is not SimulationState.STOPPING,
                accent=theme.RED, hover=theme.RED_HOVER,
            )
        else:
            set_action(
                self._primary_button, text="Set Location",
                enabled=ready and self._selected.is_valid,
                accent=theme.ACCENT, hover=theme.ACCENT_HOVER,
            )

        set_action(
            self._play_button, text="Play Route",
            enabled=ready and len(self._route) >= 2 and not running,
            accent=theme.ACCENT, hover=theme.ACCENT_HOVER,
        )
        self._add_place_button.configure(
            state="disabled" if self._selected_is_saved() else "normal"
        )

        for child in self._readiness_frame.winfo_children():
            child.destroy()

        rows = (
            (bool(self._devices), "Apple device service",
             "Reachable" if self._devices else "No devices via usbmux"),
            (ready, "Device selected", device.name if device else "Choose a target"),
            (len(self._route) >= 2, "Route ready",
             f"{len(self._route)} waypoints" if self._route else "Add two or more waypoints"),
        )
        for ok, title, detail in rows:
            row = ctk.CTkFrame(self._readiness_frame, fg_color="transparent")
            row.pack(fill="x", padx=10, pady=5)
            ctk.CTkLabel(
                row, text="✓" if ok else "○", width=16,
                text_color=theme.GREEN if ok else theme.TEXT_FAINT,
                font=(theme.FONT, 12, "bold"),
            ).pack(side="left", anchor="n")
            column = ctk.CTkFrame(row, fg_color="transparent")
            column.pack(side="left", fill="x", expand=True)
            ctk.CTkLabel(
                column, text=title, font=(theme.FONT, 12),
                text_color=theme.TEXT, anchor="w",
            ).pack(fill="x")
            ctk.CTkLabel(
                column, text=detail, font=(theme.FONT, 10),
                text_color=theme.TEXT_FAINT, anchor="w",
            ).pack(fill="x")

    def _on_close(self) -> None:
        """Restore the device's real location before quitting."""
        if self._state.is_running:
            self._set_status("Restoring real location…")
            self.update_idletasks()
            self._worker.run_blocking(self._engine.stop(), timeout=8.0)

        self._worker.shutdown()
        self.destroy()
