import Foundation

/// Great-circle helpers used to pace and smooth route playback.
enum RouteGeometry {
    static let earthRadius = 6_371_000.0

    /// Upper bound on generated track points, so a long route at a slow speed
    /// cannot produce a multi-hundred-megabyte GPX file.
    static let maximumSamples = 20_000

    /// Default cadence for re-asserting a held position. iOS overrides a one-shot
    /// simulated fix with the next real GPS fix after roughly 5–10 seconds, so the
    /// coordinate has to be repeated well inside that window.
    static let holdInterval: TimeInterval = 2

    /// How long a held position keeps being re-asserted before the track runs out.
    static let holdDuration: TimeInterval = 12 * 3600

    /// Repeats a coordinate on an interval so the device keeps re-asserting it.
    ///
    /// `simulate-location set` calls the DVT selector once and then blocks, which lets
    /// real GPS win a few seconds later. Feeding the same point repeatedly through
    /// `play` instead keeps the simulated location pinned.
    static func holdSamples(
        at point: LocationPoint,
        interval: TimeInterval = holdInterval,
        duration: TimeInterval = holdDuration,
        startingAt start: Date
    ) -> [LocationPoint] {
        let interval = max(interval, 0.5)
        let count = max(1, Int((duration / interval).rounded(.down)))

        return (0...count).map { step in
            LocationPoint(
                name: step == 0 ? point.name : "",
                latitude: point.latitude,
                longitude: point.longitude,
                timestamp: start.addingTimeInterval(Double(step) * interval)
            )
        }
    }

    /// How long a route takes to play at the given speed.
    static func totalDuration(points: [LocationPoint], speedMetersPerSecond speed: Double) -> TimeInterval {
        guard points.count >= 2 else { return 0 }
        let total = zip(points, points.dropFirst())
            .reduce(0.0) { $0 + distance(from: $1.0, to: $1.1) }
        return total / max(speed, 0.1)
    }

    /// Metres between two coordinates along the surface of the earth.
    static func distance(from start: LocationPoint, to end: LocationPoint) -> Double {
        let lat1 = start.latitude * .pi / 180
        let lat2 = end.latitude * .pi / 180
        let deltaLat = lat2 - lat1
        let deltaLon = (end.longitude - start.longitude) * .pi / 180

        let a = pow(sin(deltaLat / 2), 2) + cos(lat1) * cos(lat2) * pow(sin(deltaLon / 2), 2)
        return 2 * earthRadius * asin(min(1, sqrt(a)))
    }

    /// The coordinate at a fraction (0...1) of the total distance along a multi-leg route.
    /// Used to animate the live-position marker during playback.
    static func coordinate(
        along points: [LocationPoint],
        atFraction fraction: Double
    ) -> (latitude: Double, longitude: Double)? {
        guard let first = points.first else { return nil }
        guard points.count > 1 else { return (first.latitude, first.longitude) }

        let t = min(max(fraction, 0), 1)
        let legs = Array(zip(points, points.dropFirst()))
        let total = legs.reduce(0.0) { $0 + distance(from: $1.0, to: $1.1) }
        guard total > 0 else { return (first.latitude, first.longitude) }

        let target = t * total
        var travelled = 0.0
        for (origin, destination) in legs {
            let legDistance = distance(from: origin, to: destination)
            if travelled + legDistance >= target {
                let within = legDistance > 0 ? (target - travelled) / legDistance : 0
                return interpolate(from: origin, to: destination, fraction: within)
            }
            travelled += legDistance
        }
        return (points.last!.latitude, points.last!.longitude)
    }

