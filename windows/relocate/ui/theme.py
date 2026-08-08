"""Palette shared by the CustomTkinter widgets.

Mirrors the macOS build's colours. CustomTkinter has no gradient fill, so the accent
is the midpoint of the app icon's blue-to-violet gradient.
"""

BG = "#0a0d16"
PANEL = "#10141f"
CARD = "#141826"
CARD_HOVER = "#1b2133"
BORDER = "#232a3d"

TEXT = "#eef0f6"
TEXT_DIM = "#a7adc0"
TEXT_FAINT = "#6b7186"

ACCENT = "#5a5cf2"
ACCENT_HOVER = "#6b6df5"
BLUE = "#4e8bff"
VIOLET = "#7a3ce8"
GREEN = "#3ddc84"
RED = "#e0443e"
RED_HOVER = "#f05049"

# tkintermapview takes a plain tile-URL template.
#
# Esri's Dark Gray Canvas is a true mid-dark basemap: it sits against this chrome
# without disappearing into it. Note the {z}/{y}/{x} ordering — Esri differs from the
# usual {z}/{x}/{y}. Alternatives, if this ever needs swapping:
#   CARTO dark   https://a.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png   (near-black)
#   OSM standard https://tile.openstreetmap.org/{z}/{x}/{y}.png             (light only)
TILE_SERVER = (
    "https://server.arcgisonline.com/ArcGIS/rest/services/"
    "Canvas/World_Dark_Gray_Base/MapServer/tile/{z}/{y}/{x}"
)
TILE_MAX_ZOOM = 16
ATTRIBUTION = "Esri, HERE, Garmin, © OpenStreetMap contributors"

FONT = "Segoe UI"          # falls back automatically off Windows
FONT_MONO = "Consolas"

CORNER = 8
CORNER_LG = 12
