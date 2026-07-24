import SwiftUI

struct TutorialStep: Identifiable {
    let id = UUID()
    let symbol: String
    let title: String
    let summary: String
    let details: [String]
    let caution: String?
}

struct TutorialView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var index = 0

    private let steps: [TutorialStep] = [
        TutorialStep(
            symbol: "cable.connector",
            title: "Connect with a cable",
            summary: "Plug the iPhone directly into this Mac.",
            details: [
                "Use a cable that carries data — charge-only cables will not work.",
                "Prefer a port on the Mac itself over an unpowered hub.",
                "Relocate never changes location over Wi-Fi. The wired developer connection is required."
            ],
            caution: nil
        ),
        TutorialStep(
            symbol: "lock.open.fill",
            title: "Unlock and tap Trust",
            summary: "The iPhone must trust this Mac before it accepts developer commands.",
            details: [
                "Unlock the iPhone with Face ID, Touch ID, or your passcode.",
                "When “Trust This Computer?” appears, tap Trust.",
                "Enter the device passcode to confirm."
            ],
            caution: "Missed the prompt? Unplug the cable, plug it back in, and keep the phone unlocked."
        ),
        TutorialStep(
            symbol: "hammer.fill",
            title: "Turn on Developer Mode",
            summary: "On the iPhone, open Settings → Privacy & Security → Developer Mode.",
            details: [
                "Toggle Developer Mode on.",
                "Tap Restart when iOS asks — the iPhone reboots.",
                "After it restarts, unlock it, tap Turn On, and enter your passcode."
            ],
            caution: "Developer Mode only appears once the iPhone has been connected to a Mac with developer tools at least once."
        ),
        TutorialStep(
            symbol: "iphone.gen3",
            title: "Keep it unlocked and connected",
            summary: "The developer session lives on the cable.",
            details: [
                "Leave the iPhone unlocked while a location is being simulated.",
                "Do not unplug the cable during a session.",
                "If the screen locks or the cable is pulled, the simulated location stops."
            ],
            caution: nil
        ),
        TutorialStep(
            symbol: "location.fill",
            title: "Simulate, then restore",
            summary: "Choose the device in Relocate, pick a spot, then press Set Location.",
            details: [
                "Search, or click anywhere on the map, to choose a point.",
                "Press Set Location to move the iPhone there.",
                "Press Stop to hand control back to the real GPS."
            ],
            caution: "iOS still reports the location as simulated. Relocate does not hide or bypass that."
        )
    ]

    private var step: TutorialStep { steps[index] }
    private var isLast: Bool { index == steps.count - 1 }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            stepContent
            Divider()
            footer
        }
        .frame(width: 620, height: 580)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text("iPhone Setup Tutorial")
                    .font(.title2.bold())
                Text("Step \(index + 1) of \(steps.count)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Close") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    private var stepContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.31, green: 0.55, blue: 1.0),
                                        Color(red: 0.48, green: 0.24, blue: 0.91)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        Image(systemName: step.symbol)
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 62, height: 62)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(step.title)
                            .font(.title3.bold())
                        Text(step.summary)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(step.details.enumerated()), id: \.offset) { position, detail in
                        HStack(alignment: .top, spacing: 11) {
                            Text("\(position + 1)")
                                .font(.caption2.bold())
                                .foregroundStyle(.white)
                                .frame(width: 20, height: 20)
                                .background(Circle().fill(.blue))
                            Text(detail)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                    }
                }

                if let caution = step.caution {
                    Label(caution, systemImage: "info.circle.fill")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                }

                if isLast {
                    readinessPanel
                }

                Spacer(minLength: 0)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var readinessPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Current status")
                .font(.subheadline.weight(.semibold))

            HStack(spacing: 9) {
                Image(systemName: model.dependencyAvailable ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(model.dependencyAvailable ? .green : .orange)
                Text(
                    model.dependencyAvailable
                        ? "Mac backend installed — you are ready to simulate."
                        : "The Mac-side backend (pymobiledevice3) is not installed yet."
                )
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }

            HStack(spacing: 9) {
                Image(systemName: model.selectedDevice == nil ? "circle.dashed" : "checkmark.circle.fill")
                    .foregroundStyle(model.selectedDevice == nil ? Color.secondary : Color.green)
                Text(model.selectedDevice.map { "Selected device: \($0.name)" } ?? "No device selected yet.")
                Spacer(minLength: 0)
            }

            if !model.dependencyAvailable {
                Button("Open Mac setup…") {
                    dismiss()
                    model.showSetup = true
                }
                .buttonStyle(.link)
            }
        }
        .font(.callout)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
    }

    private var footer: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                ForEach(steps.indices, id: \.self) { position in
                    Capsule()
                        .fill(position == index ? Color.accentColor : Color.secondary.opacity(0.28))
                        .frame(width: position == index ? 18 : 7, height: 7)
                        .animation(.easeInOut(duration: 0.2), value: index)
                }
            }

            Spacer()

            Button("Back") {
                withAnimation(.easeInOut(duration: 0.15)) { index -= 1 }
            }
            .disabled(index == 0)

            if isLast {
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Next") {
                    withAnimation(.easeInOut(duration: 0.15)) { index += 1 }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }
}
