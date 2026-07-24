import SwiftUI

struct SidebarView: View {
    @Environment(AppModel.self) private var model
    @State private var importingGPX = false
    @State private var renaming: SavedPlace?
    @State private var draftName = ""

    var body: some View {
        List {
            Section("Devices") {
                if model.devices.isEmpty && !model.isRefreshing {
                    ContentUnavailableView {
                        Label("No devices", systemImage: "iphone.slash")
                    } description: {
                        Text("Connect an iPhone by cable or start an iOS Simulator.")
                    } actions: {
                        Button("Refresh") {
                            Task { await model.refreshDevices() }
                        }
                        Button("iPhone Tutorial") {
                            model.showTutorial = true
                        }
                        .buttonStyle(.link)
                    }
                    .frame(minHeight: 130)
                }

                ForEach(model.devices) { device in
                    DeviceRow(device: device)
                        .contentShape(Rectangle())
                        .onTapGesture { model.selectedDeviceID = device.id }
                }

                Button {
                    model.showSetup = true
                } label: {
                    Label("Connection setup", systemImage: "wrench.and.screwdriver")
                }
            }

            Section {
                if model.savedPlaces.isEmpty {
                    Text("Save a location from the map to keep it here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                } else {
                    ForEach(model.savedPlaces) { place in
                        SavedPlaceRow(place: place)
                            .contentShape(Rectangle())
                            .onTapGesture { model.select(point: place.point) }
                            .contextMenu {
                                Button("Use This Location") { model.select(point: place.point) }
                                Button("Add to Route") { model.addSavedPlaceToRoute(place) }
                                Divider()
                                Button("Rename…") {
                                    renaming = place
                                    draftName = place.name
                                }
                                Button("Move to Selected Coordinates") {
                                    model.updateSavedPlace(place)
                                }
                                Divider()
                                Button("Delete", role: .destructive) {
                                    model.deleteSavedPlace(place)
                                }
                            }
                    }
                    .onDelete(perform: model.deleteSavedPlaces)
                    .onMove(perform: model.moveSavedPlaces)
                }
            } header: {
                HStack {
                    Text("Saved Places")
                    Spacer()
                    Button {
                        model.saveSelectedPlace()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                    .disabled(model.selectedPointIsSaved)
                    .help(
                        model.selectedPointIsSaved
                            ? "This location is already saved"
                            : "Save the selected location"
                    )
                    .padding(.trailing, 6)
                }
            }

            Section {
                if model.route.isEmpty {
                    Text("Build a route by selecting locations on the map and adding waypoints.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                } else {
                    ForEach(Array(model.route.enumerated()), id: \.element.id) { index, point in
                        HStack(spacing: 9) {
                            Text("\(index + 1)")
                                .font(.caption2.bold())
                                .foregroundStyle(.white)
                                .frame(width: 20, height: 20)
                                .background(Circle().fill(.blue))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(point.name).lineLimit(1)
                                Text(point.coordinateLabel)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                    .onDelete(perform: model.removeRoutePoints)
                }
            } header: {
                Text("Route")
            } footer: {
                HStack {
                    Button("Import GPX") { importingGPX = true }
                    Spacer()
                    Button("Export") { model.exportGPX() }
                        .disabled(model.route.isEmpty)
                }
                .buttonStyle(.link)
                .font(.caption)
            }
        }
        .listStyle(.sidebar)
        .fileImporter(
            isPresented: $importingGPX,
            allowedContentTypes: [.xml, .data]
        ) { result in
            if case .success(let url) = result {
                model.importGPX(from: url)
            }
        }
        .alert(
            "Rename Place",
            isPresented: Binding(
                get: { renaming != nil },
                set: { if !$0 { renaming = nil } }
            )
        ) {
            TextField("Name", text: $draftName)
            Button("Cancel", role: .cancel) { renaming = nil }
            Button("Rename") {
                if let renaming { model.renameSavedPlace(renaming, to: draftName) }
                renaming = nil
            }
        }
    }
}

private struct SavedPlaceRow: View {
    let place: SavedPlace

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: place.symbol)
                .foregroundStyle(.blue)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(place.name).lineLimit(1)
                Text(place.point.coordinateLabel)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }
}

private struct DeviceRow: View {
    @Environment(AppModel.self) private var model
    let device: DeviceTarget

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(model.selectedDeviceID == device.id ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.10))
                Image(systemName: device.symbol)
                    .foregroundStyle(model.selectedDeviceID == device.id ? Color.accentColor : .secondary)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .fontWeight(model.selectedDeviceID == device.id ? .semibold : .regular)
                    .lineLimit(1)
                Text(device.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Circle()
                .fill(device.isAvailable ? Color.green : Color.gray)
                .frame(width: 7, height: 7)
        }
        .padding(.vertical, 3)
    }
}
