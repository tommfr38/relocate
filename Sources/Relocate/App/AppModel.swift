import AppKit
import Foundation
import MapKit
import Observation
import UniformTypeIdentifiers

@MainActor
@Observable
final class AppModel {
    var devices: [DeviceTarget] = []
    var selectedDeviceID: String?
    var selectedPoint = LocationPoint(name: "Budapest", latitude: 47.4979, longitude: 19.0402)
    var route: [LocationPoint] = []
    var savedPlaces: [SavedPlace] = []
    var simulationState: SimulationState = .idle
    var searchText = ""
    var searchResults: [MKMapItem] = []
    var isRefreshing = false
    var isSearching = false
    var showSetup = false
    var showTutorial = false
    var showInspector = true
    var speedMetersPerSecond = 13.9
    var lastMessage = "Ready"
    var dependencyAvailable = false
    var xcodeVersion = "Checking…"

    private let discovery = DeviceDiscoveryService()
    private let engine = LocationEngine()
    private var searchTask: Task<Void, Never>?
    private var routeCompletionTask: Task<Void, Never>?
    private var routeCursorTask: Task<Void, Never>?

    /// Live estimated position along the route while it plays, shown as a moving marker.
    var routeCursor: LocationPoint?

    var selectedDevice: DeviceTarget? {
        devices.first { $0.id == selectedDeviceID }
    }

    var canApply: Bool {
        selectedDevice?.isAvailable == true && selectedPoint.isValid && !simulationState.isRunning
    }

    var canPlayRoute: Bool {
        selectedDevice?.isAvailable == true && route.count >= 2 && !simulationState.isRunning
    }

    func start() async {
        loadSavedPlaces()
        await engine.onSessionEnded { [weak self] status in
            guard let self else { return }
            guard self.simulationState.isRunning else { return }
            self.clearRouteCursor()
            if status == 0 {
                self.simulationState = .idle
                self.lastMessage = "Route finished — real location restored"
            } else {
                self.simulationState = .failed("The device session ended unexpectedly.")
                self.lastMessage = "Session ended — check the cable and that the iPhone is unlocked"
            }
        }
        if let result = try? await CommandRunner.shared.run(
            executable: "/usr/bin/xcodebuild",
            arguments: ["-version"]
        ) {
            xcodeVersion = result.output
                .split(separator: "\n")
                .first
                .map(String.init)?
                .replacingOccurrences(of: "Xcode ", with: "") ?? "Available"
        } else {
            xcodeVersion = "Not detected"
        }
        dependencyAvailable = await engine.dependencyAvailable()
        await refreshDevices()
    }

    func refreshDevices() async {
        isRefreshing = true
        devices = await discovery.discover()
        if selectedDevice == nil {
            selectedDeviceID = devices.first(where: { $0.kind == .physical && $0.isAvailable })?.id
                ?? devices.first(where: \.isAvailable)?.id
        }
        lastMessage = devices.isEmpty ? "No devices detected" : "\(devices.count) device\(devices.count == 1 ? "" : "s") available"
        isRefreshing = false
    }

    func select(point: LocationPoint) {
        selectedPoint = point
        lastMessage = "Location selected"
    }

    func search() {
        searchTask?.cancel()
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            searchResults = []
            isSearching = false
            return
        }

