import AppKit
import SwiftUI

struct SetupView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Physical iPhone Setup")
                        .font(.title2.bold())
                    Text("A transparent developer workflow—no jailbreak or system modification.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(24)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    SetupStep(
                        number: 1,
                        title: "Connect and trust",
                        detail: "Connect the iPhone directly by USB, unlock it, and tap Trust when prompted."
                    )
                    SetupStep(
                        number: 2,
                        title: "Enable Developer Mode",
                        detail: "On iPhone: Settings → Privacy & Security → Developer Mode. The device restarts and asks for confirmation."
                    )
                    SetupStep(
                        number: 3,
                        title: "Install the developer-service backend",
                        detail: "Relocate uses the open-source pymobiledevice3 CLI for Apple’s trusted developer channel on physical devices."
                    )

                    CommandCard(command: "brew install pipx && pipx install pymobiledevice3")

                    SetupStep(
                        number: 4,
                        title: "Prepare developer services",
                        detail: "With the phone connected and unlocked, mount the matching developer image once."
                    )
                    CommandCard(command: "pymobiledevice3 mounter auto-mount")

                    Label(
                        "Location remains marked as software-simulated by iOS. Use only on devices you own or are authorized to test.",
                        systemImage: "checkmark.shield"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .background(.blue.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
                }
                .padding(24)
            }

            Divider()
            HStack {
                Circle()
                    .fill(model.dependencyAvailable ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                Text(model.dependencyAvailable ? "Physical backend detected" : "Physical backend not yet detected")
                    .font(.caption)
                Spacer()
                Button("Check Again") {
                    Task {
                        model.dependencyAvailable = await LocationEngine().dependencyAvailable()
                        await model.refreshDevices()
                    }
                }
            }
            .padding(.horizontal, 24)
            .frame(height: 50)
        }
        .frame(width: 640, height: 660)
    }
}

private struct SetupStep: View {
    let number: Int
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(.blue))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).fontWeight(.semibold)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct CommandCard: View {
    let command: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "terminal")
                .foregroundStyle(.green)
            Text(command)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
            Spacer()
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(command, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.plain)
            .help("Copy command")
        }
        .padding(12)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.separator.opacity(0.5)))
    }
}

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section("Safety") {
                Label(
                    "Physical-device actions use the trusted Apple developer channel and remain detectable as simulated locations.",
                    systemImage: "checkmark.shield"
                )
            }
            Section("Developer Tools") {
                LabeledContent("Xcode", value: model.xcodeVersion)
                LabeledContent(
                    "Physical backend",
                    value: model.dependencyAvailable ? "Available" : "Not installed"
                )
                Button("Open Setup") { model.showSetup = true }
            }
            Section {
                Text("Relocate is intended for development and testing on devices you own or are authorized to use.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
