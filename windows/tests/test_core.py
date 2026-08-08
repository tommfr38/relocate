"""Core logic tests, ported from the macOS app's GPXCodecTests.swift.

These cover the bugs that were found and fixed on macOS, so the Windows port cannot
silently regress them.
"""

from __future__ import annotations

import math

import pytest

from relocate.core import geometry, gpx
from relocate.core.models import LocationPoint, MalformedGPXError


def test_round_trip_preserves_coordinates_and_names():
    points = [
        LocationPoint(name="Start & Go", latitude=47.4979, longitude=19.0402),
        LocationPoint(name="Finish", latitude=48.2082, longitude=16.3738),
    ]

    decoded = gpx.decode(gpx.encode(points))

    assert len(decoded) == 2
    assert decoded[0].name == "Start & Go"
    assert decoded[0].latitude == pytest.approx(47.4979)
    assert decoded[1].longitude == pytest.approx(16.3738)


def test_encodes_route_as_track_points_not_waypoints():
    """pymobiledevice3 walks gpx.tracks -> segments -> points, so a route encoded as
    top-level <wpt> elements parses cleanly but plays nothing at all."""
    points = [
        LocationPoint(name="A", latitude=47.4979, longitude=19.0402),
        LocationPoint(name="B", latitude=47.5079, longitude=19.0502),
    ]

    document = gpx.encode(points).decode("utf-8")

    assert "<trk>" in document
    assert "<trkseg>" in document
    assert "<trkpt" in document
    assert "<wpt" not in document


def test_decode_still_accepts_waypoint_files_from_other_tools():
    document = b"""<?xml version="1.0" encoding="UTF-8"?>
    <gpx version="1.1" xmlns="http://www.topografix.com/GPX/1/1">
      <wpt lat="47.4979" lon="19.0402"><name>Start</name></wpt>
      <wpt lat="47.5079" lon="19.0502"><name>End</name></wpt>
    </gpx>"""

    decoded = gpx.decode(document)

    assert [p.name for p in decoded] == ["Start", "End"]


def test_rejects_gpx_without_points():
    with pytest.raises(MalformedGPXError):
        gpx.decode(b"<gpx></gpx>")


def test_rejects_malformed_xml():
    with pytest.raises(MalformedGPXError):
        gpx.decode(b"<gpx><trkpt")


def test_densify_interpolates_along_the_route_at_the_requested_speed():
    """Two waypoints alone would teleport the device straight to the destination."""
    start = LocationPoint(name="A", latitude=47.0, longitude=19.0)
    end = LocationPoint(name="B", latitude=47.01, longitude=19.0)

    leg_length = geometry.distance(start, end)
    dense = geometry.densify([start, end], speed_mps=10.0, start_time=0.0)

    # ~1111 m at 10 m/s ~= 111 s of travel, sampled about once a second.
    assert len(dense) > 50
    assert len(dense) <= geometry.MAX_SAMPLES

    # Every sample stays on the route, and the last lands on the destination.
    assert dense[-1].latitude == pytest.approx(end.latitude, abs=1e-4)
    assert dense[-1].longitude == pytest.approx(end.longitude, abs=1e-4)

    # Timestamps must be non-decreasing for playback pacing.
    times = [p.timestamp for p in dense]
    assert all(t is not None for t in times)
    assert all(a <= b for a, b in zip(times, times[1:]))

    # Total duration should track distance / speed.
    assert times[-1] - times[0] == pytest.approx(leg_length / 10.0, abs=2.0)


def test_densify_respects_the_sample_cap():
    """Half the planet at walking pace would otherwise generate millions of points."""
    dense = geometry.densify(
        [
            LocationPoint(name="A", latitude=0.0, longitude=0.0),
            LocationPoint(name="B", latitude=0.0, longitude=179.0),
        ],
        speed_mps=1.0,
        start_time=0.0,
    )
    assert len(dense) <= geometry.MAX_SAMPLES