        isSearching = true
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(280))
            guard !Task.isCancelled else { return }
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            request.resultTypes = [.address, .pointOfInterest]
            do {
                let response = try await MKLocalSearch(request: request).start()
                guard !Task.isCancelled else { return }
                searchResults = Array(response.mapItems.prefix(8))
            } catch {
                searchResults = []
            }
            isSearching = false
        }
    }

    func chooseSearchResult(_ item: MKMapItem) {
        let coordinate = item.placemark.coordinate
        selectedPoint = LocationPoint(
            name: item.name ?? item.placemark.title ?? "Selected location",
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
        searchText = ""
        searchResults = []
    }

    func applySelectedLocation() async {
        guard let device = selectedDevice else {
            present(error: RelocateError.noDevice)
            return
        }
        simulationState = .preparing
        lastMessage = "Starting secure developer session…"
        do {
            try await engine.set(point: selectedPoint, on: device)
            simulationState = .active(selectedPoint)
            lastMessage = "Simulating \(selectedPoint.name) on \(device.name)"
        } catch {
            present(error: error)
        }
    }

    func playRoute() async {
        guard let device = selectedDevice else {
            present(error: RelocateError.noDevice)
            return
        }
        simulationState = .preparing
        lastMessage = "Preparing \(route.count)-point route…"
        do {
            try await engine.play(points: route, speed: speedMetersPerSecond, on: device)
            simulationState = .playing(progress: 0)
            lastMessage = "Route playing on \(device.name)"
            scheduleRouteCompletionNotice(on: device)
            animateRouteCursor()
        } catch {
            present(error: error)
        }
    }

    /// Advances the live-position marker along the route in step with playback.
    ///
    /// The device is driven by the densified GPX we generated at this exact speed and
    /// start time, so a local time-based estimate tracks the device's real position
    /// closely without having to read anything back over the wire.
    private func animateRouteCursor() {
        routeCursorTask?.cancel()
        let points = route
        let duration = RouteGeometry.totalDuration(points: points, speedMetersPerSecond: speedMetersPerSecond)
        guard duration > 0, points.count >= 2 else { return }

        let start = Date()
        routeCursor = points.first

        routeCursorTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let fraction = min(Date().timeIntervalSince(start) / duration, 1)
                if let coordinate = RouteGeometry.coordinate(along: points, atFraction: fraction) {
                    self.routeCursor = LocationPoint(
                        name: "Current position",
                        latitude: coordinate.latitude,
                        longitude: coordinate.longitude
                    )
                }
                if fraction >= 1 { break }
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
    }

    private func clearRouteCursor() {
        routeCursorTask?.cancel()
        routeCursorTask = nil
        routeCursor = nil
    }

    /// `pymobiledevice3 play` keeps the session open after the last track point so the
    /// device stays parked at the destination — it never exits on its own. Without this
    /// the status would read "Route playing" indefinitely.
    private func scheduleRouteCompletionNotice(on device: DeviceTarget) {
        routeCompletionTask?.cancel()
        let duration = RouteGeometry.totalDuration(
            points: route,
            speedMetersPerSecond: speedMetersPerSecond
        )
        let destination = route.last

        routeCompletionTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(duration, 0)))
            guard !Task.isCancelled, let self else { return }
            guard case .playing = self.simulationState else { return }

            self.simulationState = .active(destination ?? self.selectedPoint)
            self.lastMessage = "Route finished — holding \(destination?.name ?? "final position") on \(device.name)"
            self.clearRouteCursor()
        }
    }

    func stopSimulation() async {
        routeCompletionTask?.cancel()
        routeCompletionTask = nil
        clearRouteCursor()
        let device = selectedDevice
        simulationState = .stopping
        lastMessage = "Restoring real location…"
        do {
            try await engine.stop(device: device)
            simulationState = .idle
            lastMessage = "Real location restored"
        } catch {
            present(error: error)
        }
    }

    func addSelectedToRoute() {
        var point = selectedPoint
        point.name = point.name.isEmpty ? "Waypoint \(route.count + 1)" : point.name
        route.append(point)
        lastMessage = "Waypoint \(route.count) added"
    }

    func removeRoutePoints(at offsets: IndexSet) {
        route.remove(atOffsets: offsets)
    }

    func clearRoute() {
        route.removeAll()
    }

    var selectedPointIsSaved: Bool {
        savedPlaces.contains { matches($0.point, selectedPoint) }
    }

    @discardableResult
    func saveSelectedPlace() -> Bool {
        guard !selectedPointIsSaved else {
            lastMessage = "That place is already saved"
            return false
        }
        let name = selectedPoint.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let place = SavedPlace(
            name: name.isEmpty ? selectedPoint.coordinateLabel : name,
            point: selectedPoint
        )
        savedPlaces.append(place)
        persistSavedPlaces()
        lastMessage = "Saved “\(place.name)”"
        return true
    }

    func deleteSavedPlace(_ place: SavedPlace) {
        savedPlaces.removeAll { $0.id == place.id }
        persistSavedPlaces()
        lastMessage = "Removed “\(place.name)”"
    }

    func deleteSavedPlaces(at offsets: IndexSet) {
        let names = offsets.map { savedPlaces[$0].name }
        savedPlaces.remove(atOffsets: offsets)
        persistSavedPlaces()
        lastMessage = names.count == 1
            ? "Removed “\(names[0])”"
            : "Removed \(names.count) places"
    }

    func moveSavedPlaces(from source: IndexSet, to destination: Int) {
        savedPlaces.move(fromOffsets: source, toOffset: destination)
        persistSavedPlaces()
    }

    func renameSavedPlace(_ place: SavedPlace, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = savedPlaces.firstIndex(where: { $0.id == place.id }) else { return }
        savedPlaces[index].name = trimmed
        savedPlaces[index].point.name = trimmed
        persistSavedPlaces()
        lastMessage = "Renamed to “\(trimmed)”"
    }

    /// Replaces a saved place's coordinates with whatever is currently selected.
    func updateSavedPlace(_ place: SavedPlace, toSelectedPoint: Bool = true) {
        guard let index = savedPlaces.firstIndex(where: { $0.id == place.id }) else { return }
        var point = selectedPoint
        point.name = savedPlaces[index].name
        savedPlaces[index].point = point
        persistSavedPlaces()
        lastMessage = "Updated “\(savedPlaces[index].name)” to the selected coordinates"
    }

    func addSavedPlaceToRoute(_ place: SavedPlace) {
        route.append(place.point)
        lastMessage = "Added “\(place.name)” to the route"
    }

    private func matches(_ lhs: LocationPoint, _ rhs: LocationPoint) -> Bool {
        abs(lhs.latitude - rhs.latitude) < 0.000001 && abs(lhs.longitude - rhs.longitude) < 0.000001
    }

    func importGPX(from url: URL) {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }
        do {
            route = try GPXCodec.decode(data: Data(contentsOf: url))
            if let first = route.first { selectedPoint = first }
            lastMessage = "Imported \(route.count) waypoints"
        } catch {
            present(error: error)
        }
    }

    func exportGPX() {
        guard !route.isEmpty else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "gpx") ?? .xml]
        panel.nameFieldStringValue = "Relocate Route.gpx"
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try GPXCodec.encode(points: route, speedMetersPerSecond: speedMetersPerSecond)
                    .write(to: url, options: .atomic)
                lastMessage = "Route exported"
            } catch {
                present(error: error)
            }
        }
    }

    func copyCoordinates() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(selectedPoint.coordinateLabel, forType: .string)
        lastMessage = "Coordinates copied"
    }

    private func present(error: Error) {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        simulationState = .failed(message)
        lastMessage = message
        if case RelocateError.missingDependency = error {
            showSetup = true
        }
    }

    private func loadSavedPlaces() {
        guard let data = UserDefaults.standard.data(forKey: "savedPlaces"),
              let places = try? JSONDecoder().decode([SavedPlace].self, from: data) else {
            savedPlaces = [
                SavedPlace(name: "Apple Park", point: LocationPoint(name: "Apple Park", latitude: 37.3349, longitude: -122.0090)),
                SavedPlace(name: "Budapest", point: LocationPoint(name: "Budapest", latitude: 47.4979, longitude: 19.0402)),
                SavedPlace(name: "London", point: LocationPoint(name: "London", latitude: 51.5074, longitude: -0.1278))
            ]
            return
        }
        savedPlaces = places
    }

    private func persistSavedPlaces() {
        if let data = try? JSONEncoder().encode(savedPlaces) {
            UserDefaults.standard.set(data, forKey: "savedPlaces")
        }
    }
}
