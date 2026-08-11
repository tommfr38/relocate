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
# CARTO Dark Matter, requested at @2x. Two reasons over Esri's Dark Gray Canvas, which
# this replaced:
#
#   Detail.  Esri's tiling scheme stops at z16 — past that it answers 200 with a ~2 KB
#            blank, so zooming in simply dissolved the map. CARTO carries real data to
#            z20, which is what picking a coordinate on a street actually needs.
#   Sharpness. @2x tiles are 512 px for the same ground area, so they must be paired
#            with TILE_SIZE below. Everything renders at double density.
#
# Dark Matter is near-black (luminance ~14 against this chrome's ~13), so the map body
# is separated from the surrounding panels by MAP_BORDER rather than by tone.
# Alternatives, if this ever needs swapping:
#   Esri imagery  https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}
#   CARTO voyager https://a.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}@2x.png  (light)
TILE_SERVER = "https://a.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}@2x.png"
TILE_SIZE = 512            # must match the @2x tiles above; 256 would misalign the grid
TILE_MAX_ZOOM = 20
ATTRIBUTION = "© OpenStreetMap contributors, © CARTO"

FONT = "Segoe UI"          # falls back automatically off Windows
FONT_MONO = "Consolas"

CORNER = 8
CORNER_LG = 12

# The basemap is too near-black to delimit itself against PANEL/BG on its own.
MAP_BORDER = "#2b3348"
