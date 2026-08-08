"""GPX import/export.

Ported from the macOS app's GPXCodec.swift. Routes are written as a GPX **track**
(`<trk><trkseg><trkpt>`), not as top-level `<wpt>` elements: playback consumers —
including `pymobiledevice3`'s own `simulate-location play`, which walks
`gpx.tracks -> segments -> points` — ignore `<wpt>` entirely, so a waypoint-only
file parses cleanly but plays nothing.
"""

from __future__ import annotations

import time
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from typing import Optional, Sequence

from . import geometry
from .models import LocationPoint, MalformedGPXError

_GPX_NS = "http://www.topografix.com/GPX/1/1"


def _iso(epoch: float) -> str:
    return datetime.fromtimestamp(epoch, tz=timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _escape(value: str) -> str:
    return (
        value.replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace('"', "&quot;")
    )


def _timed_points(
    points: Sequence[LocationPoint], speed_mps: float, start: float
) -> list[LocationPoint]:
    """Space timestamps by real distance so the requested speed governs playback."""
    speed = max(speed_mps, 0.5)
    elapsed = 0.0
    result: list[LocationPoint] = []

    for index, point in enumerate(points):
        if index > 0:
            elapsed += max(0.2, geometry.distance(points[index - 1], point) / speed)
        result.append(
            LocationPoint(
                name=point.name,
                latitude=point.latitude,
                longitude=point.longitude,
                timestamp=point.timestamp if point.timestamp is not None else start + elapsed,
            )
        )
    return result


def encode(
    points: Sequence[LocationPoint],
    speed_mps: float = 12.0,
    densify: bool = False,
    start_time: Optional[float] = None,
) -> bytes:
    """Encode points as a GPX track document."""
    start = time.time() if start_time is None else start_time

    if densify:
        track = geometry.densify(points, speed_mps, start_time=start)
    else:
        track = _timed_points(points, speed_mps, start)

    body = []
    for point in track:
        name = f"\n        <name>{_escape(point.name)}</name>" if point.name else ""
        stamp = _iso(point.timestamp if point.timestamp is not None else start)
        body.append(
            f'      <trkpt lat="{point.latitude}" lon="{point.longitude}">{name}\n'
            f"        <time>{stamp}</time>\n"
            f"      </trkpt>"
        )

    joined = "\n".join(body)
    document = (
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        f'<gpx version="1.1" creator="Relocate" xmlns="{_GPX_NS}">\n'
        "  <trk>\n"
        "    <name>Relocate Route</name>\n"
        "    <trkseg>\n"
        f"{joined}\n"
        "    </trkseg>\n"
        "  </trk>\n"
        "</gpx>\n"
    )
    return document.encode("utf-8")


def _local_name(tag: str) -> str:
    return tag.rsplit("}", 1)[-1] if "}" in tag else tag


def decode(data: bytes) -> list[LocationPoint]:
    """Parse waypoints, route points, or track points out of a GPX document.

    Accepts all three element kinds on import so files from other tools work, even
    though Relocate always *writes* track points.
    """
    try:
        root = ET.fromstring(data)
    except ET.ParseError as exc:
        raise MalformedGPXError() from exc

    points: list[LocationPoint] = []
    for element in root.iter():
        if _local_name(element.tag) not in ("wpt", "trkpt", "rtept"):
            continue
        lat = element.get("lat")
        lon = element.get("lon")
        if lat is None or lon is None:
            continue
        try:
            latitude = float(lat)
            longitude = float(lon)
        except ValueError:
            continue

        name = ""
        for child in element:
            if _local_name(child.tag) == "name" and child.text:
                name = child.text.strip()
                break

        points.append(
            LocationPoint(
                name=name or f"Waypoint {len(points) + 1}",
                latitude=latitude,
                longitude=longitude,
            )
        )

    if not points:
        raise MalformedGPXError()
    return points
