import AppKit
import SwiftUI

@main
struct RelocateApp: App {
    @NSApplicationDelegateAdaptor(AppLifecycleDelegate.self) private var lifecycleDelegate
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .frame(minWidth: 1080, minHeight: 720)
                .task {
                    lifecycleDelegate.model = model
                    await model.start()
                }
        }
        .defaultSize(width: 1320, height: 860)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Refresh Devices") {
                    Task { await model.refreshDevices() }
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .help) {
                Button("iPhone Setup Tutorial") {
                    model.showTutorial = true
                }
                Button("Mac Setup…") {
                    model.showSetup = true
                }
            }
            CommandMenu("Simulation") {
                Button("Set Location") {
                    Task { await model.applySelectedLocation() }
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(!model.canApply)

                Button("Stop and Restore Real Location") {
                    Task { await model.stopSimulation() }
                }
                .keyboardShortcut(".", modifiers: .command)
                .disabled(!model.simulationState.isRunning)
            }
        }

        Settings {
            SettingsView()
                .environment(model)
                .frame(width: 560, height: 390)
        }
    }
}

@MainActor
final class AppLifecycleDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?
    private var isFinishingTermination = false

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !isFinishingTermination,
              let model,
              model.simulationState.isRunning else {
            return .terminateNow
        }

        isFinishingTermination = true
        Task {
            await model.stopSimulation()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
