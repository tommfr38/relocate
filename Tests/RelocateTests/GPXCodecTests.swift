import Foundation
import Testing
@testable import Relocate

struct GPXCodecTests {
    @Test
    func roundTripPreservesCoordinatesAndNames() throws {
        let points = [
            LocationPoint(name: "Start & Go", latitude: 47.4979, longitude: 19.0402),
            LocationPoint(name: "Finish", latitude: 48.2082, longitude: 16.3738)
        ]

        let decoded = try GPXCodec.decode(data: GPXCodec.encode(points: points))

        #expect(decoded.count == 2)
        #expect(decoded[0].name == "Start & Go")
        #expect(decoded[0].latitude == 47.4979)
        #expect(decoded[1].longitude == 16.3738)
    }

    /// pymobiledevice3 walks `gpx.tracks -> segments -> points`, so a route encoded as
    /// top-level `<wpt>` elements parses cleanly but plays nothing at all.
    @Test
    func encodesRouteAsTrackPointsNotWaypoints() {
        let points = [
            LocationPoint(name: "A", latitude: 47.4979, longitude: 19.0402),
            LocationPoint(name: "B", latitude: 47.5079, longitude: 19.0502)
        ]

        let gpx = String(decoding: GPXCodec.encode(points: points), as: UTF8.self)

        #expect(gpx.contains("<trk>"))
        #expect(gpx.contains("<trkseg>"))
        #expect(gpx.contains("<trkpt"))
        #expect(!gpx.contains("<wpt"))
    }

    /// Two waypoints alone would teleport the device straight to the destination.
    @Test
    func densifyInterpolatesAlongTheRouteAtTheRequestedSpeed() {
        let start = LocationPoint(name: "A", latitude: 47.0, longitude: 19.0)
        let end = LocationPoint(name: "B", latitude: 47.01, longitude: 19.0)

        let legLength = RouteGeometry.distance(from: start, to: end)
        let dense = RouteGeometry.densify(points: [start, end], speedMetersPerSecond: 10)

        // ~1111 m at 10 m/s ≈ 111 s of travel, sampled about once a second.
        #expect(dense.count > 50)
        #expect(dense.count <= RouteGeometry.maximumSamples)

        // Every sample stays on the route, and the last one lands on the destination.
        #expect(abs(dense.last!.latitude - end.latitude) < 0.0001)
        #expect(abs(dense.last!.longitude - end.longitude) < 0.0001)

        // Timestamps must be strictly non-decreasing for playback pacing.
        let times = dense.compactMap(\.timestamp)
        #expect(times.count == dense.count)
        #expect(zip(times, times.dropFirst()).allSatisfy { $0 <= $1 })

        // Total duration should track distance / speed.
        let duration = times.last!.timeIntervalSince(times.first!)
        #expect(abs(duration - legLength / 10) < 2)
    }

    @Test
    func densifyRespectsTheSampleCap() {
        // Half the planet at walking pace would otherwise generate millions of points.
        let dense = RouteGeometry.densify(
            points: [
                LocationPoint(name: "A", latitude: 0, longitude: 0),
                LocationPoint(name: "B", latitude: 0, longitude: 179)
            ],
            speedMetersPerSecond: 1
        )
        #expect(dense.count <= RouteGeometry.maximumSamples)
    }

    @Test
    func rejectsGPXWithoutWaypoints() {
        #expect(throws: RelocateError.self) {
            try GPXCodec.decode(data: Data("<gpx></gpx>".utf8))
        }
    }

    /// A static location has to be re-asserted, or iOS overrides it with real GPS after
    /// a few seconds. The hold GPX must repeat one coordinate on a short interval.
    @Test
    func encodeHoldRepeatsOneCoordinateAsTrackPoints() throws {
        let point = LocationPoint(name: "Home", latitude: 47.4979, longitude: 19.0402)
        let gpx = String(decoding: GPXCodec.encodeHold(point: point), as: UTF8.self)

        #expect(gpx.contains("<trkpt"))
        #expect(!gpx.contains("<wpt"))

        let decoded = try GPXCodec.decode(data: Data(gpx.utf8))
        #expect(decoded.count > 100)
        #expect(decoded.allSatisfy { abs($0.latitude - 47.4979) < 1e-9 && abs($0.longitude - 19.0402) < 1e-9 })
    }

    @Test
    func holdSamplesStayWellInsideTheGpsOverrideWindow() {
        let samples = RouteGeometry.holdSamples(
            at: LocationPoint(name: "H", latitude: 0, longitude: 0),
            startingAt: Date()
        )
        let times = samples.compactMap(\.timestamp)
        let gaps = zip(times, times.dropFirst()).map { $1.timeIntervalSince($0) }
        // iOS reclaims the fix after ~5s; every re-assertion must land sooner than that.
        #expect(gaps.allSatisfy { $0 <= 4 })
    }

    @Test
    func coordinateAlongRouteTracksFraction() {
        let a = LocationPoint(name: "A", latitude: 47.0, longitude: 19.0)
        let b = LocationPoint(name: "B", latitude: 47.0, longitude: 19.02)
        let c = LocationPoint(name: "C", latitude: 47.0, longitude: 19.06)
        let route = [a, b, c]

        let start = RouteGeometry.coordinate(along: route, atFraction: 0)!
        let end = RouteGeometry.coordinate(along: route, atFraction: 1)!
        let mid = RouteGeometry.coordinate(along: route, atFraction: 0.5)!

        #expect(abs(start.longitude - 19.0) < 1e-6)
        #expect(abs(end.longitude - 19.06) < 1e-6)
        // Half the total distance (0.06° of lon) lands at 19.03, on the B→C leg.
        #expect(abs(mid.longitude - 19.03) < 0.001)
        // Monotonic in fraction.
        let q1 = RouteGeometry.coordinate(along: route, atFraction: 0.25)!
        #expect(q1.longitude < mid.longitude)
    }

    @Test
    func validatesCoordinateRanges() {
        #expect(LocationPoint(name: "Valid", latitude: -90, longitude: 180).isValid)
        #expect(!LocationPoint(name: "Invalid", latitude: 91, longitude: 0).isValid)
        #expect(!LocationPoint(name: "Invalid", latitude: 0, longitude: -181).isValid)
    }
}
