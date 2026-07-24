import MapKit
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 320)
        } content: {
            MapWorkspaceView()
                .navigationSplitViewColumnWidth(min: 460, ideal: 720)
        } detail: {
            InspectorView()
                .navigationSplitViewColumnWidth(min: 300, ideal: 330, max: 380)
        }
        .navigationSplitViewStyle(.balanced)
        .background(Color(nsColor: .windowBackgroundColor))
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    model.showTutorial = true
                } label: {
                    Image(systemName: "questionmark.circle")
                }
                .help("Show the iPhone setup tutorial")

                DevicePicker()

                Button {
                    Task { await model.refreshDevices() }
                } label: {
                    if model.isRefreshing {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .help("Refresh connected devices")
                .disabled(model.isRefreshing)

                if model.simulationState.isRunning {
                    Button(role: .destructive) {
                        Task { await model.stopSimulation() }
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .help("Stop simulating and restore the real location")
                } else {
                    Button {
                        Task { await model.applySelectedLocation() }
                    } label: {
                        Label("Set Location", systemImage: "location.fill")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.canApply)
                    .help("Simulate the selected location on the connected device")
                }
            }
        }
        .sheet(isPresented: $model.showSetup) {
            SetupView()
        }
        .sheet(isPresented: $model.showTutorial) {
            TutorialView()
        }
    }
}

private struct DevicePicker: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Picker("Device", selection: $model.selectedDeviceID) {
            Text("Select device").tag(nil as String?)
            ForEach(model.devices) { device in
                Label {
                    Text(device.name)
                } icon: {
                    Image(systemName: device.symbol)
                }
                .tag(device.id as String?)
            }
        }
        .labelsHidden()
        .frame(width: 190)
    }
}

struct StatusBar: View {
    @Environment(AppModel.self) private var model

    private var statusColor: Color {
        switch model.simulationState {
        case .active, .playing: .green
        case .failed: .red
        case .preparing, .stopping: .orange
        case .idle: .secondary
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
                .shadow(color: statusColor.opacity(0.4), radius: 3)
            Text(model.lastMessage)
                .lineLimit(1)
            Spacer()
            if let device = model.selectedDevice {
                Label(device.kind == .physical ? "USB developer channel" : "CoreSimulator", systemImage: "lock.shield")
                    .foregroundStyle(.secondary)
            }
            Text(model.selectedPoint.coordinateLabel)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(.horizontal, 14)
        .frame(height: 30)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}
