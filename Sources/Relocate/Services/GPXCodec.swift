import CoreLocation
import Foundation

enum GPXCodec {
    /// Encodes a single coordinate repeated on an interval, so `play` keeps re-asserting it.
    ///
    /// A one-shot `set` is overridden by the device's next real GPS fix after a few
    /// seconds; replaying the same point holds it in place indefinitely.
    static func encodeHold(point: LocationPoint) -> Data {
        let start = Date()
        let held = RouteGeometry.holdSamples(at: point, startingAt: start)
        return encodeTrack(held, start: start)
    }

    /// Encodes points as a GPX **track**.
    ///
    /// Playback consumers only read track points — `pymobiledevice3 simulate-location play`
    /// walks `gpx.tracks -> segments -> points` and ignores `<wpt>` and `<rte>` entirely.
    /// Emitting top-level `<wpt>` elements yields a file that parses cleanly but plays nothing.
    ///
    /// Pass `densify` to interpolate intermediate points so the device travels the route
    /// continuously instead of teleporting from waypoint to waypoint.
    static func encode(
        points: [LocationPoint],
        speedMetersPerSecond: Double = 12,
        densify: Bool = false
    ) -> Data {
        let start = Date()

        let track = densify
            ? RouteGeometry.densify(
                points: points,
                speedMetersPerSecond: speedMetersPerSecond,
                startingAt: start
              )
            : timedPoints(points, speedMetersPerSecond: speedMetersPerSecond, start: start)

        return encodeTrack(track, start: start)
    }

    /// Serializes already-timed points into a GPX track document.
    private static func encodeTrack(_ track: [LocationPoint], start: Date) -> Data {
        let formatter = ISO8601DateFormatter()
        let encodedPoints = track.map { point in
            let name = point.name.isEmpty ? "" : "\n        <name>\(escape(point.name))</name>"
            return """
                  <trkpt lat="\(point.latitude)" lon="\(point.longitude)">\(name)
                    <time>\(formatter.string(from: point.timestamp ?? start))</time>
                  </trkpt>
            """
        }.joined(separator: "\n")

        return Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="Relocate" xmlns="http://www.topografix.com/GPX/1/1">
          <trk>
            <name>Relocate Route</name>
            <trkseg>
        \(encodedPoints)
            </trkseg>
          </trk>
        </gpx>
        """.utf8)
    }

    /// Spaces timestamps by the real distance between consecutive points so the
    /// requested speed actually governs playback.
    private static func timedPoints(
        _ points: [LocationPoint],
        speedMetersPerSecond speed: Double,
        start: Date
    ) -> [LocationPoint] {
        var elapsed: TimeInterval = 0

        return points.enumerated().map { index, point in
            if index > 0 {
                let previous = points[index - 1]
                let distance = CLLocation(latitude: previous.latitude, longitude: previous.longitude)
                    .distance(from: CLLocation(latitude: point.latitude, longitude: point.longitude))
                elapsed += max(0.2, distance / max(speed, 0.5))
            }
            var copy = point
            copy.timestamp = point.timestamp ?? start.addingTimeInterval(elapsed)
            return copy
        }
    }

    static func decode(data: Data) throws -> [LocationPoint] {
        let parserDelegate = GPXParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = parserDelegate
        guard parser.parse(), !parserDelegate.points.isEmpty else {
            throw RelocateError.malformedGPX
        }
        return parserDelegate.points
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

private final class GPXParserDelegate: NSObject, XMLParserDelegate {
    var points: [LocationPoint] = []
    private var pendingCoordinate: (Double, Double)?
    private var pendingName = ""
    private var currentElement = ""
    private var text = ""

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        currentElement = elementName
        text = ""
        if ["wpt", "trkpt", "rtept"].contains(elementName),
           let latitude = attributeDict["lat"].flatMap(Double.init),
           let longitude = attributeDict["lon"].flatMap(Double.init) {
            pendingCoordinate = (latitude, longitude)
            pendingName = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        if elementName == "name", pendingCoordinate != nil {
            pendingName = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if ["wpt", "trkpt", "rtept"].contains(elementName), let coordinate = pendingCoordinate {
            points.append(
                LocationPoint(
                    name: pendingName.isEmpty ? "Waypoint \(points.count + 1)" : pendingName,
                    latitude: coordinate.0,
                    longitude: coordinate.1
                )
            )
            pendingCoordinate = nil
        }
        currentElement = ""
        text = ""
    }
}
