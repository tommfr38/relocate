import SwiftUI

struct InspectorView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Location")
                        .font(.title2.bold())
                    Text("Set a static point or build a timed route.")
                        .foregroundStyle(.secondary)
                }

                GroupBox("Coordinates") {
                    Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 12) {
                        GridRow {
                            Text("Latitude").foregroundStyle(.secondary)
                            TextField("Latitude", value: $model.selectedPoint.latitude, format: .number.precision(.fractionLength(0...7)))
                                .textFieldStyle(.roundedBorder)
                        }
                        GridRow {
                            Text("Longitude").foregroundStyle(.secondary)
                            TextField("Longitude", value: $model.selectedPoint.longitude, format: .number.precision(.fractionLength(0...7)))
                                .textFieldStyle(.roundedBorder)
                        }
                        GridRow {
                            Text("Label").foregroundStyle(.secondary)
                            TextField("Location name", text: $model.selectedPoint.name)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                    .padding(.top, 6)
                }

                GroupBox("Route Playback") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label(speedLabel, systemImage: transportSymbol)
                                .fontWeight(.medium)
                            Spacer()
                            Text("\(model.speedMetersPerSecond * 3.6, specifier: "%.0f") km/h")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $model.speedMetersPerSecond, in: 0.8...45)
                        HStack {
                            Button {
                                model.addSelectedToRoute()
                            } label: {
                                Label("Add Point", systemImage: "plus")
                            }
                            Button {
                                Task { await model.playRoute() }
                            } label: {
                                Label("Play Route", systemImage: "play.fill")
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!model.canPlayRoute)
                        }
                        .controlSize(.small)

                        if !model.route.isEmpty {
                            Button("Clear \(model.route.count) waypoints", role: .destructive) {
                                model.clearRoute()
                            }
                            .buttonStyle(.link)
                            .font(.caption)
                        }
                    }
                    .padding(.top, 6)
                }

                TargetReadinessCard()

                if case .failed(let message) = model.simulationState {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                }

                Spacer(minLength: 20)
            }
            .padding(20)
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.45))
    }

    private var speedLabel: String {
        switch model.speedMetersPerSecond {
        case ..<2: "Walking"
        case ..<7: "Cycling"
        case ..<22: "Driving"
        default: "High speed"
        }
    }

    private var transportSymbol: String {
        switch model.speedMetersPerSecond {
        case ..<2: "figure.walk"
        case ..<7: "bicycle"
        default: "car.fill"
        }
    }
}

private struct TargetReadinessCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        GroupBox("Target Readiness") {
            VStack(alignment: .leading, spacing: 10) {
                ReadinessRow(
                    title: "Xcode toolchain",
                    detail: model.xcodeVersion,
                    ready: model.xcodeVersion != "Not detected"
                )
                ReadinessRow(
                    title: "Device selected",
                    detail: model.selectedDevice?.name ?? "Choose a target",
                    ready: model.selectedDevice != nil
                )
                if model.selectedDevice?.kind == .physical {
                    ReadinessRow(
                        title: "Physical backend",
                        detail: model.dependencyAvailable ? "pymobiledevice3 available" : "Setup required",
                        ready: model.dependencyAvailable
                    )
                    Button("Review physical-device setup") {
                        model.showSetup = true
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
            }
            .padding(.top, 6)
        }
    }
}

private struct ReadinessRow: View {
    let title: String
    let detail: String
    let ready: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: ready ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(ready ? .green : .secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