def test_densify_handles_single_and_empty_input():
    assert geometry.densify([], speed_mps=10.0) == []
    single = geometry.densify(
        [LocationPoint(name="only", latitude=1.0, longitude=2.0)], speed_mps=10.0, start_time=0.0
    )
    assert len(single) == 1
    assert single[0].timestamp == 0.0


def test_densify_survives_duplicate_points():
    """A zero-length leg must not divide by zero or drop the waypoint."""
    p = LocationPoint(name="same", latitude=10.0, longitude=10.0)
    dense = geometry.densify([p, p, p], speed_mps=5.0, start_time=0.0)
    assert len(dense) == 3
    times = [x.timestamp for x in dense]
    assert all(a <= b for a, b in zip(times, times[1:]))


def test_coordinate_along_route_tracks_fraction():
    a = LocationPoint(name="A", latitude=47.0, longitude=19.0)
    b = LocationPoint(name="B", latitude=47.0, longitude=19.02)
    c = LocationPoint(name="C", latitude=47.0, longitude=19.06)
    route = [a, b, c]

    start = geometry.coordinate_along(route, 0.0)
    end = geometry.coordinate_along(route, 1.0)
    mid = geometry.coordinate_along(route, 0.5)

    assert start[1] == pytest.approx(19.0, abs=1e-6)
    assert end[1] == pytest.approx(19.06, abs=1e-6)
    # Half the total distance (0.06 deg of lon) lands at 19.03, on the B->C leg.
    assert mid[1] == pytest.approx(19.03, abs=1e-3)

    quarter = geometry.coordinate_along(route, 0.25)
    assert quarter[1] < mid[1]


def test_coordinate_along_handles_degenerate_input():
    assert geometry.coordinate_along([], 0.5) is None
    single = geometry.coordinate_along([LocationPoint(latitude=5.0, longitude=6.0)], 0.5)
    assert single == (5.0, 6.0)


def test_hold_interval_stays_inside_the_gps_override_window():
    """iOS reclaims the fix after ~5s; re-assertion must land sooner than that."""
    assert 0 < geometry.HOLD_INTERVAL <= 4.0


def test_distance_matches_known_separation():
    # One degree of latitude is ~111.2 km anywhere on the globe.
    a = LocationPoint(latitude=0.0, longitude=0.0)
    b = LocationPoint(latitude=1.0, longitude=0.0)
    assert geometry.distance(a, b) == pytest.approx(111_195, rel=0.001)


def test_interpolate_midpoint_is_between_endpoints():
    a = LocationPoint(latitude=0.0, longitude=0.0)
    b = LocationPoint(latitude=0.0, longitude=10.0)
    lat, lon = geometry.interpolate(a, b, 0.5)
    assert lon == pytest.approx(5.0, abs=1e-6)
    assert lat == pytest.approx(0.0, abs=1e-6)


def test_interpolate_clamps_out_of_range_fractions():
    a = LocationPoint(latitude=0.0, longitude=0.0)
    b = LocationPoint(latitude=0.0, longitude=10.0)
    assert geometry.interpolate(a, b, -5.0)[1] == pytest.approx(0.0, abs=1e-6)
    assert geometry.interpolate(a, b, 5.0)[1] == pytest.approx(10.0, abs=1e-6)


def test_validates_coordinate_ranges():
    assert LocationPoint(latitude=-90, longitude=180).is_valid
    assert not LocationPoint(latitude=91, longitude=0).is_valid
    assert not LocationPoint(latitude=0, longitude=-181).is_valid


def test_total_duration_scales_with_speed():
    a = LocationPoint(latitude=0.0, longitude=0.0)
    b = LocationPoint(latitude=0.0, longitude=1.0)
    slow = geometry.total_duration([a, b], 10.0)
    fast = geometry.total_duration([a, b], 20.0)
    assert slow == pytest.approx(fast * 2, rel=1e-6)
    assert geometry.total_duration([a], 10.0) == 0.0
