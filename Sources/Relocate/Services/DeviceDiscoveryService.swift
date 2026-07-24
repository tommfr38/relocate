import Foundation

actor DeviceDiscoveryService {
    private let runner = CommandRunner.shared

    func discover() async -> [DeviceTarget] {
        async let simulators = discoverSimulators()
        async let physicalDevices = discoverPhysicalDevices()
        return await (physicalDevices + simulators)
            .sorted { lhs, rhs in
                if lhs.kind != rhs.kind { return lhs.kind == .physical }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    private func discoverSimulators() async -> [DeviceTarget] {
        do {
            let result = try await runner.run(
                executable: "/usr/bin/xcrun",
                arguments: ["simctl", "list", "devices", "available", "-j"]
            )
            let response = try JSONDecoder().decode(SimctlResponse.self, from: Data(result.output.utf8))
            return response.devices.flatMap { runtime, devices in
                devices.map {
                    DeviceTarget(
                        id: $0.udid,
                        name: $0.name,
                        platform: "iOS Simulator",
                        osVersion: Self.runtimeVersion(runtime),
                        kind: .simulator,
                        connection: $0.state,
                        isAvailable: $0.isAvailable
                    )
                }
            }
        } catch {
            return []
        }
    }

    private func discoverPhysicalDevices() async -> [DeviceTarget] {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("relocate-devices-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        do {
            _ = try await runner.run(
                executable: "/usr/bin/xcrun",
                arguments: ["devicectl", "list", "devices", "--json-output", outputURL.path]
            )
            let data = try Data(contentsOf: outputURL)
            let response = try JSONDecoder().decode(DeviceCtlResponse.self, from: data)
            return response.result.devices.compactMap { device in
                guard device.hardwareProperties?.platform?.lowercased().contains("ios") == true ||
                        device.hardwareProperties?.deviceType?.lowercased() == "iphone" else { return nil }
                return DeviceTarget(
                    id: device.hardwareProperties?.udid ?? device.identifier,
                    name: device.deviceProperties?.name ?? "iPhone",
                    platform: device.hardwareProperties?.marketingName ?? "iPhone",
                    osVersion: device.deviceProperties?.osVersionNumber ?? "",
                    kind: .physical,
                    connection: device.connectionProperties?.transportType ?? "USB",
                    // Availability is "is it trusted and reachable", not devicectl's own
                    // tunnel state — pymobiledevice3 builds its own userspace tunnel, so a
                    // wired, paired device is usable even when devicectl reports
                    // tunnelState "disconnected".
                    isAvailable: (device.connectionProperties?.pairingState ?? "paired") == "paired"
                )
            }
        } catch {
            return []
        }
    }

    private static func runtimeVersion(_ runtime: String) -> String {
        runtime
            .replacingOccurrences(of: "com.apple.CoreSimulator.SimRuntime.iOS-", with: "iOS ")
            .replacingOccurrences(of: "-", with: ".")
    }
}

private struct SimctlResponse: Decodable {
    struct Device: Decodable {
        let name: String
        let udid: String
        let state: String
        let isAvailable: Bool
    }
    let devices: [String: [Device]]
}

private struct DeviceCtlResponse: Decodable {
    struct Result: Decodable {
        let devices: [Device]
    }
    struct Device: Decodable {
        struct DeviceProperties: Decodable {
            let name: String?
            let osVersionNumber: String?
        }
        struct HardwareProperties: Decodable {
            let marketingName: String?
            let platform: String?
            let deviceType: String?
            let udid: String?
        }
        struct ConnectionProperties: Decodable {
            let transportType: String?
            let tunnelState: String?
            let pairingState: String?
        }
        let identifier: String
        let deviceProperties: DeviceProperties?
        let hardwareProperties: HardwareProperties?
        let connectionProperties: ConnectionProperties?
    }
    let result: Result
}