    /// Spherical interpolation between two coordinates. `fraction` is clamped to 0...1.
    ///
    /// Linear interpolation of latitude/longitude drifts badly over long legs, so this
    /// walks the actual great-circle arc instead.
    static func interpolate(
        from start: LocationPoint,
        to end: LocationPoint,
        fraction: Double
    ) -> (latitude: Double, longitude: Double) {
        let t = min(max(fraction, 0), 1)

        let lat1 = start.latitude * .pi / 180
        let lon1 = start.longitude * .pi / 180
        let lat2 = end.latitude * .pi / 180
        let lon2 = end.longitude * .pi / 180

        let deltaLat = lat2 - lat1
        let deltaLon = lon2 - lon1
        let haversine = pow(sin(deltaLat / 2), 2) + cos(lat1) * cos(lat2) * pow(sin(deltaLon / 2), 2)
        let angle = 2 * asin(min(1, sqrt(haversine)))

        // Coincident (or effectively coincident) points: nothing to interpolate.
        guard angle > 1e-12 else { return (start.latitude, start.longitude) }

        let a = sin((1 - t) * angle) / sin(angle)
        let b = sin(t * angle) / sin(angle)

        let x = a * cos(lat1) * cos(lon1) + b * cos(lat2) * cos(lon2)
        let y = a * cos(lat1) * sin(lon1) + b * cos(lat2) * sin(lon2)
        let z = a * sin(lat1) + b * sin(lat2)

        return (
            latitude: atan2(z, sqrt(x * x + y * y)) * 180 / .pi,
            longitude: atan2(y, x) * 180 / .pi
        )
    }

    /// Expands sparse waypoints into a dense, evenly timed track.
    ///
    /// Playback teleports between whatever points the GPX contains, so a two-waypoint
    /// route would jump straight to the destination. Sampling each leg at a fixed
    /// cadence makes the device travel the route at the requested speed instead.
    static func densify(
        points: [LocationPoint],
        speedMetersPerSecond speed: Double,
        sampleInterval: TimeInterval = 1,
        startingAt start: Date = Date()
    ) -> [LocationPoint] {
        guard points.count >= 2 else {
            return points.enumerated().map { index, point in
                var copy = point
                copy.timestamp = start.addingTimeInterval(Double(index))
                return copy
            }
        }

        let speed = max(speed, 0.1)
        let interval = max(sampleInterval, 0.1)

        let totalDistance = zip(points, points.dropFirst())
            .reduce(0.0) { $0 + distance(from: $1.0, to: $1.1) }
        let totalDuration = totalDistance / speed

        // Stretch the cadence if the route would otherwise blow past the sample cap.
        // Rounding up within each leg can add one extra sample per leg, so the budget
        // reserves headroom for that plus the initial point.
        let projected = Int((totalDuration / interval).rounded(.up)) + points.count
        let budget = max(1, maximumSamples - points.count - 1)
        let step = projected > maximumSamples
            ? totalDuration / Double(budget)
            : interval

        var result: [LocationPoint] = []
        var elapsed: TimeInterval = 0

        var first = points[0]
        first.timestamp = start
        result.append(first)

        for (origin, destination) in zip(points, points.dropFirst()) {
            let legDistance = distance(from: origin, to: destination)
            let legDuration = legDistance / speed

            // Zero-length leg: emit the destination so the waypoint is not lost.
            guard legDuration > step else {
                elapsed += max(legDuration, step)
                var point = destination
                point.timestamp = start.addingTimeInterval(elapsed)
                result.append(point)
                continue
            }

            let sampleCount = Int((legDuration / step).rounded(.up))
            for sample in 1...sampleCount {
                let fraction = min(Double(sample) * step / legDuration, 1)
                let coordinate = interpolate(from: origin, to: destination, fraction: fraction)
                let isFinal = sample == sampleCount

                result.append(
                    LocationPoint(
                        name: isFinal ? destination.name : "",
                        latitude: coordinate.latitude,
                        longitude: coordinate.longitude,
                        timestamp: start.addingTimeInterval(elapsed + min(Double(sample) * step, legDuration))
                    )
                )
            }
            elapsed += legDuration
        }

        return result
    }
}
