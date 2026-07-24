import Foundation

actor LocationEngine {
    private let runner = CommandRunner.shared
    private var physicalSession: Process?
    private var sessionErrorPipe: Pipe?
    private var sessionInputPipe: Pipe?
    private var temporaryGPX: URL?
    private var sessionEnded: (@MainActor @Sendable (Int32) -> Void)?

    func set(point: LocationPoint, on device: DeviceTarget) async throws {
        guard point.isValid else { throw RelocateError.invalidCoordinate }
        try await stop(device: device, clearOnly: false)

        switch device.kind {
        case .simulator:
            _ = try await runner.run(
                executable: "/usr/bin/xcrun",
                arguments: ["simctl", "location", device.id, "set", "\(point.latitude),\(point.longitude)"]
            )
        case .physical:
            // `simulate-location set` fires the DVT selector once and then blocks, so the
            // device's next real GPS fix overrides it after a few seconds ("teleported home").
            // Replaying the same coordinate on a short interval keeps it pinned instead.
            let executable = try physicalExecutable()
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("relocate-hold-\(UUID().uuidString).gpx")
            try GPXCodec.encodeHold(point: point).write(to: url, options: .atomic)
            temporaryGPX = url
            try await startPhysicalSession(
                executable: executable,
                arguments: physicalArguments(
                    device: device,
                    subcommand: ["developer", "dvt", "simulate-location", "play"],
                    positional: [url.path]
                )
            )
        }
    }

    func play(points: [LocationPoint], speed: Double, on device: DeviceTarget) async throws {
        guard points.count >= 2, points.allSatisfy(\.isValid) else {
            throw RelocateError.unsupported("A route needs at least two valid waypoints.")
        }
        try await stop(device: device, clearOnly: false)

        switch device.kind {
        case .simulator:
            let coordinates = points.map { "\($0.latitude),\($0.longitude)" }
            _ = try await runner.run(
                executable: "/usr/bin/xcrun",
                arguments: ["simctl", "location", device.id, "start", "--speed=\(max(speed, 0.5))"] + coordinates
            )
        case .physical:
            let executable = try physicalExecutable()
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("relocate-route-\(UUID().uuidString).gpx")
            try GPXCodec.encode(points: points, speedMetersPerSecond: speed, densify: true)
                .write(to: url, options: .atomic)
            temporaryGPX = url
            try await startPhysicalSession(
                executable: executable,
                arguments: physicalArguments(
                    device: device,
                    subcommand: ["developer", "dvt", "simulate-location", "play"],
                    positional: [url.path]
                )
            )
        }
    }

    func stop(device: DeviceTarget?, clearOnly: Bool = true) async throws {
        if let process = physicalSession {
            // Detach first: this is a deliberate stop, not a session ending by itself,
            // so the termination callback must not fire and re-enter the UI state.
            process.terminationHandler = nil
            physicalSession = nil
            sessionErrorPipe = nil
            sessionInputPipe = nil

            process.interrupt()
            try? await Task.sleep(for: .milliseconds(250))
            if process.isRunning { process.terminate() }
        }
        if let temporaryGPX {
            try? FileManager.default.removeItem(at: temporaryGPX)
            self.temporaryGPX = nil
        }
        guard clearOnly, let device else { return }

        switch device.kind {
        case .simulator:
            _ = try await runner.run(
                executable: "/usr/bin/xcrun",
                arguments: ["simctl", "location", device.id, "clear"]
            )
        case .physical:
            let executable = try physicalExecutable()
            _ = try await runner.run(
                executable: executable,
                arguments: physicalArguments(
                    device: device,
                    subcommand: ["developer", "dvt", "simulate-location", "clear"]
                )
            )
        }
    }

    func dependencyAvailable() -> Bool {
        (try? physicalExecutable()) != nil
    }

    private func startPhysicalSession(executable: String, arguments: [String]) async throws {
        let process = Process()
        let errorPipe = Pipe()
        let inputPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardInput = inputPipe
        process.standardOutput = Pipe()
        process.standardError = errorPipe
        do {
            try process.run()
        } catch {
            throw RelocateError.commandFailed("Unable to start the physical-device backend: \(error.localizedDescription)")
        }

        // Long enough for the Python interpreter to start and for any CLI-usage
        // error (bad flag, unknown device) to surface as an early exit.
        try await Task.sleep(for: .milliseconds(2500))
        if !process.isRunning {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw RelocateError.commandFailed(message.isEmpty ? "The physical-device session ended unexpectedly." : message)
        }
        // A route ends on its own when the GPX runs out. Without this the UI would sit
        // in "playing" with a Stop button forever.
        process.terminationHandler = { [weak self] finished in
            guard let self else { return }
            Task { await self.sessionDidTerminate(finished) }
        }

        physicalSession = process
        sessionErrorPipe = errorPipe
        sessionInputPipe = inputPipe
    }

    /// Invoked when a held session exits by itself (route finished, device unplugged,
    /// phone locked). Ignored when the process is one we already replaced or stopped.
    private func sessionDidTerminate(_ process: Process) {
        guard physicalSession === process else { return }
        physicalSession = nil
        sessionErrorPipe = nil
        sessionInputPipe = nil

        if let temporaryGPX {
            try? FileManager.default.removeItem(at: temporaryGPX)
            self.temporaryGPX = nil
        }

        let handler = sessionEnded
        Task { @MainActor in handler?(process.terminationStatus) }
    }

    /// Set by `AppModel` so the UI can return to idle when a session ends on its own.
    func onSessionEnded(_ handler: @escaping @MainActor @Sendable (Int32) -> Void) {
        sessionEnded = handler
    }

    /// Builds a `pymobiledevice3` invocation.
    ///
    /// Device-selection flags belong to the *subcommand*, not the root command:
    /// `pymobiledevice3 developer dvt simulate-location set --udid <id> -- <lat> <lon>`.
    /// Passing `--udid` before the subcommand fails with "No such option: --udid".
    ///
    /// `--userspace` establishes the iOS 17+ RemoteXPC tunnel in-process, so the app
    /// never needs root or a separately running `tunneld`.
    private func physicalArguments(
        device: DeviceTarget,
        subcommand: [String],
        positional: [String] = []
    ) -> [String] {
        var arguments = subcommand
        arguments += ["--userspace", "--udid", device.id]
        if !positional.isEmpty {
            arguments += ["--"] + positional
        }
        return arguments
    }

    private func physicalExecutable() throws -> String {
        let candidates = [
            "/opt/homebrew/bin/pymobiledevice3",
            "/usr/local/bin/pymobiledevice3",
            "\(FileManager.default.homeDirectoryForCurrentUser.path)/.local/bin/pymobiledevice3",
            "\(FileManager.default.homeDirectoryForCurrentUser.path)/.local/pipx/venvs/pymobiledevice3/bin/pymobiledevice3",
            "\(FileManager.default.homeDirectoryForCurrentUser.path)/Library/Application Support/pipx/venvs/pymobiledevice3/bin/pymobiledevice3"
        ]
        guard let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw RelocateError.missingDependency
        }
        return path
    }
}
