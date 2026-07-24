import Foundation

struct CommandResult: Sendable {
    let output: String
    let error: String
    let exitCode: Int32
}

actor CommandRunner {
    static let shared = CommandRunner()

    func run(
        executable: String,
        arguments: [String],
        environment: [String: String] = [:]
    ) async throws -> CommandResult {
        let process = Process()
        let standardOutput = Pipe()
        let standardError = Pipe()

        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = standardOutput
        process.standardError = standardError
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }

        do {
            try process.run()
        } catch {
            throw RelocateError.commandFailed("Could not launch \(executable): \(error.localizedDescription)")
        }

        let outputTask = Task.detached {
            standardOutput.fileHandleForReading.readDataToEndOfFile()
        }
        let errorTask = Task.detached {
            standardError.fileHandleForReading.readDataToEndOfFile()
        }

        process.waitUntilExit()
        let outputData = await outputTask.value
        let errorData = await errorTask.value
        let result = CommandResult(
            output: String(decoding: outputData, as: UTF8.self),
            error: String(decoding: errorData, as: UTF8.self),
            exitCode: process.terminationStatus
        )

        guard result.exitCode == 0 else {
            let message = result.error.trimmingCharacters(in: .whitespacesAndNewlines)
            throw RelocateError.commandFailed(message.isEmpty ? "Command failed with exit code \(result.exitCode)." : message)
        }
        return result
    }
}
