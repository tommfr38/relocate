import CoreLocation
import Foundation

struct LocationPoint: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var latitude: Double
    var longitude: Double
    var timestamp: Date?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var coordinateLabel: String {
        String(format: "%.6f, %.6f", latitude, longitude)
    }

    var isValid: Bool {
        (-90...90).contains(latitude) && (-180...180).contains(longitude)
    }
}

struct SavedPlace: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var point: LocationPoint
    var symbol: String = "mappin"
}

enum TargetKind: String, Codable, Sendable {
    case simulator
    case physical
}

struct DeviceTarget: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var name: String
    var platform: String
    var osVersion: String
    var kind: TargetKind
    var connection: String
    var isAvailable: Bool

    var symbol: String {
        kind == .physical ? "iphone.gen3" : "iphone.and.arrow.forward"
    }

    var detail: String {
        [platform, osVersion, connection].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

enum SimulationState: Equatable, Sendable {
    case idle
    case preparing
    case active(LocationPoint)
    case playing(progress: Double)
    case stopping
    case failed(String)

    var isRunning: Bool {
        switch self {
        case .active, .playing, .preparing, .stopping: true
        case .idle, .failed: false
        }
    }
}

enum RelocateError: LocalizedError, Sendable {
    case noDevice
    case invalidCoordinate
    case missingDependency
    case commandFailed(String)
    case unsupported(String)
    case malformedGPX

    var errorDescription: String? {
        switch self {
        case .noDevice:
            "Select an available device first."
        case .invalidCoordinate:
            "Latitude must be between −90 and 90; longitude between −180 and 180."
        case .missingDependency:
            "Physical iPhone support requires pymobiledevice3. Install it with the command shown in Setup."
        case .commandFailed(let message):
            message
        case .unsupported(let message):
            message
        case .malformedGPX:
            "The GPX file does not contain valid waypoints."
        }
    }
}
