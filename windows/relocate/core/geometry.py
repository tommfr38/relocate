"""Great-circle helpers used to pace and smooth route playback.

Ported from the macOS app's RouteGeometry.swift, including the fixes made there:
routes must be interpolated (playback teleports between whatever points it is
given), and a static location must be re-asserted on a short interval or iOS
overrides it with a real GPS fix after a few seconds.
"""

from __future__ import annotations

import math
import time
from typing import Optional, Sequence

from .models import LocationPoint

EARTH_RADIUS = 6_371_000.0

# Upper bound on generated track points, so a long route at a slow speed cannot
# produce an unbounded playback schedule.
MAX_SAMPLES = 20_000

# Cadence for re-asserting a held position. iOS overrides a one-shot simulated fix
# with the next real GPS fix after roughly 5-10 seconds, so the coordinate has to be
# repeated well inside that window.
HOLD_INTERVAL = 2.0


def distance(start: LocationPoint, end: LocationPoint) -> float:
    """Metres between two coordinates along the surface of the earth."""
    lat1 = math.radians(start.latitude)
    lat2 = math.radians(end.latitude)
    delta_lat = lat2 - lat1
    delta_lon = math.radians(end.longitude - start.longitude)

    a = math.sin(delta_lat / 2) ** 2 + math.cos(lat1) * math.cos(lat2) * math.sin(delta_lon / 2) ** 2
    return 2 * EARTH_RADIUS * math.asin(min(1.0, math.sqrt(a)))


def interpolate(start: LocationPoint, end: LocationPoint, fraction: float) -> tuple[float, float]:
    """Spherical interpolation between two coordinates; `fraction` is clamped to 0..1.

    Linear interpolation of latitude/longitude drifts badly over long legs, so this
    walks the actual great-circle arc instead.
    """
    t = min(max(fraction, 0.0), 1.0)

    lat1 = math.radians(start.latitude)
    lon1 = math.radians(start.longitude)
    lat2 = math.radians(end.latitude)
    lon2 = math.radians(end.longitude)

    delta_lat = lat2 - lat1
    delta_lon = lon2 - lon1
    haversine = math.sin(delta_lat / 2) ** 2 + math.cos(lat1) * math.cos(lat2) * math.sin(delta_lon / 2) ** 2
    angle = 2 * math.asin(min(1.0, math.sqrt(haversine)))

    # Coincident (or effectively coincident) points: nothing to interpolate.
    if angle <= 1e-12:
        return (start.latitude, start.longitude)

    a = math.sin((1 - t) * angle) / math.sin(angle)
    b = math.sin(t * angle) / math.sin(angle)

    x = a * math.cos(lat1) * math.cos(lon1) + b * math.cos(lat2) * math.cos(lon2)
    y = a * math.cos(lat1) * math.sin(lon1) + b * math.cos(lat2) * math.sin(lon2)
    z = a * math.sin(lat1) + b * math.sin(lat2)

    return (
        math.degrees(math.atan2(z, math.sqrt(x * x + y * y))),
        math.degrees(math.atan2(y, x)),
    )


def total_duration(points: Sequence[LocationPoint], speed_mps: float) -> float:
    """How long a route takes to play at the given speed, in seconds."""
    if len(points) < 2:
        return 0.0
    total = sum(distance(a, b) for a, b in zip(points, points[1:]))
    return total / max(speed_mps, 0.1)


def coordinate_along(points: Sequence[LocationPoint], fraction: float) -> Optional[tuple[float, float]]:
    """The coordinate at a fraction (0..1) of the total distance along a multi-leg route."""
    if not points:
        return None
    if len(points) == 1:
        return (points[0].latitude, points[0].longitude)

    t = min(max(fraction, 0.0), 1.0)
    legs = list(zip(points, points[1:]))
    total = sum(distance(a, b) for a, b in legs)
    if total <= 0:
        return (points[0].latitude, points[0].longitude)

    target = t * total
    travelled = 0.0
    for origin, dest in legs:
        leg = distance(origin, dest)
        if travelled + leg >= target:
            within = (target - travelled) / leg if leg > 0 else 0.0
            return interpolate(origin, dest, within)
        travelled += leg

    return (points[-1].latitude, points[-1].longitude)


def densify(
    points: Sequence[LocationPoint],
    speed_mps: float,
    sample_interval: float = 1.0,
    start_time: Optional[float] = None,
) -> list[LocationPoint]:
    """Expand sparse waypoints into a dense, evenly timed track.

    Playback moves the device to each point in turn, so a two-waypoint route would
    jump straight to the destination. Sampling each leg at a fixed cadence makes the
    device travel the route at the requested speed instead.

    Timestamps are epoch seconds and are strictly non-decreasing.
    """
    start = time.time() if start_time is None else start_time

    if len(points) < 2:
        return [
            LocationPoint(
                name=p.name,
                latitude=p.latitude,
                longitude=p.longitude,
                timestamp=start + index,
            )
            for index, p in enumerate(points)
        ]

    speed = max(speed_mps, 0.1)
    interval = max(sample_interval, 0.1)

    legs = list(zip(points, points[1:]))
    total_distance = sum(distance(a, b) for a, b in legs)
    duration = total_distance / speed

    # Stretch the cadence if the route would otherwise blow past the sample cap.
    # Rounding up within each leg can add one extra sample per leg, so the budget
    # reserves headroom for that plus the initial point.
    projected = int(math.ceil(duration / interval)) + len(points)
    if projected > MAX_SAMPLES:
        budget = max(1, MAX_SAMPLES - len(points) - 1)
        step = duration / budget
    else:
        step = interval

    result: list[LocationPoint] = [
        LocationPoint(
            name=points[0].name,
            latitude=points[0].latitude,
            longitude=points[0].longitude,
            timestamp=start,
        )
    ]

    elapsed = 0.0
    for origin, dest in legs:
        leg_distance = distance(origin, dest)
        leg_duration = leg_distance / speed

        # Zero-length leg: emit the destination so the waypoint is not lost.
        if leg_duration <= step:
            elapsed += max(leg_duration, step)
            result.append(
                LocationPoint(
                    name=dest.name,
                    latitude=dest.latitude,
                    longitude=dest.longitude,
                    timestamp=start + elapsed,
                )
            )
            continue

        sample_count = int(math.ceil(leg_duration / step))
        for sample in range(1, sample_count + 1):
            fraction = min(sample * step / leg_duration, 1.0)
            lat, lon = interpolate(origin, dest, fraction)
            is_final = sample == sample_count
            result.append(
                LocationPoint(
                    name=dest.name if is_final else "",
                    latitude=lat,
                    longitude=lon,
                    timestamp=start + elapsed + min(sample * step, leg_duration),
                )
            )
        elapsed += leg_duration

    return result
